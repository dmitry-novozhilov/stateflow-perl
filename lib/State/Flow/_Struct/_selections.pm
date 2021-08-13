package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';

# -selections => { name => { where => [@fields], order => [-desc => @fields, -asc => @fields,..]
sub _preinit_selections {
    my($self, $declaration, $t_name) = @_;

    foreach my $s_name (keys $declaration->{ $t_name }->{-selections}->%*) {
        my %selection;
        my $s_declaration = $declaration->{ $t_name }->{-selections}->{ $s_name };
        croak "$t_name.-selections.$s_name isn't a hashref" if ref($s_declaration) ne 'HASH';

        foreach my $s_opt_name (keys %$s_declaration) {
            my $s_opt_value = $s_declaration->{ $s_opt_name };
            if($s_opt_name eq 'where') {
                croak "$t_name.-selections.$s_name.where isn't an arrayref" unless ref($s_opt_value) eq 'ARRAY';
                $selection{where} = $s_opt_value;
            }
            elsif($s_opt_name eq 'order') {
                my @order;
                croak "$t_name.-selections.$s_name.order isn't an arrayref" unless ref($s_opt_value) eq 'ARRAY';
                my $order = 'ASC';
                foreach my $o (@$s_opt_value) {
                    if(substr($o, 0, 1) eq '-') {
                        if($o eq '-asc') {
                            $order = 'ASC';
                        }
                        elsif($o eq '-desc') {
                            $order = 'DESC';
                        }
                        else {
                            croak "$t_name.-selections.$s_name.order.$o: unknown option";
                        }
                    } else {
                        push @order, $o, $order;
                    }
                }
                croak "$t_name.-selections.$s_name.order declared but has no fields" unless @order;
                $selection{order} = \@order;
            }
            else {
                croak "$t_name.-selections.$s_name.$s_opt_name: unknown option";
            }
        }

        croak "$t_name.-selections.$s_name.where has no fields" unless $selection{where};

        $self->{ $t_name }->{selections}->{ $s_name } = \%selection;
    }
}

1;
