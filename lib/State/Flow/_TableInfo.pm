package State::Flow;

use strict;
use warnings FATAL => 'all';
use Const::Fast;

sub _TableInfo {
	my($class, $fields, $uniqs, $non_uniqs) = @_;
	
	my %indexes;
	foreach my $uniq ($uniqs->@*) {
		$indexes{ join(':', sort $uniq->@*) } = 1;
	}
	
	# TODO: $non_uniqs + учесть, что любое начало uniq'а - это non_uniq
	
	my %defaults;
	while(my($field, $field_info) = each %$fields) {
		$defaults{ $field } = $field_info->{default};
	}
	
	const my $info => {
		fields	=> $fields,
		defaults=> \%defaults,
		indexes	=> \%indexes,
	};
	
	return $info;
}

1;
