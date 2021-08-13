package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';

# -src => 'table'
# -src => ['table_a', 'table_b'] # tables must have an identical fields
# -src => ['table_a', 'table_b' => {field_a => 'expr', field_b => 'expr'} # if fields differs
sub _preinit_src {
    my($self, $declaration, $t_name) = @_;

    return if ! exists $declaration->{ $t_name }->{-src};

    my $src = $declaration->{ $t_name }->{-src};

    croak "$t_name.-src isn't an arrayref" unless ! ref($src) or ref($src) eq 'ARRAY';

    $src = [ $src ] if ! ref($src);

    my %src;
    my $last_table;
    foreach my $src_node (@$src) {
        if(ref($src_node) eq 'HASH') {
            croak "$t_name.-src unexpected fields mapping" unless $last_table;
            $src{ $last_table } = $src_node;
            $last_table = undef;
        }
        elsif(! ref($src_node)) {
            $last_table = $src_node;
            $src{ $src_node } = undef;
        }
        else {
            croak "$t_name.-src unexpected ".ref($src_node)."REF";
        }
    }

    $self->{ $t_name }->{src} = \%src;
}

1;
