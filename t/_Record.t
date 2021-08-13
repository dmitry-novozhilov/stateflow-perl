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
        is $r->initial_version, undef;
        is_deeply $r->current_version, {a=>1,b=>2};
        is $r->initial_version, undef;
    };

    it 'changing' => sub {
        my $r = State::Flow::_Record->new(test => {a=>1,b=>2,c=>3});
        is_deeply $r->current_version, {a=>1,b=>2,c=>3};
        is_deeply $r->initial_version, {a=>1,b=>2,c=>3};
        $r->_update({a=>11,b=>22});
        is_deeply $r->current_version, {a=>11,b=>22,c=>3};
        is_deeply $r->initial_version, {a=>1,b=>2,c=>3};
    };

    it 'deleting' => sub {
        my $r = State::Flow::_Record->new(test => {a=>1,b=>2,c=>3});
        is_deeply $r->current_version, {a=>1,b=>2,c=>3};
        is_deeply $r->initial_version, {a=>1,b=>2,c=>3};
        $r->_update(undef);
        is $r->current_version, undef;
        is_deeply $r->initial_version, {a=>1,b=>2,c=>3};
    };

    it 'multiple changes' => sub {
        my $r = State::Flow::_Record->new(test => undef, {b=>22,c=>33});
        is $r->initial_version, undef;
        $r->_update({a=>1,b=>2});
        is_deeply $r->current_version, {a=>1,b=>2,c=>33};
        is $r->initial_version, undef;
        $r->_update({a=>11,b=>22});
        is_deeply $r->current_version, {a=>11,b=>22,c=>33};
        is $r->initial_version, undef;
        $r->_update(undef);
        is $r->current_version, undef;
        is $r->initial_version, undef;
    };
};

runtests unless caller;
