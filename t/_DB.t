#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use Test::Spec;
use Mock::Sub;
use State::Flow::_DB;

describe _DB => sub {

    it _match_conds_to_sql_where => sub {
        my $dbh = mock();
        $dbh->stubs(quote => sub {"'$_[1]'"});

        my $where = State::Flow::_DB::_match_conds_to_sql_where(
            {dbh => $dbh},
            [
                {a => 1, b => 2},
                {a => 1, b => 22},
                {a => 11,b => 2},
            ]
        );

        is $where, "((`a` = '1' AND (`b` = '2' OR `b` = '22')) OR (`a` = '11' AND (`b` = '2')))";
    };

    it _update_rows_gen_sql_sets => sub {
        my $set = State::Flow::_DB::_update_rows_gen_sql_sets(
            {1 => {2 => 12, 3 => 13}, 11 => 11},
            0,
            ['a', 'b'],
            'c',
        );
        ok $set =~ s/WHEN '2' THEN '12'/qqq/;
        ok $set =~ s/WHEN '3' THEN '13'/qqq/;
        ok $set =~ s/WHEN '1' THEN CASE `b` qqq qqq ELSE `c` END/qqq/;
        ok $set =~ s/WHEN '11' THEN '11'/qqq/;
        is $set, 'CASE `a` qqq qqq ELSE `c` END';
    };

    it _update_rows_get_sql_wheres => sub {
        my $wheres = State::Flow::_DB::_update_rows_get_sql_wheres({
            "a=1" => {"b=2" => undef, "b=3" => undef},
            "a=2" => undef,
        });
        ok $wheres =~ s/\((b=2 OR b=3|b=3 OR b=2)\)/bbb/;
        my @wheres = split / OR /, $wheres;
        ok !! grep {$_ eq '(a=1 AND bbb)'} @wheres;
        ok !! grep {$_ eq 'a=2'} @wheres;
    };

    describe queries => sub {
        my($db, $dbh, @do_calls);
        before sub {
            $dbh = mock();
            $dbh->expects('do')->returns(sub {push @do_calls, \@_; return 1});
            $dbh->stubs(quote => sub {"'$_[1]'"});
            $db = bless {dbh => $dbh} => 'State::Flow::_DB';
        };
        before each => sub {@do_calls = ()};

        it 'delete_rows by single field' => sub {
            $db->delete_rows(ttt => [{a => 1}, {a => 2}]);
            cmp_deeply \@do_calls, [[$dbh, q|DELETE FROM `ttt` WHERE (`a` = '1' OR `a` = '2')|]];
        };

        it 'delete_rows by multi fields' => sub {
            $db->delete_rows(ttt => [{a => 1, b => 2}, {a => 3, b => 4}]);
            cmp_deeply \@do_calls, [[$dbh, q|DELETE FROM `ttt` WHERE ((`a` = '1' AND (`b` = '2')) OR (`a` = '3' AND (`b` = '4')))|]];
        };

        it 'insert rows common' => sub {
            $db->insert_rows(ttt => ['a','b'], [[1,2],[3,4]]);
            cmp_deeply \@do_calls, [[$dbh, q|INSERT INTO `ttt` (`a`, `b`) VALUES ('1', '2'), ('3', '4')|]];
        };

        it 'insert rows SQLite' => sub {
            State::Flow::_DB::SQLite::insert_rows($db, ttt => ['a','b'], [[1,2],[3,4]]);
            cmp_deeply \@do_calls, [[$dbh, q|INSERT INTO `ttt` (`a`, `b`) VALUES ('1', '2'), ('3', '4')|]];
        };

        it 'update rows' => sub {

            $db->update_rows(ttt => [{a=>1,b=>2},{a=>11,b=>22}], [{c=>3,d=>4},{c=>33,d=>44}]);
            cmp_deeply \@do_calls, [[$dbh, q|UPDATE `ttt` SET `a` = CASE `c` WHEN '3' THEN CASE `d` WHEN '4' THEN '1' ELSE `a` END WHEN '33' THEN CASE `d` WHEN '44' THEN '11' ELSE `a` END ELSE `a` END, `b` = CASE `c` WHEN '3' THEN CASE `d` WHEN '4' THEN '2' ELSE `b` END WHEN '33' THEN CASE `d` WHEN '44' THEN '22' ELSE `b` END ELSE `b` END WHERE ((`c` = '3' AND (`d` = '4')) OR (`c` = '33' AND (`d` = '44')))|]];

        };
    };
};

runtests unless caller;
