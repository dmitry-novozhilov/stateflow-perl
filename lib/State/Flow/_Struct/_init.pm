package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';
use Carp qw/cluck croak/;
use List::Util qw/any/;
use Const::Fast;

const my %TYPE_DEFAULT_VALUES => (
    int8    => 0,
    int16   => 0,
    int32   => 0,
    int64   => 0,
    uint8   => 0,
    uint16  => 0,
    uint32  => 0,
    uint64  => 0,
    float32 => 0,
    float64 => 0,
    string  => '',
    datetime=> 0,
    bool    => 0,
);

const my %TYPE_INT_LIMITS => (
    int8    => [-2 ** 8 / 2,    2 ** 8 / 2 - 1],
    int16   => [-2 ** 16 / 2,   2 ** 16 / 2 - 1],
    int32   => [-2 ** 32 / 2,   2 ** 32 / 2 - 1],
    int64   => [-2 ** 64 / 2,   2 ** 64 / 2 - 1],
    uint8   => [0,              2 ** 8],
    uint16  => [0,              2 ** 16],
    uint32  => [0,              2 ** 32],
    uint64  => [0,              2 ** 64],
);

sub _init {
    my($self, $declaration, $dbh) = @_;

    my $db = State::Flow::_DB->new($dbh);

    $self->_init_table($_ => $declaration->{ $_ }) foreach keys %$declaration;

    foreach my $init (map {"_init_$_"} qw/field const autoincrement user_field expr type max_length is_field_declaration_empty/) {
        foreach my $t_name (keys %$declaration) {
            foreach my $f_name (keys $declaration->{ $t_name }->%*) {

                next if substr($f_name, 0, 1) eq '-'; # skip table options

                $self->$init({
                    table           => $self->{ $t_name },
                    field           => $self->{ $t_name }->{fields}->{ $f_name },
                    f_declaration   => $declaration->{ $t_name }->{ $f_name },
                });
            }
        }
    }

    foreach my $option (qw/fields indexes selections autocreate_tables check_db/) {
        my $init = "_init_$option";
        foreach my $t_name (keys %$declaration) {
            $self->$init({
                table           => $self->{ $t_name },
                o_declaration   => $declaration->{ $t_name }->{ "-$option" },
                db              => $db,
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

    # TODO init 'extends'
}

sub _init_table {
    my($self, $t_name, $t_declaration) = @_;

    croak "$t_name name is invalid" unless _is_name_valid($t_name);
    croak "$t_name declaration isn't a hashref" if ref($t_declaration) ne 'HASH';
    croak "$t_name there is no fields" unless %$t_declaration;

    $self->{ $t_name } = {
        name       => $t_name,
        fields     => { map {$_ => { name => $_ }} grep {$_ !~ /^-/} keys $t_declaration->%* },
        indexes    => { map {$_ => { name => $_ }} keys $t_declaration->{'-indexes'}->%* },
        selections => { map {$_ => { name => $_ }} keys $t_declaration->{'-selections'}->%*},
    };
}

sub _init_field {
    my($self, $ctx) = @_;

    croak "$ctx->{table}->{name}.$ctx->{field}->{name} name is invalid" unless _is_name_valid($ctx->{field}->{name});

    if($ctx->{f_declaration}->{type} and ! exists $TYPE_DEFAULT_VALUES{ $ctx->{f_declaration}->{type} }) {
        croak "$ctx->{table}->{name}.$ctx->{field}->{name} unknown type '$ctx->{f_declaration}->{type}'";
    }

    $self->{ $ctx->{table}->{name} }->{fields}->{ $ctx->{field}->{name} }->{type} = delete $ctx->{f_declaration}->{type};
}

sub _init_const {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{const};

    $ctx->{field}->{type} ||= _valid_type_of_value(min => $ctx->{f_declaration}->{const});
    $ctx->{field}->{const} = $ctx->{field}->{default} = delete $ctx->{f_declaration}->{const};
}

sub _init_autoincrement {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{default} or $ctx->{f_declaration}->{default} ne 'AUTOINCREMENT';

    $ctx->{field}->{autoincrement} = 1;
    if($ctx->{table}->{autoincrement_field}) {
        croak "$ctx->{table}->{name} has two autoincrement fields: $ctx->{field} and $ctx->{table}->{autoincrement_field}";
    }
    $ctx->{table}->{autoincrement_field} = $ctx->{field}->{name};
    $ctx->{field}->{type} ||= 'uint64';
    delete $ctx->{f_declaration}->{default};
}

sub _init_user_field {
    my($self, $ctx) = @_;

    return if any {$_ ne 'default' and $_ ne 'const' and $_ ne 'expr'} keys $ctx->{f_declaration}->%*;

    $ctx->{field}->{type} ||= _valid_type_of_value(max => $ctx->{f_declaration}->{default});
    if(exists $ctx->{f_declaration}->{default}) {
        my $default = delete $ctx->{f_declaration}->{default};
        $ctx->{field}->{default} = $default unless exists $ctx->{field}->{default};
    }
}

use State::Flow::_Struct::_expr;
sub _init_expr {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{expr};

    my($code, $links) = $self->_expr_parse($ctx->{table}->{name}, $ctx->{field}->{name}, delete $ctx->{f_declaration}->{expr});

    $ctx->{field}->{expr} = {
        code        => $code,
        in_links    => $links,
    };

    unless($ctx->{field}->{type}) {
        croak "$ctx->{table}->{name}.$ctx->{field}->{name} expr type autodetection wasn't supported yet";
    }
    # TODO: автоматически вычислять тип в парсере выражения
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
            $self->{ $ctx->{table}->{name} }->{fields}->{ $field }->{in_match_conds}->{ $link->{name} } = $link;
        }
    }
}

sub _init_type {
    my($self, $ctx) = @_;

    unless($ctx->{field}->{type}) {
        croak "$ctx->{table}->{name}.$ctx->{field}->{name} type not defined and cannot be autodetermined"
            ." from default or const or expr";
    }

    unless(exists $ctx->{field}->{default}) {
        $ctx->{field}->{default} = $ctx->{field}->{autoincrement} ? undef : $TYPE_DEFAULT_VALUES{ $ctx->{field}->{type} };
    }
}

sub _init_max_length {
    my($self, $ctx) = @_;

    return if ! exists $ctx->{f_declaration}->{max_length};

    unless($ctx->{field}->{type} eq 'string') {
        croak "$ctx->{table}->{name}.$ctx->{field}->{name} doesn't support max_length, because it $ctx->{field}->{type} instead of string";
    }

    my $max_length = delete $ctx->{f_declaration}->{max_length};

    croak "$ctx->{table}->{name}.$ctx->{field}->{name}.max_length must be a number" if $max_length !~ /^\d+$/;
    croak "$ctx->{table}->{name}.$ctx->{field}->{name}.max_length must be a positive number" if $max_length <= 0;

    $ctx->{field}->{max_length} = $max_length;
}

sub _init_is_field_declaration_empty {
    my($self, $ctx) = @_;

    if($ctx->{f_declaration}->%*) {
        croak "$ctx->{table}->{name}.$ctx->{field}->{name} has unknown fields: ".dmp($ctx->{f_declaration});
    }
}

sub _init_fields {
    my($self, $ctx) = @_;

    foreach my $f_name (keys $ctx->{table}->{fields}->%*) {
        $ctx->{table}->{defaults}->{ $f_name } = delete $ctx->{table}->{fields}->{ $f_name }->{default};
        $ctx->{table}->{fields_order} = [sort keys $ctx->{table}->{defaults}->%*];
    }
}

sub _init_indexes {
    my($self, $ctx) = @_;

    $ctx->{table}->{indexes} = {};

    return unless $ctx->{o_declaration};

    croak "$ctx->{table}->{name}.-indexes isn't a hashref" if ref($ctx->{o_declaration}) ne 'HASH';

    foreach my $i_name (keys $ctx->{o_declaration}->%*) {

        croak "$ctx->{table}->{name}.-indexes.$i_name name is invalid" unless _is_name_valid($i_name);

        my $index = delete $ctx->{o_declaration}->{ $i_name };

        if(ref($index) ne 'ARRAY') {
            croak "$ctx->{table}->{name}.-indexes.$i_name index must declares as arrayref instead of $index";
        }

        $ctx->{table}->{indexes}->{ $i_name }->{name} = $i_name;

        my $is_unique = (@$index and $index->[0] eq '-uniq');
        shift @$index if $is_unique;
        $ctx->{table}->{indexes}->{ $i_name }->{is_unique} = $is_unique;

        croak "$ctx->{table}->{name}.-indexes.PRIMARY cannot be non unique" if $i_name eq 'PRIMARY' and not $is_unique;

        croak "$ctx->{table}->{name}.-indexes.$i_name haven't fields" if ! @$index;

        foreach my $field (@$index) {
            unless(exists $ctx->{table}->{fields}->{ $field }) {
                croak "$ctx->{table}->{name}.-indexes.$i_name unknown field $field";
            }
            push $ctx->{table}->{indexes}->{ $i_name }->{fields}->@*, $field;
        }
    }
}

sub _init_selections {
    my($self, $ctx) = @_;

    $ctx->{table}->{selections} = {};

    return unless $ctx->{o_declaration};

    croak "$ctx->{table}->{name}.-selections isn't a hashref" if ref($ctx->{o_declaration}) ne 'HASH';

    foreach my $s_name (keys $ctx->{o_declaration}->%*) {

        croak "$ctx->{table}->{name}.-selections.$s_name name is invalid" unless _is_name_valid($s_name);

        my $selection = delete $ctx->{o_declaration}->{ $s_name };

        if(ref($selection) ne 'HASH') {
            croak "$ctx->{table}->{name}.-selections.$s_name selection must declares as hashref instead of $selection";
        }

        my %selection;

        my @requires_index_fields_begin;

        foreach my $w ((delete $selection->{where} || [])->@*) {
            unless(exists $ctx->{table}->{fields}->{ $w }) {
                croak "$ctx->{table}->{name}.-selections.$s_name.where.$w field not found";
            }
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
                unless(exists $ctx->{table}->{fields}->{ $o }) {
                    croak "$ctx->{table}->{name}.-selections.$s_name.order.$o field not found";
                }
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
        croak "$ctx->{table}->{name}.-selections.$s_name has no index" unless $possible_indexes;


        croak "$ctx->{table}->{name}.-selections.$s_name has unexpected fields: ".dmp($selection) if %$selection;
    }
}

sub _init_autocreate_tables {
    my($self, $ctx) = @_;
    return if ! $ENV{STATEFLOW_AUTOCREATE_TABLES};
    unless(any {$ENV{STATEFLOW_AUTOCREATE_TABLES} eq $_} qw/PERSIST TEMP/) {
        cluck "Unknown STATEFLOW_AUTOCREATE_TABLES='$ENV{STATEFLOW_AUTOCREATE_TABLES}'";
    }

    $ctx->{db}->create_table($ctx->{table}, $ENV{STATEFLOW_AUTOCREATE_TABLES});
}

sub _init_check_db {
    my($self, $ctx) = @_;

    my $errors = $ctx->{db}->check_table($ctx->{table});
    croak "$ctx->{table}->{name} errors in database:\n".join("\n", @$errors) if @$errors;
}

sub _valid_type_of_value {
    my($sort, $value) = @_;

    my @int_sizes = (8, 16, 32, 64);
    @int_sizes = reverse @int_sizes if $sort eq 'max';

    die "Can't determine type from undefined value" if ! defined $value;

    return 'bool' if $value =~ /^[01]$/;

    if($value =~ /^\+?\d+$/) {
        foreach my $type (map {"uint$_"} @int_sizes) {
            return $type if $value <= $TYPE_INT_LIMITS{ $type }->[1];
        }
    }

    if($value =~ /^-\d+$/) {
        foreach my $type (map {"int$_"} @int_sizes) {
            return $type if $value >= $TYPE_INT_LIMITS{ $type }->[0];
        }
    }

    return 'float'.($sort eq 'min' ? '32' : '64') if $value =~ /^\d*\.\d+$/;

    return 'datetime' if defined Date->new($value);

    return 'string';
}

1;
