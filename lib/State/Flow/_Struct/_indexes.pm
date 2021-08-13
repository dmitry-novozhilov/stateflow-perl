package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';

# -indexes => { PRIMARY => [-uniq => @fields], some_name => [@fields] }
sub _preinit_indexes {
    my($self, $declaration, $t_name) = @_;

    return if ! exists $declaration->{ $t_name }->{-indexes};

    my $indexes = $declaration->{ $t_name }->{-indexes};

    croak "$t_name.-indexes isn't a hashref" if ref($indexes) ne 'HASH';
    foreach my $i_name (keys %$indexes) {
        croak "$t_name.-indexes.$i_name name is invalid" unless _is_name_valid($i_name);
        croak "$t_name.-indexes.$i_name isn't an arrayref"
            if ref($indexes->{ $i_name }) ne 'ARRAY';
        my @i_declaration = $indexes->{ $i_name }->@*;
        my $is_uniq = $i_declaration[0] eq '-uniq';
        shift @i_declaration if $is_uniq;
        croak "$t_name.-indexes.$i_name haven't fields" if ! @i_declaration;
        $self->{ $t_name }->{indexes}->{ $i_name } = {uniq => $is_uniq, fields => \@i_declaration};
    }
}

1;
