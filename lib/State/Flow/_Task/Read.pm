package State::Flow::_Task::Read;

use strict;
use warnings FATAL => 'all';
use parent 'State::Flow::_Task';

sub new {
    my($class, %args) = @_;

    my $self = bless {%args} => $class;

    my $index_name = $self->{trx}->values_to_index_name($self->{match_conds});
    $self->{cluster_name} = join(':', read => $self->{table}, $index_name);

    return $self;
}

sub to_string {sprintf "Task:Read{table=%s,record=%s}", map {$_[0]->{$_} // '<undef>'} qw/table record/}

sub cluster_priority {2 * (ref($_[0]) eq 'ARRAY' ? $_[0]->@* : 1)}

sub done {exists shift->{record}}

# bulk
sub run {
    my($tasks) = @_;

    my $effect = 0;
    my $trx = $tasks->[0]->{trx};

    my($exists, $records) = $trx->get($tasks->[0]->{table}, [map {$_->{match_conds}} @$tasks]);

    my @tasks2fetch;

    for my $q (0 .. $#$tasks) {
        if(defined $exists->[$q]) {
            $tasks->[$q]->{record} = $records->[$q];
            $effect++;
        } else {
            push @tasks2fetch, $tasks->[$q];
        }
    }

    return \@tasks2fetch, $effect if $effect;

    ($exists, $records) = $trx->fetch($tasks->[0]->{table}, [map {$_->{match_conds}} @tasks2fetch]);
    for my $q (0 .. $#$tasks) {
        $tasks->[$q]->{record} = $records->[$q];
        $effect++;
    }

    return [], $effect;
}


1;
