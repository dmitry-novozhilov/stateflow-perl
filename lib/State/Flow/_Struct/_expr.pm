package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';
use Carp qw/croak/;
use List::Util qw/any/;
use Data::Dmp;

# @param text of the expression
# @result arrayref with parsed tokens, where token is hashref with:
#   type    - type of token (NAME, DIGIT, STRING, control signs)
#   value   - value of token
sub _tokenize {
    my @tokens;
    my $line = 1;
    my $column = 0;
    my $cur_token;
    for(my $q = 0; $q < length($_[0]); $q++) {
        my $c = substr($_[0], $q, 1);
        $column++;
        if($c eq "\n") {
            $column = 0;
            $line++;
        }

        if(! $cur_token) {
            if($c =~ /^[a-zA-Z_]$/) {
                $cur_token = {type => 'NAME', value => $c};
            }
            elsif(grep {$c eq $_} qw#[ = ] . + - * / < > ( )#) {
                $cur_token = {type => $c};
            }
            elsif($c =~ /^\d$/) {
                $cur_token = {type => 'DIGIT', value => $c};
            }
            elsif($c eq '"' or $c eq '\'') {
                $cur_token = {type => 'STRING', terminator => $c, value => ''};
            }
            elsif($c =~ /\s/) {
                next;
            }
            else {
                die "$line:$column Unexpected symbol $c";
            }
            $cur_token->{line} = $line;
            $cur_token->{column} = $column;
            push @tokens, $cur_token;
        }
        elsif($cur_token->{type} eq 'NAME') {
            if($c =~ /^[a-zA-Z_0-9]$/) {
                $cur_token->{value} .= $c;
            } else {
                $cur_token = undef;
                redo;
            }
        }
        elsif(grep {$cur_token->{type} eq $_} qw#[ = ] . + - * / ( )#) {
            $cur_token = undef;
            redo;
        }
        elsif(grep {$cur_token->{type} eq $_} qw#< >#) {
            if($c eq '=') {
                $cur_token->{type} .= '=';
                $cur_token = undef;
            } else {
                $cur_token = undef;
                redo;
            }
        }
        elsif($cur_token->{type} eq 'DIGIT') {
            if($c =~ /^\d$/) {
                $cur_token->{value} .= $c;
            }
            elsif($c eq '.' and $cur_token->{value} !~ /\./) {
                $cur_token->{value} .= '.';
            }
            else {
                $cur_token = undef;
                redo;
            }
        }
        elsif($cur_token->{type} eq 'STRING') {
            my $escaped = delete $cur_token->{escaped};
            if(! $escaped and $c eq '\\') {
                $cur_token->{escaped} = 1;
            }
            elsif(! $escaped and $c eq $cur_token->{terminator}) {
                $cur_token = undef;
            }
            else {
                $cur_token->{value} .= $c;
            }
        }
        else {
            die "Unknown token type '$cur_token->{type}'";
        }
    }

    return \@tokens;
}

sub _expr_parse {
    my($self, $t_name, $f_name, $expr) = @_;

    my $tokens = _tokenize($expr);
    my %links;
    my $code = '';
    while(@$tokens) {
        if( @$tokens >= 2
            and $tokens->[0]->{type} eq 'NAME'
            and $tokens->[1]->{type} eq '['
        ) {
            my %link;

            $link{table} = shift(@$tokens)->{value};

            while(@$tokens >= 5
                and $tokens->[0]->{type} eq '['
                and (any {$tokens->[1]->{type} eq $_} qw/NAME DIGIT STRING/),
                and $tokens->[2]->{type} eq '=',
                and (any {$tokens->[3]->{type} eq $_} qw/NAME DIGIT STRING/),
                and $tokens->[4]->{type} eq ']'
            ) {
                shift @$tokens; # [
                my $left_token = shift @$tokens;
                shift @$tokens; # =
                my $right_token = shift @$tokens;
                shift @$tokens; # ]

                if($left_token->{type} eq 'NAME' and $self->{ $link{table} }->{fields}->{ $left_token->{value} }->{const}) {
                    $left_token->{const} = $self->{ $link{table} }->{fields}->{ $left_token->{value} }->{const};
                    $left_token->{type} = $self->{ $link{table} }->{fields}->{ $left_token->{value} }->{type}; # TODO: use it
                }

                if($right_token->{type} eq 'NAME' and $self->{ $t_name }->{fields}->{ $right_token->{value} }->{const}) {
                    $right_token->{const} = $self->{ $t_name }->{fields}->{ $right_token->{value} }->{const};
                    $right_token->{type} = $self->{ $t_name }->{fields}->{ $right_token->{value} }->{type}; # TODO: use it
                }


                foreach my $token ($left_token, $right_token) {
                    next if $token->{const};
                    next if $token->{type} eq 'NAME';
                    $token->{const} = $token->{value};
                    $token->{type} = 'string' if $token->{type} eq 'STRING'; # TODO: to force num to string in expr type
                }

                if(not exists $left_token->{const} and not exists $right_token->{const}) {
                    $link{match_conds}->{ $left_token->{value} } = $right_token->{value};
                }
                elsif(not exists $left_token->{const} and exists $right_token->{const}) {
                    $link{src_filters}->{ $left_token->{value} } = $right_token->{const};
                }
                elsif(exists $left_token->{const} and not exists $right_token->{const}) {
                    $link{dst_filters}->{ $right_token->{value} } = $left_token->{const};
                }
                else {
                    croak "$t_name.$f_name link to table $link{table} expecting match conds as "
                        ."field=field or field=const or const=field, but got const=const "
                        ."(".($left_token->{const} // 'undef').'='.($right_token->{const} // 'undef').")";
                }
            }

            if(not $link{match_conds} and not $link{src_filters} and not $link{dst_filters}) {
                croak "$t_name.$f_name link to table $link{table} expecting match conds, got "
                    .(@$tokens ? ($tokens->[0]->{value} // $tokens->[0]->{type}) : 'end of expression');
            }

            croak "$t_name.$f_name link to table $link{table} expecting dot, got end of expression" if ! @$tokens;
            if($tokens->[0]->{type} ne '.') {
                croak "$tokens->[0]->{line}:$tokens->[0]->{column} expecting dot, got "
                    .($tokens->[0]->{value} // $tokens->[0]->{type});
            }
            shift @$tokens;

            croak "expecting name, got end of expression" if ! @$tokens;
            if($tokens->[0]->{type} ne 'NAME') {
                croak "$tokens->[0]->{line}:$tokens->[0]->{column} expecting name, got "
                    .($tokens->[0]->{value} // $tokens->[0]->{type});
            }
            $link{field} = shift(@$tokens)->{value};

            if(@$tokens and $tokens->[0]->{type} eq '(') {
                $link{aggregate} = delete $link{field};
                if(@$tokens >= 2 and $tokens->[1]->{type} eq ')') {
                    # .func()
                    shift(@$tokens) for 1..2;
                }
                elsif(@$tokens >= 3 and $tokens->[1]->{type} eq 'NAME' and $tokens->[2]->{type} eq ')') {
                    $link{field} = $tokens->[1]->{value};
                    shift(@$tokens) for 1..3;
                }
                else {
                    croak "$tokens->[0]->{line}:$tokens->[0]->{column} expecting closing parenthesis maybe with name before";
                }
            }


            croak "$t_name.$f_name links to unknown table '$link{table}'" if ! exists $self->{ $link{table} };

            $link{name} = $link{table};

            foreach my $ext_field (sort keys $link{match_conds}->%*) {
                my $int_field = $link{match_conds}->{ $ext_field };

                croak "$t_name.$f_name using unknown field '$int_field' of this table in link to table $link{table}"
                    if ! exists $self->{ $t_name }->{fields}->{ $int_field };

                croak "$t_name.$f_name using unknown field '$ext_field' of linked table in link to table $link{table}"
                    if ! exists $self->{ $link{table} }->{fields}->{ $ext_field };

                $link{name} .= "[$ext_field=$int_field]";
            }

            foreach my $src_field (sort keys $link{src_filters}->%*) {
                my $const = $link{src_filters}->{ $src_field };

                croak "$t_name.$f_name using unknown field '$src_field' of linked table in link to table $link{table}"
                    if ! exists $self->{ $link{table} }->{fields}->{ $src_field };

                $link{name} .= "[$src_field=$const]";
            }

            foreach my $dst_field (sort keys $link{dst_filters}->%*) {
                my $const = $link{dst_filters}->{ $dst_field };

                croak "$t_name.$f_name using unknown field '$dst_field' of linked table in link to table $link{table}"
                    if ! exists $self->{ $t_name }->{fields}->{ $dst_field };

                $link{name} .= "[$const=$dst_field]";
            }

            if($link{aggregate}) {
                croak "$t_name.$f_name uses unknown aggregate function '$link{aggregate}' in link to table $link{table}"
                    if ! grep {$link{aggregate} eq $_} qw/count sum/;

                croak "$t_name.$f_name not specifies field as `sum` aggregate function parameter"
                    if $link{aggregate} eq 'sum' and ! $link{field};

                croak "$t_name.$f_name specifies field with `count` aggregate function parameter"
                    if $link{aggregate} eq 'count' and $link{field};

                $link{name} .= ".$link{aggregate}(".($link{field} // '').")";
            } else {
                croak "$t_name.$f_name not specifies field from $link{table} in link" if ! $link{field};

                $link{name} .= ".$link{field}";
            }

            croak "$t_name.$f_name links to unknown field $link{field} of table $link{table}"
                if $link{field} and ! exists $self->{ $link{table} }->{fields}->{ $link{field} };


            $link{name} .= "->$t_name";

            $links{ $link{name} } = \%link;

            $code .= '$_[0]->{"_sf_m13n_'.$link{name}.'"} ';
        }
        elsif(@$tokens and $tokens->[0]->{type} eq 'NAME') {
            $code .= '$_[0]->{'.shift(@$tokens)->{value}.'} ';
        }
        elsif(@$tokens and grep {$tokens->[0]->{type} eq $_} qw(DIGIT STRING)) {
            $code .= shift(@$tokens)->{value};
        }
        else{
            $code .= shift(@$tokens)->{type};
        }
    }

    {
        $code = 'sub { return '.$code.'}';
        #print "# code: $code\n";
        my $c = eval $code;
        die "Bad expression code '$code': $@" if $@;
        $code = $c;
    }

    return $code, \%links;
}

1;
