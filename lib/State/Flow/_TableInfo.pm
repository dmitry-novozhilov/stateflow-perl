package State::Flow;

use strict;
use warnings;

sub _TableInfo {
	my($dbh, $table_name) = @_;
	
	my %fields = map { $_->{Field} => {name => $_->{Field}, default => $_->{Default} } }
		map {@$_}
		$dbh->selectall_arrayref("SHOW COLUMNS FROM ".$dbh->quote_identifier($table_name), {Slice=>{}})
		;
	
	my %uniqs;
	foreach my $if (map {@$_}
		$dbh->selectall_arrayref("SHOW INDEX FROM ".$dbh->quote_identifier($table_name), {Slice=>{}})
	) {
		next if $if->{Non_unique};
		$uniqs{ $if->{Key_name} }->[ $if->{Seq_in_index} - 1 ] = $if->{Column_name};
	}
	
	return \%fields, \%uniqs;
}

1;
