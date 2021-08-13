package State::Flow::_Task::Write;

use strict;
use warnings FATAL => 'all';
use parent 'State::Flow::_Task';
use State::Flow::_Task::Read;

sub new {
    my($class, %args) = @_;

    return bless {
        %args,
        # There is only one cluster, because write tasks do nothing in DB until transaction commit, and on commit records clusterises by another logic
        cluster_name    => 'write',
    } => $class;
}

sub cluster_priority {1}

# bulk
sub run {
    my($tasks) = @_;

    my $effect = 0;
    my @new_tasks;

    my @tasks_ready_to_update;

    foreach my $task (@$tasks) {
        if($task->{match_conds}) {
            if($task->{read_task}) {
                if($task->{record} = $task->{read_task}->record) {
                    push @tasks_ready_to_update, $task;
                }
            } else {
                push @new_tasks, $task->{read_task} = State::Flow::_Task::Read->new(table => $task->{table}, match_conds => $task->{match_conds});
                $effect++;
            }
        } else {
            use Data::Dumper;
            say STDERR "task=".Dumper($task);
            $task->{record} = $task->{trx}->create_record($task->{table});
            push @tasks_ready_to_update, $task;
        }
    }

    foreach my $task (@tasks_ready_to_update) {
        my($before, $after) = $task->{trx}->update_record($task->{record}, $task->{changes});
        $effect++;

        # TODO: #v0.0.2 все изменённые тут записи наверное хотят сгенерить задания по обновлению связанных материализаций

    }

    return \@new_tasks, $effect;
}

1;
