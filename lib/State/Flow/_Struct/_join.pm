package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';

# -join => {table => [@match], table => [@match]}
sub _preinit_join {
    my($self, $declaration, $t_name) = @_;

    croak "$t_name.-join must be a hashref" if ref($declaration->{ $t_name }->{-join}) ne 'HASH';

    foreach my $j_table (keys $declaration->{ $t_name }->{-join}->%*) {
        my $match = $declaration->{ $t_name }->{-join}->{ $j_table };
        croak "$t_name.-join.$j_table matches must be an arrayref" if ref($match) ne 'ARRAY';
        croak "$t_name.-join.$j_table.".ref($_)."REF unexpected" foreach grep {ref $_} @$match;
        $self->{ $t_name }->{join}->{ $j_table } = [ @$match ];
    }
}

1;
