use strict;
use warnings;
use Test::Spec;
use State::Flow;

describe "Multi records manipulations:" => sub {
	spec_helper "../helper.pl";
	share my %share;
	it "Fetch multi records by '=' selector and non-uniq key" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
					indexes	=> [[qw(a_val)]], # TODO: это должно выясняться автоматически по выборкам
				},
			},
			$share{dbh},
			log_level => 'ERROR',
		);
	};
	xit "Fetch multi records by '>','<','>=','<=','!=' selectors";
};

runtests;
