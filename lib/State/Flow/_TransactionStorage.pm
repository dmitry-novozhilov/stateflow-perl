package State::Flow::_TransactionStorage;

use strict;
use warnings;
use Data::Dumper;
use List::MoreUtils qw(uniq);
use Scalar::Util qw(refaddr);
use Carp;

sub new {
	my($class, $stateFlow) = @_;
	
	return bless {
		state_flow	=> $stateFlow,
		data		=> {
			# Тут будет храниться инфа о строках базы, которая залочена в транзакции
			# формат:
			#	- ключ		- имя таблицы
			#	- значение	- хеш:
			#		- ключ		- название индекса
			#		- значение	- хеш:
			#			- ключ		- конкатенация значений (если ключа нет - данные не запрашивались из БД и надо делать запрос; Если есть - можно с уверенностью сказать, что в БД)
			#			- значение	- если записи с БД нет - undef, если есть - объект Record
		},
		records		=> {}, # Тут будут храниться ссылки на все когда-либо хранимые записи
	} => $class;
}

=pod Чтение значения из транзакционного хранилища
Параметры:
	 0	- таблица;
	 1	- имя uniq'а;	<- Это можно взять так:
	 2	- ключ uniq'а;	<- State::Flow->_selector_2_uniq_name_key(селектор)
Результат:
	 0	- есть ли информация об этой записи (если запись не запрашивалась, будет undef, иначе - 1);
	[1]	- StateFlow::Record (если такая запись в БД была, то её ->current_version вернёт её, иначе ->current_version вернёт undef).
=cut
sub get {
	my($self, $table, $uniq_name, $uniq_key) = @_;
	
	die "Unknown table '$table'" if ! exists $self->{state_flow}->{tables}->{ $table };
	
	croak "No uniq '$uniq_name' in table '$table'" if ! exists $self->{state_flow}->{tables}->{ $table }->{uniqs}->{ $uniq_name };
	
	return undef if ! exists $self->{data}->{ $table }->{ $uniq_name }->{ $uniq_key };
	
	return 1 => $self->{data}->{ $table }->{ $uniq_name }->{ $uniq_key };
}

sub get_all { [ values %{ shift->{records} } ] }

# при изменении ключевых полей записи обновим индексы в памяти (локальный кеш)
sub on_record_update {
	my($self, $record, $before, $after) = @_;
	
	# обновляем местонахождение записей в деревьях индексов. на старых местах оставлять пустое место тождественно не найденной, но искавшейся записи
	while(my($uniq_name, $uniq_fields) = each %{ $self->{state_flow}->{tables}->{ $record->table }->{uniqs} }) {
		if(	$before	# Если что-то было
			and (	
				! $after	# и либо не стало
				# либо изменились ключевые поля
				or grep { defined($before->{$_}) != defined($after->{$_}) and $before->{$_} != $after->{$_} } @$uniq_fields
			)
		) {	# то надо в индексе поставить запись пустого места
			my $uniq_key = join('|', map { $before->{ $_ } } sort @$uniq_fields);
			$self->{data}->{ $record->table }->{ $uniq_name }->{ $uniq_key } = undef;
		}
		if( $after	# Если что-то стало
			and (
				! $before	# и его не было
				# либо изменились ключевые поля
				or grep { defined($before->{$_}) != defined($after->{$_}) and $before->{$_} != $after->{$_} } @$uniq_fields
			)
		) {	# то надо в индексе поставить эту запись
			my $uniq_key = join('|', map { $after->{ $_ } } sort @$uniq_fields);
			
			# если на новом месте записи уже есть какая-то запись и это не undef, значит у нас дуп = ошибка
			if(	$self->{data}->{ $record->table }->{ $uniq_name }->{ $uniq_key } ) {
				die "DUP!";
			}
			
			$self->{data}->{ $record->table }->{ $uniq_name }->{ $uniq_key } = $record;
		}
	}
	
	$self->{records}->{ refaddr($record) } = $record;
}

=pod Запись в транзакционный кеш
Параметры:
	 0		- StateFlow::Record (если запись в БД не была найдена, Record должен быть удалённой записи (->current_version возвращает undef);
	[1,2]	- если запись в БД не была найдена, имя и ключ uniq'а, по которым она искалась;
Результат: нет
=cut
sub set {
	my($self, $record, $uniq_name, $uniq_key) = @_;
	
	if($record and $record->current_version) {
		my $uniq_fields;
		while(($uniq_name, $uniq_fields) = each %{ $self->{state_flow}->{tables}->{ $record->table }->{uniqs} }) {
			$uniq_key = join('|', map { $record->current_version->{ $_ } } sort @$uniq_fields);
			$self->{data}->{ $record->table }->{ $uniq_name }->{ $uniq_key } = $record;
		}
	} else {
		$self->{data}->{ $record->table }->{ $uniq_name }->{ $uniq_key } = $record;
	}
	
	$self->{records}->{ refaddr($record) } = $record;
}

1;
