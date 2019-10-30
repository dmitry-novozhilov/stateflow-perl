package State::Flow::_FetchTask;

use strict;
use warnings;
use Data::Dumper;
use State::Flow::_Record;

=pod Конструирует объект задания на получение записей из БД.
Параметры:
	 state_flow	- объект StateFlow;
	 trx_storage- объект StateFlow::_TransactionStorage;
	 table		- таблица;
	 selector	- условия выборки;
=cut
sub new {
	my($class, %options) = @_;
	return bless \%options => $class;
}

sub priority {2}

=pod Пакетный метод (метод пакета, принимающий целый пакет объектов вместо одного).
Получает из БД записи.
Параметры:
	 0	- ссылка на список объектов данного класса;
Результат:
	 0	- ссылка на список заданий для добавления в очередь (в т.ч. невыполненные на этой итерации задания);
	 1	- был ли достигнут какой-то полезный эффект?
=cut
sub run {
	my($pkg, $tasks) = @_;
	
	# TODO: выполняем все таски, которе можно выполнить обращаясь лишь к transaction storage. Если таковые есть - выходим.
	foreach my $task (@$tasks) {
		($task->{uniq_name}, $task->{uniq_key}) = $task->{state_flow}->_selector_2_uniq_name_key($task->{selector});
		my($requested, $record) = $task->{trx_storage}->get( $task->{table}, $task->{uniq_name}, $task->{uniq_key} );
		next if ! $requested;
		$task->{result} = $record;
	}
	if(my @tasks_from_trx_storage = grep {exists $_->{result}} @$tasks) {
		return \@tasks_from_trx_storage, scalar @tasks_from_trx_storage;
	}
	
	my $dbh = $tasks->[0]->{state_flow}->{dbh};
	my(%tables_uniqs2tasks, $largest_tables_uniqs_group);
	foreach my $task (@$tasks) {
		my $table_uniq = $task->{table}.':'.$task->{uniq_name};
		
		# TODO: группируем таски по таблицам и ключам.
		push @{ $tables_uniqs2tasks{$table_uniq} }, $task;
		
		# TODO: выбираем самую большую группу.
		if(	! $largest_tables_uniqs_group
			or @{ $tables_uniqs2tasks{$table_uniq} } > @{ $tables_uniqs2tasks{$largest_tables_uniqs_group} }
		) {
			$largest_tables_uniqs_group = $table_uniq;
		}
	}
	
	# TODO: делаем запрос в БД
	$tasks = delete $tables_uniqs2tasks{$largest_tables_uniqs_group};
	my %value2tasks;
	push @{$value2tasks{$_->{selector}->[0]->[2]}}, $_ foreach @$tasks;
	my $data = $dbh->selectall_arrayref("SELECT * FROM ".$dbh->quote_identifier($tasks->[0]->{table})."
		WHERE $tasks->[0]->{selector}->[0]->[0] IN(".join(', ', keys %value2tasks).")",
		{Slice=>{}},
	);
	$_->{record} = undef foreach @$tasks; # Помечаем все таски как выполненные
	foreach my $d (@$data) {
		my $record = State::Flow::_Record->new(
			state_flow	=> $tasks->[0]->{state_flow},
			trx_storage	=> $tasks->[0]->{trx_storage},
			table		=> $tasks->[0]->{table},
			value		=> $d,
		);
		# Записываем запись в таск
		$_->{record} = $record foreach @{ $value2tasks{ $d->{ $tasks->[0]->{selector}->[0]->[0] } } };
	}
	
	# TODO: сохраняем результат в transaction storage
	foreach my $task (@$tasks) {
		$task->{trx_storage}->set( $task->{record}, $task->{uniq_name}, $task->{uniq_key} );
	}
	
	return [ map {@$_} values %tables_uniqs2tasks ], scalar @$tasks;
}

sub result {
	my $self = shift;
	die "Task not executed" if ! exists $self->{record};
	return $self->{record};
}

1;
