use v5.18;
use warnings;
use Glib qw(TRUE FALSE);
use Glib::Object::Introspection;
use Data::Dumper;
use Carp;
use PDL;
use PDL::IO::GD;
use PDL::Image2D;
use Gtk3 '-init';
use Cairo::GObject;
use Cairo;
use App::Scope3D;

use Getopt::Long;

my $device = '/dev/video1';
my $location = '/tmp/capture/frame-%d-%09d.png';
my $seq = 0;

GetOptions('device|d=s' => \$device,
           'location|o=s' => \$location,
           'seq|q=i' => \$seq);

my $loop = Glib::MainLoop->new;

my $builder = Gtk3::Builder->new;
$builder->add_from_file('scope3d.glade');

my $window = $builder->get_object('main-window');
$window->show_all;

my $capture_area = $builder->get_object('capture-area');
my $variance_area = $builder->get_object('variance-area');
my $best_variance_area = $builder->get_object('best-variance-area');
my $result_area = $builder->get_object('result-area');

map { Glib::Object::Introspection->setup(basename => $_, version => '1.0', package => 'GStreamer') } qw'Gst GstBase';
GStreamer::init([$0, @ARGV]);
say 'Gst ', join '.', GStreamer::version();

my $pipeline = GStreamer::Pipeline->new('scope3d');

my %e;



sub location {
    my $l = $location;
    $l =~ s/(\%[0-9]*d)(?=.*\%[0-9]*d)/sprintf $1, $seq/e;
    say "saving frames as $l";
    $l;
}

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

lnes map mke($_), qw(v4l2src videoscale tee capsfilter queue videoconvert xvimagesink);
lnes tee => map mke($_), qw(queue pngenc multifilesink);
#lnes 'tee', map mke($_), qw(xvimagesink);

my $caps = GStreamer::Caps->new_empty_simple('video/x-raw');
$caps->set_value(width => gval int => 960);
$caps->set_value(height => gval int => 540);
#$caps->set_value(framerate => gval int => "30");
$e{capsfilter}->set(caps => $caps);

$e{multifilesink}->set(location => location());
$e{multifilesink}->set('post-messages' => 1);

$e{"queue'"}->set(leaky => 'downstream');
$e{pngenc}->set('compression-level' => 0);

$e{v4l2src}->set('device' => $device);
#$e{valve}->set('drop' => 1);

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

my $gaussian = 1/256 * pdl([ 1,  4,  6,  4,  1],
                           [ 4, 16, 24, 16,  4],
                           [ 6, 24, 36, 24,  6],
                           [ 4, 16, 24, 16,  4],
                           [ 1,  4,  6,  4,  1]);

my $capture_pdl;
my $variance_img_pdl;
my $best_variance_pdl;
my $best_variance_img_pdl;
my $result_pdl;




sub variance_to_gray_img {
    my $pdl = (shift() * 20.0)->convert(byte());
    cat($pdl, $pdl, $pdl)->reorder(2, 0, 1);
}

my $stopped;
my $process = 0;
my $redraw_queued;
my @capture_queue;
my $queue_size = 10;
sub new_png_available {
    return if $stopped;
    my $fn = shift;
    say "new_png_available: $fn";

    return unless $process;

    if (@capture_queue < $queue_size) {
        my $gd = PDL::IO::GD->new({filename => $fn});
        push @capture_queue, $gd->to_pdl;
    }
    elsif ($redraw_queued++) {
        say "Skipping frame!";
    }
    else {
        my $sum = float(shift @capture_queue);
        $sum += $_ for @capture_queue;
        $sum /= $queue_size;
        @capture_queue = ();
        $capture_pdl = byte($sum)->reorder(2, 0, 1);
        #my $variance_pdl = imgvar(10, $capture_pdl);
        #my $variance_pdl = conv2d imgdiff($capture_pdl), $gaussian, { Boundary => 'Replicate' };
        my $variance_pdl = imgdiff($capture_pdl);

        #say "variance: ", $variance_pdl->reshape(30, 30);
        $variance_img_pdl = variance_to_gray_img($variance_pdl);

        $best_variance_pdl //= $variance_pdl;
        $result_pdl //= $capture_pdl;

        say "variance dims: " . join('-', $variance_pdl->dims);
        
        imgbest($variance_pdl, $capture_pdl, $best_variance_pdl, $result_pdl);

        $best_variance_img_pdl = variance_to_gray_img($best_variance_pdl);

        $capture_area->queue_draw;
        $variance_area->queue_draw;
        $best_variance_area->queue_draw;
        $result_area->queue_draw;
    }
}

my $id = 0;
sub reset {
    say "Stopped";
    undef $capture_pdl;
    undef $result_pdl;
    undef $variance_img_pdl;
    undef $best_variance_pdl;
    undef $best_variance_img_pdl;
    undef $result_pdl;
    @capture_queue = ();
    $stopped = 1;
    $e{multifilesink}->set(location => "/tmp/drop.png");;

}

sub record {
    if ($stopped) {
        $stopped = 0;
        say "Starting recording";
        $seq++;
        $e{multifilesink}->set(location => location());
        $e{multifilesink}->set(index => 0);
        #$e{valve}->set('drop', 1);
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

$capture_area->signal_connect(draw => sub { draw_pdl($capture_pdl, @_);});
$variance_area->signal_connect(draw => sub { draw_pdl($variance_img_pdl, @_)});
$best_variance_area->signal_connect(draw => sub { draw_pdl($best_variance_img_pdl, @_)});
$result_area->signal_connect(draw => sub { draw_pdl($result_pdl, @_); undef $redraw_queued});


$builder->get_object('stop-button')->signal_connect('clicked' => \&reset);
$builder->get_object('record-button')->signal_connect('clicked' => \&record);
my $process_button = $builder->get_object('process-button');
$process_button->signal_connect('toggled' => sub { $process = $process_button->get('active') });

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
