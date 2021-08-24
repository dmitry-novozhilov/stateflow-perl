package State::Flow::TestHelpers;
use strict;
use warnings FATAL => 'all';

use Exporter 'import';
our @EXPORT = qw(describe_shared_example_for_each_dbms);

use Test::Spec;

sub describe_shared_example_for_each_dbms {
    my($shared_example_name) = @_;

    foreach my $dbms (
        {
            name               => 'SQLite',
            module             => 'DBD::SQLite',
            DBI_connect_params => [
                'dbi:SQLite:dbname=:memory:',
                undef,
                undef,
                {
                    RaiseError => 1,
                    sqlite_see_if_its_a_number => 1,
                },
            ],
        },
        {
            name    => 'MySQL',
            module    => 'DBD::mysql',
            DBI_connect_params    => ['DBI:mysql:database=test;host=localhost', 'test', 'test', {RaiseError => 1}],
        },
    ) {
        my $describer = eval("use $dbms->{module}; 1") ? \&describe : \&xdescribe;

        $describer->(
            $dbms->{name},
            sub {
                share my %shared_vars;
                before all => sub {$shared_vars{dbh} = DBI->connect($dbms->{DBI_connect_params}->@*)};

                it_should_behave_like $shared_example_name;
            },
        );
    }
}

1;
