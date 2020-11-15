use strict;
use warnings;
use Test::Spec;
use DBI;
use Carp;
$SIG{__DIE__} = sub { confess(@_) };

share my %share;

$share{dbh} = DBI->connect(
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
			
			$error_msg .= ' placeholders: '.Data::Dumper->new([ $hdl->{ParamValues} ])
				->Indent(0)
				->Terse(1)
				->Pair('=>')
				->Quotekeys(0)
				->Sortkeys(1)
				->Dump()
				;
			
			die $error_msg;
		},
		mysql_init_command 	=> "SET NAMES 'utf8mb4'", # Это выполняется при каждом автореконнекте
	}
) or die $DBI::errstr;

sub drop_test_tables {
	foreach my $t (map {@$_} $share{dbh}->selectcol_arrayref("SHOW TABLES LIKE 'state_flow_test_table_%'")) {
		$share{dbh}->do("DROP TABLE IF EXISTS `$t`");
	}
}

drop_test_tables();

after each => sub { drop_test_tables(); };

after all => sub { $share{dbh}->disconnect(); }
