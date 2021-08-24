#!/usr/bin/perl

use strict;
use warnings;
use Test::Spec;

describe _Record => sub {
    it 'use ok' => sub {require_ok('State::Flow::_Record')};

    it 'constructing with initial version' => sub {
        is_deeply(
            State::Flow::_Record->new(test => {a=>1,b=>2})->current_version,
            {a=>1,b=>2},
        );
    };

    it 'know his table' => sub {
        is State::Flow::_Record->new('test', {})->table, 'test';
    };

    it 'creating' => sub {
        my $r = State::Flow::_Record->new(test => undef, {a=>1,b=>2});
        is $r->last_saved_version, undef;
        is_deeply $r->current_version, {a=>1,b=>2};
        is $r->last_saved_version, undef;
    };

    it 'changing' => sub {
        my $r = State::Flow::_Record->new(test => {a=>1,b=>2,c=>3});
        is_deeply $r->current_version, {a=>1,b=>2,c=>3};
        is_deeply $r->last_saved_version, {a=>1,b=>2,c=>3};
        $r->update({a=>11,b=>22});
        is_deeply $r->current_version, {a=>11,b=>22,c=>3};
        is_deeply $r->last_saved_version, {a=>1,b=>2,c=>3};
    };

    it 'deleting' => sub {
        my $r = State::Flow::_Record->new(test => {a=>1,b=>2,c=>3});
        is_deeply $r->current_version, {a=>1,b=>2,c=>3};
        is_deeply $r->last_saved_version, {a=>1,b=>2,c=>3};
        $r->update(undef);
        is $r->current_version, undef;
        is_deeply $r->last_saved_version, {a=>1,b=>2,c=>3};
    };

    it 'multiple changes' => sub {
        my $r = State::Flow::_Record->new(test => undef, {b=>22,c=>33});
        is $r->last_saved_version, undef;
        $r->update({a=>1,b=>2});
        is_deeply $r->current_version, {a=>1,b=>2,c=>33};
        is $r->last_saved_version, undef;
        $r->update({a=>11,b=>22});
        is_deeply $r->current_version, {a=>11,b=>22,c=>33};
        is $r->last_saved_version, undef;
        $r->update(undef);
        is $r->current_version, undef;
        is $r->last_saved_version, undef;
    };
};

runtests unless caller;
