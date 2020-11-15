use strict;
use warnings;
use Test::Spec;
use State::Flow;


describe "Tables structure:" => sub {
	spec_helper "../helper.pl";
	share my %share;
	
	it "Upgrade tables by structure declaration" => sub {
		
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a1 => {}, a2 => {}},
					uniqs	=> [["a1","a2"]],
				},
			},
			$share{dbh},
			log_level => 'ERROR',
		);
		my($fields, $uniqs) = State::Flow::_TableInfo($share{dbh}, 'state_flow_test_table_a');
		cmp_deeply([sort keys %$fields], [qw(a1 a2)]);
		cmp_deeply($uniqs, {a1__a2 => ['a1', 'a2']});
		
		$sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a1 => {}, a3 => {}},
					uniqs	=> [["a1","a3"]],
				},
			},
			$share{dbh},
			log_level => 'ERROR',
		);
		($fields, $uniqs) = State::Flow::_TableInfo($share{dbh}, 'state_flow_test_table_a');
		cmp_deeply([sort keys %$fields], [qw(a1 a3)]);
		cmp_deeply($uniqs, {a1__a3 => ['a1', 'a3']});
	};
};

runtests;
