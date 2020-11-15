use strict;
use warnings;
use Test::Spec;
use State::Flow;


describe "One record manipulations:" => sub {
	spec_helper "../helper.pl";
	share my %share;
	
	it "Fetch existing record" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
				},
			},
			$share{dbh},
			log_level => 'ERROR',
		);
		
		$share{dbh}->do("INSERT INTO state_flow_test_table_a SET a_id = 2, a_val = 22");
		
		my $result = $sf->fetch(state_flow_test_table_a => [[a_id => '=' => 2]]);
		
		cmp_deeply($result, {a_id => 2, a_val => 22});
	};
	
	it "Attempt to fetch not existsing record" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
				},
			},
			$share{dbh},
			log_level => 'ERROR',
		);
		
		my $result = $sf->fetch(state_flow_test_table_a => [[a_id => '=' => 2]]);
		
		is($result, undef);
	};
	
	it "Create new record" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
				},
			},
			$share{dbh},
			log_level => 'ERROR',
		);
		
		$sf->update(state_flow_test_table_a => undef, {a_id => 3, a_val => 33});
		
		cmp_deeply(
			$share{dbh}->selectall_arrayref("SELECT * FROM state_flow_test_table_a", {Slice=>{}}),
			[{a_id => 3, a_val => 33}],
		);
	};
	
	it "Update existing record" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
				},
			},
			$share{dbh},
			log_level => 'ERROR',
		);
		
		$share{dbh}->do("INSERT INTO state_flow_test_table_a SET a_id = 4, a_val = 44");
		
		$sf->update(state_flow_test_table_a => [[qw(a_id = 4)]], {a_val => 400});
		
		cmp_deeply(
			$share{dbh}->selectall_arrayref("SELECT * FROM state_flow_test_table_a", {Slice=>{}}),
			[{a_id => 4, a_val => 400}],
		);
	};
	
	it "Delete existing record" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
				},
			},
			$share{dbh},
			log_level => 'ERROR',
		);
		
		$share{dbh}->do("INSERT INTO state_flow_test_table_a SET a_id = 4, a_val = 44");
		
		$sf->update(state_flow_test_table_a => [[qw(a_id = 4)]], undef);
		
		cmp_deeply(
			$share{dbh}->selectall_arrayref("SELECT * FROM state_flow_test_table_a", {Slice=>{}}),
			[],
		);
	};
};

runtests;
