#!/usr/bin/perl
use strict;
use warnings;
use Test::Spec;
use Clone qw/clone/;
use State::Flow;
use State::Flow::TestHelpers;
use Data::Dmp;

describe StandaloneBlog => sub {

    my $struct = require(__FILE__ =~ s/^(.*)\.t/.\/$1\.pm/r);

    shared_examples_for 'all dbh implementations' => sub {

        share my %shared_vars;
        my($sf);

        before all => sub {$ENV{STATEFLOW_AUTOCREATE_TABLES} = 'TEMP'};

        it 'init' => sub {
            $sf = State::Flow->new(
                dbh    => $shared_vars{dbh},
                struct => clone($struct),
            );
            ok !! $sf;
        };

        it 'create a new post' => sub {
            my %values = (text => 'POST TEXT', title => 'TITLE', ctime => time);
            my $created_post = $sf->write(posts => undef, \%values);
            is_deeply $created_post, {id => 1, comments_cnt => 0, likes_cnt => 0, dislikes_cnt => 0, uobj_type => 2, %values};
            my $read_post = $sf->read(posts => {id => $created_post->{id}});
            is_deeply $read_post, $created_post;
        };

    };

    describe_shared_example_for_each_dbms 'all dbh implementations';
};


runtests unless caller;
