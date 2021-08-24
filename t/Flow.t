#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::Spec;
use State::Flow;

describe Flow => sub {
    it _run => sub {

        my %tasks;
        foreach my $t ([Target => 1], [Required => 2], [Autocommit => 2]) {
            my $task = bless {}, 'State::Flow::_Task::Test'.$t->[0].'Task';
            $task->stubs({
                to_string   => $t->[0].'Task',
                done        => sub {shift->{done}},
                record      => undef,
            });
            $tasks{$t->[0]} = $task;

            ('State::Flow::_Task::Test'.$t->[0].'Task')->stubs(
                new             => $task,
                run             => sub {
                    $_->{done} = 1 foreach shift->@*;
                    return [], 1;
                },
                cluster_priority=> $t->[1],
                cluster_name    => $t->[0].'_task_cluster',
            );
        }

        my $trx = mock();
        $trx->stubs(
            commit => undef,
            save_records => sub {return $tasks{Autocommit}->{done} ? [] : [$tasks{Autocommit}]},
        );
        State::Flow::_Transaction->stubs(new => $trx);

        State::Flow::_Task::TestTargetTask->stubs(
            new                 => sub {
                is shift, 'State::Flow::_Task::TestTargetTask';
                cmp_deeply {@_}, {table => 'SomeTable', arg => 123, trx => $trx};
                return $tasks{Target};
            },
            run                 => sub {
                my($self) = shift->[0];
                return [ $self, $self->{required_task} = $tasks{Required} ], 1 if !$self->{required_task};
                return [ $self ], 0 if ! $self->{required_task}->{done};
                $self->{done} = 1;
                return [], 1;
            },
        );


        #local $ENV{STATEFLOW_DEBUG} = 1;
        State::Flow::_run({dbh => 'DBH', struct => 'STRUCT'}, TestTargetTask => SomeTable => arg => 123);

        ok $tasks{Required}->done;
        ok $tasks{Target}->done;
        ok $tasks{Autocommit}->done;
    };
};

runtests unless caller;
