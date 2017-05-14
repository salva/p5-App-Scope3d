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

my $loop = Glib::MainLoop->new;

my $builder = Gtk3::Builder->new;
$builder->add_from_file('scope3d.glade');

my $window = $builder->get_object('main-window');
$window->show_all;

my $capturing_area = $builder->get_object('capturing-area');

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

my $last_pdl;

sub new_png_available {
    my $fn = shift;
    say "new_png_available: $fn";
    my $gd = PDL::IO::GD->new({filename => $fn});
    $last_pdl = $gd->to_pdl;
    #$last_pdl = PDL::pdl(PDL::byte(), [[[255, 0, 0], [255, 0, 0], [255, 0, 0]],
    #$last_pdl = pdl byte(), [[[255, 0, 0], [255, 0, 0], [255, 0, 0], [0, 0, 0 ]],
    #                         [[255, 0, 0], [255, 0, 0], [255, 0, 0], [0, 0, 0 ]],
    #                         [[255, 0, 0], [255, 0, 0], [255, 0, 0], [0, 0, 0 ]],
    #                         [[0, 255, 0], [0, 255, 0], [0, 255, 0], [0, 0, 0 ]],
    #                         [[0, 255, 0], [0, 255, 0], [0, 255, 0], [0, 0, 0 ]],
    #                         [[0, 255, 0], [0, 255, 0], [0, 255, 0], [0, 0, 0 ]],
    #                         [[0, 0, 255], [0, 0, 255], [0, 0, 255], [0, 0, 0 ]],
    #                         [[0, 0, 255], [0, 0, 255], [0, 0, 255], [0, 0, 0 ]],
    #                         [[0, 0, 255], [0, 0, 255], [0, 0, 255], [0, 0, 0 ]]];

    $capturing_area->queue_draw;
}

sub draw_capturing {
    if (defined $last_pdl) {
        my ($w, $h) = my @dims = $last_pdl->dims;
        #my $pdl = $last_pdl->xchg(0, 2);

        my $pdl = $last_pdl->reorder(2, 0, 1);

        say "dims: @dims";
        #my $stride = Cairo::Surface::stride_for_width("rgb32", $w);
        #my $stride = $w;
        #say "stride: $stride";
        #$last_pdl->reshape($stride, $h, 4);
        # my $surface = Cairo::ImageSurface->create_for_data(${$last_pdl->get_dataref}, 'rgb24', $w, $h, $stride);

        my ($da, $cr) = @_;
        my $daw = $da->get_allocated_width || 10;
        my $dah = $da->get_allocated_height || 10;
        my $sclw = $daw / $w;
        my $sclh = $dah / $h;


        my $scl = ($sclw < $sclh ? $sclw : $sclh);
        say "daw: $daw, dah: $dah, sclw: $sclw, sclh: $sclh, scl: $scl";

        #$cr->save;
        $cr->scale($scl, $scl);
        my $pixbuf = Gtk3::Gdk::Pixbuf->new_from_data(${$pdl->get_dataref}, 'rgb', 0, 8, $w, $h, $w * 3);
        Gtk3::Gdk::cairo_set_source_pixbuf($cr, $pixbuf, 0, 0);
        $cr->paint;
        #$cr->restore;
        return 0;
    }
}

$capturing_area->signal_connect(draw => \&draw_capturing);

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
