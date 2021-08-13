package State::Flow::_Record;

use strict;
use warnings FATAL => 'all';
use Carp;

sub new {
    my($class, $table, @versions) = @_;

    croak "You creating useless record" if ! $versions[-1];

    Internals::SvREADONLY(@versions, 1);

    return bless {
        table       => $table,
        versions    => \@versions,
    } => $class;
}

sub table {shift->{table}}

# Returns current version values (readonly!)
sub current_version { shift->{versions}->[-1] }

# Returns initial version values (readonly!)
sub initial_version { shift->{versions}->[0] }

# Record updating. Call from State::Flow::_Transaction only allowed.
# Params:
#   0   - if it is creating of new record or updating of existing record: hashref of changes
#       - if it is deleting of record: undef
# Result:
#   0   - state before changes
#   1   - state after changes
sub _update {
    my($self, $changes) = @_;

    Internals::SvREADONLY($self->{versions}->@*, 0);

    if($changes) {
        use Data::Dumper;
        die "Can't update non-existent record ".Dumper($self) if ! $self->{versions}->[-1];
        push $self->{versions}->@*, { $self->{versions}->[-1]->%*, $changes->%* };
    } else {
        push @{ $self->{versions} }, undef;
    }
    Internals::SvREADONLY($self->{versions}->[-1], 1);

    Internals::SvREADONLY($self->{versions}->@*, 1);

    return $self->{versions}->[-2], $self->{versions}->[-1];
}

1;
