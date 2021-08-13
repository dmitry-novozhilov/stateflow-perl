#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::Spec;
use DBI;
use State::Flow::_Transaction;
use State::Flow::TestHelpers;

describe _Transaction => sub {

    shared_examples_for 'all dbh implementations' => sub {

        share my %shared_vars;

        my $table_name;
        before each => sub { $table_name = 'stateflow_test_'.int rand 1e6 };

        describe 'records manipulations' => sub {

            my($table_info, $trx);
            before each => sub {

                $table_info = {
                    $table_name => {
                        indexes    => {a => {is_unique => 1, fields => ['a']}},
                    },
                };

                $shared_vars{dbh}->do("CREATE TABLE $table_name (a INTEGER PRIMARY KEY, b TEXT)");

                $trx = State::Flow::_Transaction->new($shared_vars{dbh}, $table_info);
            };


            describe 'fetch an existing row' => sub {

                my ($exists, $records);
                before sub {
                    $shared_vars{dbh}->do("INSERT INTO $table_name (a, b) VALUES (123, 'test')");
                    ($exists, $records) = $trx->fetch($table_name, [{ a => 123 }]);
                };

                it 'return "existed"' => sub { is_deeply $exists, [1] };
                it 'return one record' => sub { cmp_deeply( $records, [Isa('State::Flow::_Record')])};
                it 'with a right data in fields' => sub {
                    is_deeply $records->[0]->current_version // undef, { a => 123, b => 'test' };
                };
            };

            describe 'get a cached row' => sub {
                my ($exists, $records);
                before sub {
                    $shared_vars{dbh}->do("INSERT INTO $table_name (a, b) VALUES (123, 'test')");
                    $trx->fetch($table_name, [{ a => 123 }]);
                    $shared_vars{dbh}->do("UPDATE $table_name SET b = 'zzz' WHERE a = 123");
                    ($exists, $records) = $trx->get($table_name, [{ a => 123 }]);
                };

                it 'return "existed"' => sub { is_deeply $exists, [1] };
                it 'return one record' => sub { cmp_deeply( $records, [Isa('State::Flow::_Record')])};
                it 'with a right data in fields' => sub {
                    is_deeply $records->[0]->current_version // undef, { a => 123, b => 'test' };
                };
            };

            describe 'after record changed' => sub {

                my($orig_record);
                before sub {
                    $shared_vars{dbh}->do("INSERT INTO $table_name (a, b) VALUES (123, 'test')");
                    $orig_record = $trx->fetch($table_name, [{a => 123}])->[0];
                    $trx->update_record($orig_record, {a => 111});
                };

                describe 'get by old key' => sub {
                    my($exists, $records);
                    before sub {($exists, $records) = $trx->get($table_name, [{a => 123}])};
                    it 'return "existed" because it was' => sub {cmp_deeply $exists, [!!0]};
                    it 'return no record' => sub { cmp_deeply $records, [undef] };
                };

                describe 'get by new key' => sub {
                    my($exists, $records);
                    before sub {($exists, $records) = $trx->get($table_name, [{a => 111}])};
                    it 'return "existed"' => sub { is_deeply $exists, [1] };
                    it 'return one record' => sub { cmp_deeply( $records, [Isa('State::Flow::_Record')]) };
                    it 'with a right data in fields' => sub {
                        is_deeply $records->[0]->current_version // undef, { a => 111, b => 'test' };
                    };
                    it 'and it\'s a original record object' => sub {is $records->[0], $orig_record};
                };
            };

            after each => sub {
                $trx->rollback();
                $shared_vars{dbh}->do("DROP TABLE $table_name");
            };
        };

        describe "DB writes" => sub {
            my($table_info, $trx);
            before each => sub {
                $table_info = {
                    $table_name => {
                        indexes    => {
                            a    => { is_unique => 1, fields => [ 'a' ] },
                            b_c    => { is_unique => 1, fields => [ 'b', 'c' ] },
                        },
                    },
                };

                $shared_vars{dbh}->do("CREATE TABLE $table_name (a INTEGER PRIMARY KEY, b INTEGER, c INTEGER, UNIQUE (b,c))");

                $trx = State::Flow::_Transaction->new($shared_vars{dbh}, $table_info);
            };

            # TODO: write tests

            after each => sub {
                $shared_vars{dbh}->do("DROP TABLE $table_name");
            };
        };
    };

    describe_shared_example_for_each_dbms "all dbh implementations";
};

runtests unless caller;
