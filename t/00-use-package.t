#!/usr/bin/perl

use strict;
use warnings;
use Test::Spec;

it "Package can be used" => sub {
	require_ok("State::Flow");
};

runtests unless caller;
