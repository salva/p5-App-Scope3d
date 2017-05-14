use 5.024001;
use PDL::Core::Dev;
use ExtUtils::MakeMaker;

my $package = ["app_scope3d.pd", "Scope3D", "App::Scope3D"];

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile( ABSTRACT => 'The surprising Scope3D',
               AUTHOR   => 'Salvador Fandiño <sfandino@yahoo.com>',
               LICENSE  => 'perl',
               pdlpp_stdargs($package),
);

sub MY::postamble { pdlpp_postamble($package) }
