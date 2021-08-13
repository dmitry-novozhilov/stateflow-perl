package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';

# -extends  => $parent_table_name # TODO multi parents
sub _preinit_extends {
    my($self, $declaration, $t_name) = @_;

    return if ! exists $declaration->{ $t_name }->{-extends};

    $self->{ $t_name }->{extends} = $declaration->{ $t_name }->{-extends};

    # TODO: in init! croak "$t_name.-extends unknown table $extends" unless exists $declaration->{ $extends };
}


1;
