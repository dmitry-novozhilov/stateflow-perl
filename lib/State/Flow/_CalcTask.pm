package State::Flow::_CalcTask;

use strict;
use warnings;

sub new {
	my($class, $stateFlow, $record, $field) = @_;
	my $self = $class->SUPER::new($stateFlow, $record->table);
	$self->{record} = $record;
	$self->{field} = $field;
	return $self;
}

sub priority {3}

sub run {
	die "Not implemented";
}

1;
