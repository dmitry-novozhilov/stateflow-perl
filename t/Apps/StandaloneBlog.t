#!/usr/bin/perl
use strict;
use warnings;
use Test::Spec;
use Clone qw/clone/;
use State::Flow;
use State::Flow::TestHelpers;

describe StandaloneBlog => sub {

    my $struct = require(__FILE__ =~ s/^(.*)\.t/.\/$1\.pm/r);

    shared_examples_for "all dbh implementations" => sub {

        share my %shared_vars;
        my($sf, $post);

        it "init" => sub {
            $sf = State::Flow->new(
                dbh    => $shared_vars{dbh},
                struct => clone($struct),
            );
            ok !! $sf;
        };

        it "create a new post" => sub {
            $post = $sf->write(
                posts =>
                undef,
                {
                    text    => 'POST TEXT',
                    title   => 'TITLE',
                    ctime   => time,
                },
            );
            ok !! $post;
        };

    };

    describe_shared_example_for_each_dbms "all dbh implementations";
};


runtests unless caller;
