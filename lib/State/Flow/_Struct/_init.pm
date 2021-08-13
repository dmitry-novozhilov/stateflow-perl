package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';
use Carp;
use List::Util qw/any/;

sub _init {
    my($self, $declaration) = @_;

    $self->_init_table($_ => $declaration->{ $_ }) foreach keys %$declaration;

    foreach my $init (map {"_init_$_"} qw/field const autoincrement user_field expr type max_length is_field_declaration_empty/) {
        foreach my $t_name (keys %$declaration) {
            foreach my $f_name (keys $declaration->{ $t_name }->%*) {

                next if substr($f_name, 0, 1) eq '-'; # skip table options

                $self->$init({
                    t_name          => $t_name,
                    f_name          => $f_name,
                    field           => $self->{ $t_name }->{fields}->{ $f_name },
                    f_declaration   => $declaration->{ $t_name }->{ $f_name },
                });
            }
        }
    }

    foreach my $option (qw/indexes selections/) {
        my $init = "_init_$option";
        foreach my $t_name (keys %$declaration) {
            $self->$init({
                t_name          => $t_name,
                table           => $self->{ $t_name },
                o_declaration   => $declaration->{ $t_name }->{ "-$option" },
            });
        }
    }

    foreach my $t_name (keys %$declaration) {
        foreach my $d_name (keys $declaration->{ $t_name }->%*) {
            my $d = delete $declaration->{ $t_name }->{ $d_name };
            next if ref($d) eq 'HASH' and not %$d;
            next if ref($d) eq 'ARRAY' and not @$d;
            next if not ref($d) and not $d;

            croak "$t_name.$d_name unexpected ".dmp($d);
        }
    }
}

sub _init_table {
    my($self, $t_name, $t_declaration) = @_;

    croak "$t_name name is invalid" unless _is_name_valid($t_name);
    croak "$t_name declaration isn't a hashref" if ref($t_declaration) ne 'HASH';
    croak "$t_name there is no fields" unless %$t_declaration;

    $self->{ $t_name } = {};
}

sub _init_field {
    my($self, $ctx) = @_;

    croak "$ctx->{t_name}.$ctx->{f_name} name is invalid" unless _is_name_valid($ctx->{f_name});

    if($ctx->{f_declaration}->{type} and ! exists TYPE_DEFAULT_VALUES()->{ $ctx->{f_declaration}->{type} }) {
        croak "$ctx->{t_name}.$ctx->{f_name} unknown type '$ctx->{f_declaration}->{type}'";
    }

    $self->{ $ctx->{t_name} }->{fields}->{ $ctx->{f_name} } = {type => delete $ctx->{f_declaration}->{type}};
}

sub _init_const {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{const};

    $ctx->{field}->{type} ||= _valid_type_of_value(min => $ctx->{f_declaration}->{const});
    $ctx->{field}->{const} = delete $ctx->{f_declaration}->{const};
}

sub _init_autoincrement {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{default} or $ctx->{f_declaration}->{default} ne 'AUTOINCREMENT';

    $ctx->{field}->{autoincrement} = 1;
    $ctx->{field}->{type} ||= 'uint64';
    delete $ctx->{f_declaration}->{default};
}

sub _init_user_field {
    my($self, $ctx) = @_;

    return if any {$_ ne 'default'} keys $ctx->{f_declaration}->%*;

    $ctx->{field}->{type} ||= _valid_type_of_value(max => $ctx->{f_declaration}->{default});
    $ctx->{field}->{default} = delete $ctx->{f_declaration}->{default};
}

sub _init_expr {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{expr};

    my($code, $links) = $self->_expr_parse($ctx->{t_name}, $ctx->{f_name}, delete $ctx->{f_declaration}->{expr});

    $ctx->{field}->{expr} = {
        code        => $code,
        in_links    => $links,
    };
}

sub _init_links {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{expr};

    foreach my $link (values $ctx->{field}->{expr}->{in_links}->%*) {
        # out_links
        $self->{ $link->{table} }->{fields}->{ $link->{field} }->{out_links}->{ $link->{name} } = $link;

        # out_match_conds
        foreach my $field (keys $link->{match_conds}->%*) {
            $self->{ $link->{table} }->{fields}->{ $field }->{out_match_conds}->{ $link->{name} } = $link;
        }

        # in_match_conds
        foreach my $field (values $link->{match_conds}->%*) {
            $self->{ $ctx->{t_name} }->{fields}->{ $field }->{in_match_conds}->{ $link->{name} } = $link;
        }
    }
}

sub _init_type {
    my($self, $ctx) = @_;

    unless($ctx->{field}->{type}) {
        croak "$ctx->{t_name}.$ctx->{f_name} type not defined and cannot be autodetermined from default or const or expr";
    }
}

sub _init_max_length {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{max_length};

    unless($ctx->{field}->{type} eq 'string') {
        croak "$ctx->{t_name}.$ctx->{f_name} doesn't support max_length, because it $ctx->{field}->{type} instead of string";
    }

    my $max_length = delete $ctx->{f_declaration}->{max_length};

    croak "$ctx->{t_name}.$ctx->{f_name}.max_length must be a number" if $max_length !~ /^\d+$/;
    croak "$ctx->{t_name}.$ctx->{f_name}.max_length must be a positive number" if $max_length <= 0;

    $ctx->{field}->{max_length} = $max_length;
}

sub _init_is_field_declaration_empty {
    my($self, $ctx) = @_;

    if($ctx->{f_declaration}->%*) {
        croak "$ctx->{t_name}.$ctx->{f_name} has unknown fields: ".dmp($ctx->{f_declaration});
    }
}

sub _init_indexes {
    my($self, $ctx) = @_;

    $ctx->{table}->{indexes} = {};

    return unless $ctx->{o_declaration};

    croak "$ctx->{t_name}.-indexes isn't a hashref" if ref($ctx->{o_declaration}) ne 'HASH';

    foreach my $i_name (keys $ctx->{o_declaration}->%*) {

        croak "$ctx->{t_name}.-indexes.$i_name name is invalid" unless _is_name_valid($i_name);

        my $index = delete $ctx->{o_declaration}->{ $i_name };

        if(ref($index) ne 'ARRAY') {
            croak "$ctx->{t_name}.-indexes.$i_name index must declares as arrayref instead of $index";
        }

        my $is_unique = (@$index and $index->[0] eq '-uniq');
        shift @$index if $is_unique;
        $ctx->{table}->{indexes}->{ $i_name }->{is_unique} = $is_unique;

        croak "$ctx->{t_name}.-indexes.$i_name haven't fields" if ! @$index;

        foreach my $field (@$index) {
            croak "$ctx->{t_name}.-indexes.$i_name unknown field $field" if ! exists $ctx->{table}->{fields}->{ $field };
            push $ctx->{table}->{indexes}->{ $i_name }->{fields}->@*, $field;
        }
    }
}

sub _init_selections {
    my($self, $ctx) = @_;

    $ctx->{table}->{selections} = {};

    return unless $ctx->{o_declaration};

    croak "$ctx->{t_name}.-selections isn't a hashref" if ref($ctx->{o_declaration}) ne 'HASH';

    foreach my $s_name (keys $ctx->{o_declaration}->%*) {

        croak "$ctx->{t_name}.-selections.$s_name name is invalid" unless _is_name_valid($s_name);

        my $selection = delete $ctx->{o_declaration}->{ $s_name };

        if(ref($selection) ne 'HASH') {
            croak "$ctx->{t_name}.-selections.$s_name selection must declares as hashref instead of $selection";
        }

        my %selection;

        my @requires_index_fields_begin;

        foreach my $w ((delete $selection->{where} || [])->@*) {
            croak "$ctx->{t_name}.-selections.$s_name.where.$w field not found" if ! exists $ctx->{table}->{fields}->{ $w };
            push $selection{where}->@*, $w;
            push @requires_index_fields_begin, $w;
        }

        my $order = 'ASC';
        foreach my $o ((delete $selection->{order} || [])->@*) {
            if($o eq '-asc') {
                $order = 'ASC';
            }
            elsif($o eq '-desc') {
                $order = 'DESC';
            }
            else {
                croak "$ctx->{t_name}.-selections.$s_name.order.$o field not found" if ! exists $ctx->{table}->{fields}->{ $o };
                push $selection{order}->@*, $o, $order;
            }
            push @requires_index_fields_begin, $o;
        }

        my $possible_indexes = 0;
        foreach my $index (values $ctx->{table}->{indexes}->%*) {
            next if $index->{fields}->@* < @requires_index_fields_begin;
            my $found = 0;
            for my $q (0 .. $#requires_index_fields_begin) {
                $found++ if $index->{fields}->[ $q ] eq $requires_index_fields_begin[ $q ];
            }
            $possible_indexes++ if $found == @requires_index_fields_begin;
        }
        croak "$ctx->{t_name}.-selections.$s_name has no index" unless $possible_indexes;


        croak "$ctx->{t_name}.-selections.$s_name has unexpected fields: ".dmp($selection) if %$selection;
    }

    # TODO: при отсутствии индекса делать вид, что он задекларирован
    # TODO: если среди полей выборки есть все поля какого-то уникального индекса, считать, что индекс есть
    # TODO: заменить декларацию индексов декларацией констрейнтов uniq (то же самое, но все индексы уникальные)
}

sub _valid_type_of_value {
    my($sort, $value) = @_;

    my @int_sizes = (8, 16, 32, 64);
    @int_sizes = reverse @int_sizes if $sort eq 'max';

    die "Can't determine type from undefined value" if ! defined $value;

    return 'bool' if $value =~ /^[01]$/;

    if($value =~ /^\+?\d+$/) {
        foreach my $type (map {"uint$_"} @int_sizes) {
            return $type if $value <= TYPE_INT_LIMITS()->{ $type }->[1];
        }
    }

    if($value =~ /^-\d+$/) {
        foreach my $type (map {"int$_"} @int_sizes) {
            return $type if $value >= TYPE_INT_LIMITS()->{ $type }->[0];
        }
    }

    return 'float'.($sort eq 'min' ? '32' : '64') if $value =~ /^\d*\.\d+$/;

    return 'datetime' if defined Date->new($value);

    return 'string';
}

1;
