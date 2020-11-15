package State::Flow::_Expression;

use strict;
use warnings;

sub parse {
	my($text) = @_;
	
	if(	$text =~ /^\s*
		([A-Za-z0-9_]+)
		\s*\[\s*
		([A-Za-z0-9_]+)
		\s*
		(=)
		\s*
		([A-Za-z0-9_]+)
		\s*\]\s*\.\s*
		([A-Za-z0-9_]+)
		\s*$/x
	) {
		return {
			type	=> 'LINK',
			table	=> $1,
			match	=> [
				{ ext_field => $2, op => $3, int_field => $4 }
			],
			field	=> $5,
			match_conds => {
				# Параметры: 0 - хеш с полями ЭТОЙ записи
				# Результат: параметр match_conds для вызова sf->fetch, чтобы найти по ЭТОЙ записи ТУ
				ext_table => sub { [[ $2 => '=' => $_[0]->{ $4 } ]] },
				# Параметры: 0 - хеш с полями ТОЙ записи
				# Результат: параметр match_conds для вызова sf->fetch, чтобы найти по ТОЙ записи ЭТУ
				int_table => sub { [[ $4 => '=' => $_[0]->{ $2 } ]] },
			},
		};
	} else {
		die "Can't parse expression '$text'";
	}
}

1;
