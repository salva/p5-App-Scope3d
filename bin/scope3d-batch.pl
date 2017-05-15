use strict;
use warnings;

use PDL;
use PDL::IO::GD;
use PDL::Image2D;
use Sort::Key::Natural qw(natsort);
use Getopt::Long;

use App::Scope3D;

$|=1;

my $seq;
my $n = 10;
my $infn = '/tmp/capture/frame-%09d.png';
my $outfn = '/tmp/out/frame-%d.png';
my $queue_size = 10;
#my $video;

GetOptions('in|i=s' => \$infn,
           'out|o=s' => \$outfn,
           'queue-size|s=i' => \$queue_size,
           'offset|f=i' => \$n,
           'seq|q=i' => \$seq );

while (1) {
    if ($seq) {
        last unless -f sprintf($infn, $seq, $n);
    }

    my @capture_queue;
    my $best;
    my $best_variance;
    my $nout = 0;
    my $nin = $n;
    while(1) {
        my $fn = (defined($seq) ? sprintf($infn, $seq, $nin) : sprintf($infn, $nin));
        $nin++;

        unless (-f $fn) {
            warn "file $fn not found, exiting\n";
            last;
        }

        push @capture_queue, PDL::IO::GD->new({filename =>  $fn})->to_pdl;

        if (@capture_queue >= $queue_size) {
            my $queue_avg = float(shift @capture_queue);
            $queue_avg += $_ for @capture_queue;
            $queue_avg /= $queue_size;
            my $frame = byte($queue_avg)->reorder(2, 0, 1);
            my $variance = imgdiff $frame;

            if (not defined $best) {
                $best_variance = $variance;
                $best = $frame;
            }
            else {
                imgbest $variance, $frame, $best_variance, $best;
            }

            my $max = max $best_variance;

            my $out1 = append $frame->reorder(1, 2, 0), $best->reorder(1, 2, 0);
            my $out2 = (append $variance, $best_variance) * 8;
            my $out3 = cat $out2, $out2, $out2;
            my $out4 = $out1->glue(1, $out3);
            print "nout: $nout\r";
            write_true_png(byte($out4),
                           (defined($seq) ? sprintf($outfn, $seq, $nout) : sprintf($outfn, $nout)));
            $nout++;
        }
    }

    last unless defined $seq;
    $seq++;
}

# make video as follows:
#  ffmpeg -r 60 -f image2 -s 1920x1080 -i /tmp/out/frame-%d.png -vcodec libx264 -crf 25  -pix_fmt yuv420p test.mp4
