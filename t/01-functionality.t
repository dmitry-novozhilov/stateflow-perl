#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Test::Spec;
use State::Flow;
use DBI;

describe "Basic functionality:" => sub {
	my $dbh;
	before each => sub {
		$dbh = DBI->connect(
			"dbi:mysql:host=127.0.0.1;database=test",
			"test",
			"test",
			{
				PrintError			=> 0,
				RaiseError			=> 1,
				AutoInactiveDestroy	=> 1,
				HandleError			=> sub {
					my($error_msg, $hdl, $failed) = @_;
					if(ref($hdl) eq 'DBI::db' || ref($hdl) eq 'Apache::DBI::db') {
						$error_msg .= ' on ' . $hdl->{Name} . ", pid:$$, statement: " . $hdl->{Statement};
					}
					elsif(ref($hdl) eq 'DBI::st' || ref($hdl) eq 'Apache::DBI::st') {
						$error_msg .= ' on ' . $hdl->{Database}->{Name} . ", pid:$$, statement: " . $hdl->{Statement};
					}
					
					$error_msg .= ' placeholders: '.Data::Dumper->new([$hdl->{ParamValues}])->Indent(0)->Terse(1)->Pair('=>')->Quotekeys(0)->Sortkeys(1)->Dump();
					
					die $error_msg;
				},
				mysql_init_command 	=> "SET NAMES 'utf8'", # Это выполняется при каждом автореконнекте
			}
		) or die $DBI::errstr;
		
		$dbh->do("DROP TABLE IF EXISTS `state_flow_test_table_$_`") foreach qw(a b c);
	};
	
	after each => sub {
		$dbh->do("DROP TABLE IF EXISTS `state_flow_test_table_$_`") foreach qw(a b c);
		
		$dbh->disconnect();
	};
	
	it "Upgrade tables by structure declaration" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a1 => {}, a2 => {}},
					uniqs	=> [["a1","a2"]],
				},
			},
			$dbh,
		);
		my($fields, $uniqs) = State::Flow::_TableInfo($dbh, 'state_flow_test_table_a');
		cmp_deeply([sort keys %$fields], [qw(a1 a2)]);
		cmp_deeply($uniqs, {a1__a2 => ['a1', 'a2']});
		
		$sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a1 => {}, a3 => {}},
					uniqs	=> [["a1","a3"]],
				},
			},
			$dbh,
		);
		($fields, $uniqs) = State::Flow::_TableInfo($dbh, 'state_flow_test_table_a');
		cmp_deeply([sort keys %$fields], [qw(a1 a3)]);
		cmp_deeply($uniqs, {a1__a3 => ['a1', 'a3']});
	};
	
	it "Fetch existing record" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
				},
			},
			$dbh,
		);
		
		$dbh->do("INSERT INTO state_flow_test_table_a SET a_id = 2, a_val = 22");
		
		my $result = $sf->fetch(state_flow_test_table_a => [[a_id => '=' => 2]]);
		
		cmp_deeply($result, {a_id => 2, a_val => 22});
	};
	
	it "Create new record" => sub {
		my $sf = State::Flow->new(
			{
				state_flow_test_table_a	=> {
					fields	=> {a_id => {}, a_val => {}},
					uniqs	=> [[qw(a_id)]],
				},
			},
			$dbh,
		);
		
		$sf->update(state_flow_test_table_a => undef, {a_id => 3, a_val => 33});
		
		cmp_deeply(
			$dbh->selectall_arrayref("SELECT * FROM state_flow_test_table_a", {Slice=>{}}),
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
			$dbh,
		);
		
		$dbh->do("INSERT INTO state_flow_test_table_a SET a_id = 4, a_val = 44");
		
		$sf->update(state_flow_test_table_a => [[qw(a_id = 4)]], {a_val => 400});
		
		cmp_deeply(
			$dbh->selectall_arrayref("SELECT * FROM state_flow_test_table_a", {Slice=>{}}),
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
			$dbh,
		);
		
		$dbh->do("INSERT INTO state_flow_test_table_a SET a_id = 4, a_val = 44");
		
		$sf->update(state_flow_test_table_a => [[qw(a_id = 4)]], undef);
		
		cmp_deeply(
			$dbh->selectall_arrayref("SELECT * FROM state_flow_test_table_a", {Slice=>{}}),
			[],
		);
	};
	
	xit "Update multi records";
};

runtests unless caller;
