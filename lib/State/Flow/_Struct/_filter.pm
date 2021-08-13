package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';

# -filter    => 'similarity.pos > similarity.neg * 10 && similarity.pos - similarity.net > 3',
sub _preinit_filter {
    my($self, $declaration, $t_name) = @_;

    my $filter = $declaration->{ $t_name }->{-filter};

    croak "$t_name.-filter must be a string with expression" unless ! ref($filter);
    $self->{ $t_name }->{filter} = $filter;
}

1;
