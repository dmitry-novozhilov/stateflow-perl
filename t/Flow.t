#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::Spec;
use State::Flow;

describe Flow => sub {
    it _run => sub {

        my $required_task = bless {}, 'State::Flow::_Task::TestRequiredTask';
        $required_task->stubs({
            to_string       => 'required_task',
            done            => sub { shift->{done} },
        });
        State::Flow::_Task::TestRequiredTask->stubs(
            new             => $required_task,
            run             => sub {
                $_->{done} = 1 foreach shift->@*;
                return [], 1;
            },
            cluster_priority=> 2,
            cluster_name    => 'required_task_cluster',
        );

        my $target_task = bless {}, 'State::Flow::_Task::TestTargetTask';
        $target_task->stubs({
            to_string           => 'target_task',
            record              => undef,
            done                => sub { shift->{done} },
        });
        State::Flow::_Task::TestTargetTask->stubs(
            new                 => sub {
                is shift, 'State::Flow::_Task::TestTargetTask';
                cmp_deeply {@_}, {table => 'SomeTable', arg => 123, trx => 'TRX'};
                return $target_task;
            },
            run                 => sub {
                my($self) = shift->[0];
                return [ $self, $self->{required_task} = $required_task ], 1 if !$self->{required_task};
                return [ $self ], 0 if ! $self->{required_task}->{done};
                $self->{done} = 1;
                return [], 1;
            },
            cluster_priority    => 1,
            cluster_name        => 'target_task_cluster',
        );


        State::Flow::_Transaction->stubs(new => 'TRX');

        #local $ENV{STATEFLOW_DEBUG} = 1;
        State::Flow::_run({dbh => 'DBH', struct => 'STRUCT'}, TestTargetTask => SomeTable => arg => 123);

        ok $required_task->done;
        ok $target_task->done;
    };
};

runtests unless caller;
