package State::Flow::_Task::UpdateM13n;

=pod Обновляет значение поля материализации
=cut

use strict;
use warnings;

=pod Конструирует объект задания на получение записей из БД.
Параметры:
	 state_flow	- объект StateFlow;
	 trx_storage- объект StateFlow::_TransactionStorage;
	
	либо:
	 table		- таблица;
	 selector	- условия выборки;
	либо:
	 record		- запись, в которой будем обновлять материализацию
	 
	 field		- имя обновляемого опля
=cut
sub new {
	my($class, %options) = @_;
	return bless \%options => $class;
}

sub priority { 3 }

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
	
	my(@next_tasks, $effect);
	
	foreach my $task (@$tasks) {
		if(! $task->{record}) {
			my($uniq_name, $uniq_key) = $task->{state_flow}->_selector_2_uniq_name_key($task->{selector});
			
			if( $task->{record} = $task->{trx_storage}->get( $task->{table}, $uniq_name, $uniq_key ) ) {
				$effect++;
			}
			elsif( ! $task->{fetch_task_created} ) {
				push @next_tasks, State::Flow::_Task::Fetch->new(
					state_flow	=> $task->{state_flow},
					trx_storage	=> $task->{trx_storage},
					table		=> $task->{table},
					selector	=> $task->{selector},
				);
				$task->{fetch_task_created} = 1;
				$effect++;
			}
		}
	}
	
	foreach my $task (@$tasks) {
		if($task->{record}) {
			my $m13n_props = $task->{state_flow}->{ $task->{record}->table }->{ $task->{field} }->{m13n};
			
			if(! $task->{ext_record}) {
				my @selector = (
					$m13n_props->{selector}->[1],
					$m13n_props->{selector}->[2],
					$task->{record}->current_version->{ $m13n_props->{selector}->[3] },
				);
				my($uniq_name, $uniq_key) = $task->{state_flow}->_selector_2_uniq_name_key(\@selector);
				if( $task->{ext_record} = $task->{trx_storage}->get( $m13n_props->{table}, $uniq_name, $uniq_key ) ) {
					$effect++ ;
				}
				elsif( ! $task->{fetch_ext_task_created} ) {
					push @next_tasks, State::Flow::_Task::Fetch->new(
						state_flow	=> $task->{state_flow},
						trx_storage	=> $task->{trx_storage},
						table		=> $m13n_props->{table},
						selector	=> \@selector,
					);
					$task->{fetch_ext_task_created} = 1;
					$effect++;
				}
			}
			
			# TODO: кейс, когда ext_record не нашёлся
			
			if($task->{ext_record}) {
				my $value = $task->{ext_record}->{ $m13n_props->{field} };
				push @next_tasks, State::Flow::_Task::UpdatePlain->new(
					state_flow	=> $task->{state_flow},
					trx_storage	=> $task->{trx_storage},
					record		=> $task->{record},
					changes		=> { $task->{field} => $value },
				);
				$effect++;
			} else {
				push @next_tasks, $task;
			}
		} else {
			push @next_tasks, $task;
		}
	}
	
	return \@next_tasks, $effect;
}

1;
