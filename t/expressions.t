use strict;
use warnings;
use Test::Spec;
use Data::Dumper;
use State::Flow;

describe "Expressions:" => sub {
	spec_helper "helper.pl";
	share my %share;
	
	it "Simple expression using save record" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
				},
				state_flow_test_table_b => {
					fields	=> {b_id => {}, b_val => {expr => q{ state_flow_test_table_a[ a_id = b_id ].a_val }}},
					uniqs	=> [[qw(b_id)]],
				},
			},
			$share{dbh},
		);
		
		$sf->update(state_flow_test_table_a => undef, {a => 2, a_val => 22});
		$sf->update(state_flow_test_table_b => undef, {b => 2});
		my $result = $sf->fetch(state_flow_test_table_b => [[b_id => '=' => 2]]);
		
		cmp_deeply( $result, { b_id => 2, b_val => 22 });
	};
	xit "Expression linked to second table";
	xit "Reactive expression update";
};

runtests;
