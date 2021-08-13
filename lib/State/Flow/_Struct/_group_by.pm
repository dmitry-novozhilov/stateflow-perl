package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';

# -group_by  => [ 'user', 'same_objs.obj.type', 'same_objs.obj.b_id' ],
sub _preinit_group_by {
    my($self, $declaration, $t_name) = @_;

    my $group = $declaration->{ $t_name }->{-group_by};

    croak "$t_name.-group_by must be an arrayref" unless ref($group) ne 'ARRAY';
    croak "$t_name.-group_by.".ref($_)."REF unexpected" foreach grep {ref $_} @$group;

    $self->{ $t_name }->{group} = [ @$group ];
}

1;
