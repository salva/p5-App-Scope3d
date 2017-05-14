use v5.18;
use warnings;
use Glib qw(TRUE FALSE);
use Glib::Object::Introspection;
use Data::Dumper;
use Carp;
use PDL;
use PDL::IO::GD;
use Gtk3 '-init';
use Cairo::GObject;
use Cairo;
use App::Scope3D;

my $loop = Glib::MainLoop->new;

my $builder = Gtk3::Builder->new;
$builder->add_from_file('scope3d.glade');

my $window = $builder->get_object('main-window');
$window->show_all;

my $capture_area = $builder->get_object('capture-area');
my $variance_area = $builder->get_object('variance-area');
my $result_area = $builder->get_object('result-area');

map { Glib::Object::Introspection->setup(basename => $_, version => '1.0', package => 'GStreamer') } qw'Gst GstBase';
GStreamer::init([$0, @ARGV]);
say 'Gst ', join '.', GStreamer::version();

my $pipeline = GStreamer::Pipeline->new('miscroscope');

my %e;

sub mke {
    my ($name, $type) = @_;
    $type //= $name;
    $name .= "'" while exists $e{$name};
    my $e = GStreamer::ElementFactory::make($type, $name) // croak "Unable to create element $name of type $type";
    $pipeline->add($e);
    $e{$name} = $e;
    $name;
}

sub lnes {
    my $last;
    for (@_) {
        my $e = $e{$_};
        $last->link($e) if defined $last;
        $last = $e;
    }
}

sub gval ($$) {  # GValue wrapper shortcut
    Glib::Object::Introspection::GValueWrapper->new('Glib::'.ucfirst($_[0]) => $_[1]);
}

lnes map mke($_), qw(v4l2src queue pngenc multifilesink);

my $caps = GStreamer::Caps->new_empty_simple('video/x-raw');
$caps->set_value(width => gval int => 1000);
$caps->set_value(height => gval int => 600);
#$e{capsfilter}->set(caps => $caps);

$e{multifilesink}->set_property(location => '/tmp/capture/frame-%09d.png');
$e{multifilesink}->set_property('post-messages' => 1);

$e{queue}->set(leaky => 'upstream');
$e{pngenc}->set('compression-level' => 0);

$e{v4l2src}->set('device' => '/dev/video1');

no strict 'refs';
warn Dumper [sort grep //i, keys %{'Glib::Object::_Unregistered::GstXvImageSink::'}];

sub new_sample_cb {
    my $sink = shift;
    warn "new-sample: $sink";
    my $sample = $sink->signal_emit('pull-sample');
    #warn Dumper [\@GStreamer::Sample::ISA, \%{GStreamer::Sample::}];
    my $info = $sample->get_info;
    say "pull-sample returned: ", join(", ", $sample, $info, $sample->list_properties);
    'ok';
}

my $bus = $pipeline->get_bus;
$bus->add_signal_watch;

my $capture_pdl;
my $variance_img_pdl;
my $best_variance_pdl;
my $result_pdl;

sub new_png_available {
    my $fn = shift;
    say "new_png_available: $fn";
    unless (defined $capture_pdl) {
        my $gd = PDL::IO::GD->new({filename => $fn});
        $capture_pdl = $gd->to_pdl->reorder(2, 0, 1);

        my $variance_pdl = App::Scope3D::imgvar(3, $capture_pdl);
        #say "variance: ", $variance_pdl->reshape(30, 30);
        $variance_img_pdl = $variance_pdl->convert(byte());
        $variance_img_pdl = cat($variance_img_pdl, $variance_img_pdl, $variance_img_pdl)->reorder(2, 0, 1);

        $best_variance_pdl //= $variance_pdl;
        $result_pdl //= $capture_pdl;

        imgbest($variance_pdl, $capture_pdl, $best_variance_pdl, $result_pdl);

        $capture_area->queue_draw;
        $variance_area->queue_draw;
        $result_area->queue_draw;

        say "device name: " . $e{v4l2src}->get('device-name');
    }
}


sub draw_pdl {
    my ($pdl, $da, $cr) = @_;
    if (defined $pdl) {
        my (undef, $w, $h) = my @dims = $pdl->dims;
        say "dims: @dims";

        my $daw = $da->get_allocated_width || 10;
        my $dah = $da->get_allocated_height || 10;
        my $sclw = $daw / ($w || 10);
        my $sclh = $dah / ($h || 10);
        my $scl = ($sclw < $sclh ? $sclw : $sclh);
        say "daw: $daw, dah: $dah, sclw: $sclw, sclh: $sclh, scl: $scl";

        $cr->scale($scl, $scl);
        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_data(${$pdl->get_dataref}, 'rgb', 0, 8, $w, $h, $w * 3);
        Gtk3::Gdk::cairo_set_source_pixbuf($cr, $pixbuf, 0, 0);
        $cr->paint;
        return 0;
    }
}

$capture_area->signal_connect(draw => sub { draw_pdl($capture_pdl, @_); undef $capture_pdl});
$variance_area->signal_connect(draw => sub { draw_pdl($variance_img_pdl, @_)});
$result_area->signal_connect(draw => sub { draw_pdl($result_pdl, @_)});

$bus->signal_connect(message => sub { my ($bus, $message) = @_;
                                      my $st = $message->get_structure;
                                      if ($message->type eq 'eos') {
                                          $loop->quit;
                                      }
                                      elsif ($message->type eq 'error') {
                                          say "error: " . $st->get_string('debug');
                                      }
                                      elsif ($message->has_name('GstMultiFileSink')) {
                                          new_png_available($st->get_string('filename'));
                                      }
                                      TRUE });

$pipeline->set_state ('playing');
$loop->run;
$pipeline->set_state ('null');
