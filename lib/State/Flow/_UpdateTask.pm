package State::Flow::_UpdateTask;

use strict;
use warnings;

=pod Конструирует объект задания на обновление.
Параметры:
	 state_flow	- объект StateFlow;
	 trx_storage- объект StateFlow::_TransactionStorage;
	 table		- имя таблицы;
	 selector	- selector для поиска записи;
	 changes	- какие изменения надо наложить на запись;
	[-create]	- если запись не найдена, создать её, а не проигнорировать задание;
=cut
sub new {
	my($class, %options) = @_;
	return bless \%options => $class;
}

sub priority { 1 }

use State::Flow::_Record;
use State::Flow::_FetchTask;
=pod Пакетный метод (метод пакета, принимающий целый пакет объектов вместо одного).
Накладывает обновления на доступные записи, пытается получить записи.
Параметры:
	 0	- ссылка на список объектов данного класса;
Результат:
	 0	- ссылка на список заданий для добавления в очередь (в т.ч. невыполненные на этой итерации задания);
	 1	- был ли достигнут какой-то полезный эффект?
=cut
sub run {
	my($pkg, $tasks) = @_;
	
	my $effect = 0;
	my(@nextTasks, @tasksWithRecord);
	
	foreach my $task (@$tasks) {
		if(! $task->{selector}) {
			$task->{record} = State::Flow::_Record->new(
				state_flow	=> $task->{state_flow},
				trx_storage	=> $task->{trx_storage},
				table		=> $task->{table},
				value		=> undef,
			);
		}
		
		if($task->{record}) {	# Если запись уже известна, можно идти её и обновлять
			push @tasksWithRecord, $task;
		} else {				# Если неизвестна
			# Если в транзакционном хранилище запись известна, т.е. её пытались получить и есть какой-то за'hold'енный в транзакции ответ
			my($uniq_name, $uniq_key) = $task->{state_flow}->_selector_2_uniq_name_key($task->{selector});
			if(my $record = $task->{trx_storage}->get( $task->{table}, $uniq_name, $uniq_key )) {
				# Если запись обнаружена, либо не обнаружена, но у задания есть флаг, что в этом случае её надо будет создать, будем работать с этим объектом записи
				if($record->current_version or $task->{-create}) {
					$task->{record} = $record;
					$effect++;
					push @tasksWithRecord, $task;
				} else { # Если же запись не обнаружена и флага о создании нет, значит нечего делать.
					$effect++; # Теперь мы это знаем
				}
			} else { # Если же запись неизвестна, надо её получить
				if( ! $task->{fetch_task_created} ) {
					# Для этого заводим fetch task
					push @nextTasks, State::Flow::_FetchTask->new(
						state_flow	=> $task->{state_flow},
						trx_storage	=> $task->{trx_storage},
						table		=> $task->{table},
						selector	=> $task->{selector},
					);
					# И запоминаем, что это уже сделано и при следующей попытке выполнения этого задания опять его заводить не надо
					$task->{fetch_task_created} = 1;
					
					$effect++; # Полезные действия выполнены были, так что эффект есть
				}
				
				# И раз мы задачу не выполнили, добавим её на перевыполенние
				push @nextTasks, $task;
			}
		}
	}
	
	foreach my $task (@tasksWithRecord) {
		my($before, $after) = $task->{record}->update( $task->{changes} );
		# TODO: #reactive сравнить before и after, взять подписки на отличающиеся поля, и создать по ним задания на пересчёт
		
		$effect++;
	}
	
	return \@nextTasks, $effect;
}

1;
