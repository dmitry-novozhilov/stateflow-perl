package State::Flow::_Record;

use strict;
use warnings;
use Data::Dumper;

sub new {
	my($class, %options) = @_;
	return bless {
		state_flow	=> $options{state_flow},
		trx_storage	=> $options{trx_storage},
		table		=> $options{table},
		versions	=> [ $options{value} ],
	} => $class;
}

sub table {shift->{table}}

=pod Возвращает копию значений текущей версии
=cut
sub current_version {
	if( my $cv = shift->{versions}->[-1] ) {
		return { %$cv };
	} else {
		return undef;
	}
}

=pod Возвращает копию значений первой (инициирующей) версии
=cut
sub initial_version {
	if( my $cv = shift->{versions}->[0] ) {
		return { %$cv };
	} else {
		return undef;
	}
}

=pod Обновление записи.
Добавляет в список версий записи новую версию, которая отличается от предыдущей переданными изменениями.
Параметры:
	 0	- если запись создаётся или обновляется, то ссылка на хеш изменений, где:
	 		ключ	- название поля;
			значение- новое значение
		Если же запись удаляется, то undef,
Результат:
	 0	- состояние "до";
	 1	- состояние "после".
=cut
sub update {
	my($self, $changes) = @_;
	
	if( $changes ) {
		if( $self->{versions}->[-1] ) {
			push @{ $self->{versions} }, { %{ $self->{versions}->[-1] }, %$changes };
		} else {
			push @{ $self->{versions} }, {
				map { $_->{name} => exists $changes->{ $_->{name} } ? $changes->{ $_->{name} } : $_->{default} }
				values %{ $self->{state_flow}->{tables}->{ $self->{table} }->{fields} }
			};
		}
	} else {
		push @{ $self->{versions} }, undef;
	}
	
	# при изменении ключевых полей записи обновим индексы в памяти (локальный кеш)
	$self->{trx_storage}->on_record_update($self, $self->{versions}->[-2], $self->{versions}->[-1]);
	
	# возвращаем before, after
	return $self->{versions}->[-2], $self->{versions}->[-1];
}

1;
