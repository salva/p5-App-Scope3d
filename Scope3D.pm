
#
# GENERATED WITH PDL::PP! Don't modify!
#
package App::Scope3D;

@EXPORT_OK  = qw( PDL::PP imgvar PDL::PP imgdiff PDL::PP imgbest );
%EXPORT_TAGS = (Func=>[@EXPORT_OK]);

use PDL::Core;
use PDL::Exporter;
use DynaLoader;



   
   @ISA    = ( 'PDL::Exporter','DynaLoader' );
   push @PDL::Core::PP, __PACKAGE__;
   bootstrap App::Scope3D ;








=head1 FUNCTIONS



=cut






=head2 imgvar

=for sig

  Signature: (int s(); byte a(c, h, w); float [o] v(h, w))


=for ref

info not available


=for bad

imgvar does not process bad values.
It will set the bad-value flag of all output piddles if the flag is set for any of the input piddles.


=cut






*imgvar = \&PDL::imgvar;





=head2 imgdiff

=for sig

  Signature: (byte a(c, h, w); float [o] v(h, w))


=for ref

info not available


=for bad

imgdiff does not process bad values.
It will set the bad-value flag of all output piddles if the flag is set for any of the input piddles.


=cut






*imgdiff = \&PDL::imgdiff;





=head2 imgbest

=for sig

  Signature: (float v(); byte img(c); float [o] best_v(); byte [o] best_img(c))


=for ref

info not available


=for bad

imgbest does not process bad values.
It will set the bad-value flag of all output piddles if the flag is set for any of the input piddles.


=cut






*imgbest = \&PDL::imgbest;



;



# Exit with OK status

1;

		   