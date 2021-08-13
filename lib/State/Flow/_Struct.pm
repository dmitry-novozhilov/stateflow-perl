package State::Flow::_Struct;

use strict;
use warnings FATAL => 'all';
use Carp; our @CARP_NOT = qw(State::Flow);


use State::Flow::_Struct::_init;

use State::Flow::_Struct::_extends;
use State::Flow::_Struct::_selections;
use State::Flow::_Struct::_indexes;
use State::Flow::_Struct::_expr;

use constant TYPE_DEFAULT_VALUES => {
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
};

use constant TYPE_INT_LIMITS => {
    int8    => [-2 ** 8 / 2,    2 ** 8 / 2 - 1],
    int16   => [-2 ** 16 / 2,   2 ** 16 / 2 - 1],
    int32   => [-2 ** 32 / 2,   2 ** 32 / 2 - 1],
    int64   => [-2 ** 64 / 2,   2 ** 64 / 2 - 1],
    uint8   => [0,              2 ** 8],
    uint16  => [0,              2 ** 16],
    uint32  => [0,              2 ** 32],
    uint64  => [0,              2 ** 64],
};


=pod
Struct declaration:    hash of tables (key - table name, value - Table declaration)
Table declaration:    hash with next fields:
    fields:        hash of fields (key - field name, value - field declaration)
    indexes:    hash of indexes (key - index name, value - index declaration)
Field declaration:    hash with next fields:
    type:        database definition for this field (ex: UNSIGNED INTEGER NOT NULL)
    validator:    coderef to value validator or array with such coderefs.
    expr:        text of expression on local DSL.

Field validator:    function with field value as single argument
                    and returning text of validation error if field value is invalid or undef otherwise.

Expression DSL:
    field_a + b - c / d * e % (f) + abs( sqrt ( g ** h ) ) + log( i, j ) + (k = l) + (m != n) + (o < p) + (r > d)
    + (t <= u) + (v | w) + x & z + aa xor ab + ~ac + ad << ae + af >> ag + ah && aj + ai || aj

    part_a := ...sub_expr...

    ext_table[int_field = ext_field]
        FROM ext WHERE ext_field = $int_field
        FROM int WHERE int_field = $ext_field
=cut

sub new {
    my($class, $declaration, $dbh) = @_;

    croak "Struct must be an hashref" if ref($declaration) ne 'HASH';
    croak "Struct is empty" unless %$declaration;

    my $self = bless {} => $class;

    $self->_init($declaration);



    # TODO proc 'extends'
    # TODO proc 'selections':
        # TODO check selection.where.fields

    return $self;
}

sub _is_name_valid {shift =~ /^[a-zA-Z_][a-zA-Z0-9_]*[a-zA-Z_]$/}

1;
