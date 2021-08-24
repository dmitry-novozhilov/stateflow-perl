package State::Flow;

use strict;
use warnings FATAL => 'all';
use Carp;

use Method::Bulk;
use State::Flow::_Task;
use State::Flow::_Transaction;
use State::Flow::_DB;
use State::Flow::_Struct;
use State::Flow::_Task::Read;
use State::Flow::_Task::Write;

our $VERSION = '0.0.1';

sub new {
    my($pkg, %args) = @_;

    croak "Argument 'dbh' doesn't specified" if ! $args{dbh};
    State::Flow::_DB::dbh_to_package($args{dbh}); # check DBD driver compatibility

    croak "Argument 'struct' doesn't specified" if ! $args{struct};

    return bless {
        dbh       => $args{dbh},
        struct    => State::Flow::_Struct->new($args{struct}, $args{dbh}),
    } => $pkg;
}

sub _run {
    my($self, $task_type, $table, @args) = @_;

    my $trx = State::Flow::_Transaction->new($self->{dbh}, $self->{struct});

    my $task = (__PACKAGE__.'::_Task::'.$task_type)->new(trx => $trx, table => $table, @args);

    my @prio2cluster2tasks;
    push $prio2cluster2tasks[ $task->cluster_priority ]->{ $task->cluster_name }->@*, $task;

    my %clusters_priorities = ($task->cluster_name => $task->cluster_priority);

    my $iter_num = 0;
    while(1) {
        $iter_num++;
        my $effect;
        my @new_tasks;
        foreach my $prio (0 .. $#prio2cluster2tasks) {
            print STDERR "DEBUG: iter=$iter_num prio=$prio" if $ENV{STATEFLOW_DEBUG};
            if(! $prio2cluster2tasks[ $prio ]) {
                print STDERR ": nothing -> skip\n" if $ENV{STATEFLOW_DEBUG};
                next;
            }

            # if(! $prio2cluster2tasks[ $prio ]->@*) {
            #     print STDERR "no clusters -> skip\n" if $ENV{STATEFLOW_DEBUG};
            #     $prio2cluster2tasks[ $prio ] = undef;
            #     next;
            # }

            my($cluster_name) = keys $prio2cluster2tasks[ $prio ]->%*;
            print STDERR " cluster=$cluster_name" if $ENV{STATEFLOW_DEBUG};

            my $tasks = delete $prio2cluster2tasks[ $prio ]->{ $cluster_name };
            $prio2cluster2tasks[ $prio ] = undef if ! $prio2cluster2tasks[ $prio ]->%*;
            delete $clusters_priorities{ $cluster_name };

            print STDERR " tasks: ".join(', ', map {$_->to_string} @$tasks)."\n" if $ENV{STATEFLOW_DEBUG};

            my $new_tasks;
            ($new_tasks, $effect) = bulk($tasks)->run();
            if($ENV{STATEFLOW_DEBUG}) {
                print STDERR "DEBUG:   ".($effect ? 'HAS' : 'NO')." effect, new tasks: "
                    .join(', ', map {$_->to_string} @$new_tasks)."\n";
            }
            push @new_tasks, @$new_tasks;


            last if $effect;
        }

        if(not $effect) {
            my $new_tasks = $trx->save_records();
            push @new_tasks, @$new_tasks;
            $effect += @$new_tasks;
        }

        if(@new_tasks) {
            my %cluster2new_tasks;
            push $cluster2new_tasks{ $_->cluster_name }->@*, $_ foreach @new_tasks;
            foreach my $new_cluster_name (keys %cluster2new_tasks) {
                print STDERR "DEBUG:   cluster $new_cluster_name priority= " if $ENV{STATEFLOW_DEBUG};
                my $old_cluster;
                if(my $old_cluster_priority = $clusters_priorities{ $new_cluster_name }) {
                    $old_cluster = delete $prio2cluster2tasks[ $old_cluster_priority ]->{ $new_cluster_name };
                    print STDERR $old_cluster_priority if $ENV{STATEFLOW_DEBUG};
                } else {
                    $old_cluster = [];
                    print STDERR "-" if $ENV{STATEFLOW_DEBUG};
                }

                my @new_cluster = ($cluster2new_tasks{ $new_cluster_name }->@*, @$old_cluster);

                my $new_cluster_priority = bulk(\@new_cluster)->cluster_priority();
                print STDERR " -> $new_cluster_priority tasks: ".join(', ', map {$_->to_string} @new_cluster)."\n" if $ENV{STATEFLOW_DEBUG};

                $prio2cluster2tasks[ $new_cluster_priority ]->{ $new_cluster_name } = \@new_cluster;
                $clusters_priorities{ $new_cluster_name } = $new_cluster_priority;

            }

        }

        last if not $effect;
    }

    $trx->commit();

    #warn Dumper($task); use Data::Dumper;

    return $task->record ? $task->record->current_version : undef;
}

=pod
@param table name;
@param match conds;
=cut
sub read { shift->_run(Read => shift, match_conds => shift, @_ ) }

=pod
@param table name;
@param match conds or undef to create new record;
@param new values hashref or undef for delete
=cut
sub write { shift->_run(Write => shift, match_conds => shift, changes => shift, @_) }

1;
