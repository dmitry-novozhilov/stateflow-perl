package State::Flow;

use strict;
use warnings;
our $VERSION = '0.0.1';
use Data::Dumper;
use Carp;
use Const::Fast;
use State::Flow::_TableInfo;
use State::Flow::_Expression;

sub _init_struct {
	my($self, $declaration) = @_;
	
	while(my($tName, $tDecl) = each %$declaration) {
		
		$self->{tables}->{$tName} = {name => $tName, triggers => {}};
		
		while(my($tPropName, $tPropValue) = each %$tDecl) {
			if($tPropName eq 'fields') {
				while(my($fName, $fDecl) = each %$tPropValue) {
					$self->{tables}->{$tName}->{fields}->{$fName} = {
						name	=> $fName,
						default	=> 0,
						expr	=> $fDecl->{expr} ? State::Flow::_Expression::parse($fDecl->{expr}) : undef,
					};
				}
			}
			elsif($tPropName eq 'uniqs') {
				foreach my $uniq (@$tPropValue) {
					my $uniq_name = join('__', sort @$uniq);
					$self->{tables}->{$tName}->{uniqs}->{$uniq_name} = $uniq;
					
					# Выбираем в качестве primary key первый из самых коротких uniq'ов
					# TODO: #types Когда у полей будут типы, нужно так же учитывать размер полей - лучше пусть primary будет из int'ов, чем из строк
					if(	! $self->{tables}->{$tName}->{primary}
						or @{ $self->{tables}->{$tName}->{uniqs}->{ $self->{tables}->{$tName}->{primary} } } > @$uniq
					) {
						$self->{tables}->{$tName}->{primary} = $uniq_name;
					}
				}
				
				
			}
			elsif($tPropName eq 'indexes') {
				foreach my $index (@$tPropValue) {
					my $undex_name = join('__', sort @$index);
					$self->{tables}->{$tName}->{indexes}->{ join('__', sort @$index) } = $index;
				}
			}
			else {
				die "Unknown table $tName property '$tPropName'";
			}
		}
	}
	
	foreach my $tProps ( values %{ $self->{tables} } ) {
		foreach my $fProps ( values %{ $tProps->{fields} } ) {
			if($fProps->{expr}) {
				
				my $ext_table = $self->{tables}->{ $fProps->{expr}->{table} }
					# чекаем валидность ссылок (имена таблиц и полей)
					or die "Unknown table '$fProps->{expr}->{table}' in $tProps->{name}.$fProps->{name} expression";
				
				
				warn Dumper([$ext_table, $fProps, $tProps]);
				exists( $ext_table->{fields}->{ $fProps->{expr}->{match}->{ext_field} } )
					or die "Unknown field '$fProps->{expr}->{table}.$fProps->{expr}->{match}->{ext_field}' in $tProps->{name}.$fProps->{name} expression";
				
				exists( $tProps->{fields}->{ $fProps->{expr}->{match}->{int_field} })
					or die "Unknown field '$tProps->{name}.$fProps->{expr}->{match}->{int_field}' in $tProps->{name}.$fProps->{name} expression";
				
				exists( $ext_table->{fields}->{ $fProps->{expr}->{field} } )
					or die "Unknown field '$fProps->{expr}->{table}.$fProps->{expr}->{field}' in $tProps->{name}.$fProps->{name} expression";
				
				my $materialize_field = join(_ => '', stateflow => materialize
					# TODO: #multi_record_selector
					=> $ext_table->{name} => $fProps->{expr}->{match}->{ext_field} => eq => $fProps->{expr}->{match}->{int_field}
					=> $fProps->{expr}->{field});
				
				# TODO: calc-задание на это expr-поле:
					# если все необходимые материализации есть, просто считает выражение
					# если каких-то не хватает, сначала требует calc-задание на них
				
				$tProps->{fields}->{ $materialize_field } = {
					name			=> $materialize_field,
					default			=> 0,
					m13n			=> { # TODO: Это для выполнения calc-задания на этом поле. Быть может стоит обозвать этот тип задания иначе
						table	=> $ext_table->{name},
						selector=> [ $fProps->{expr}->{match}->{ext_field} => '=' => $fProps->{expr}->{match}->{int_field} ],
						field	=> $fProps->{expr}->{field},
					},
					update_triggers	=> [
						{
							type	=> 'UpdateExpr',
							field	=> $fProps->{name},
						}
					],
				};
				
				# Внешние триггеры (на поле из match_conds и на целевое поле ссылки):
				# триггер обновит материализацию поля той таблцы в этой таблице
				# и потом триггер уже на этой таблице, на поле материализации, пересчитает поле с выражением, использующим эту материализацию
				my $ext_table_trigger = {
					type	=> 'UpdatePlain',
					table	=> $tProps->{name},
					selector=> [ $fProps->{expr}->{match}->{int_field}, '=', $fProps->{expr}->{match}->{ext_field} ],
					# TODO: при выполнении триггера надо подставить значение поля
					changes	=> { $materialize_field => $fProps->{expr}->{field} },
				};
				push @{ $ext_table->{fields}->{ $fProps->{expr}->{field} }->{update_triggers} }, $ext_table_trigger;
				if( $fProps->{expr}->{field} ne $fProps->{expr}->{match}->{ext_field} ) {
					push @{ $ext_table->{fields}->{ $fProps->{expr}->{match}->{ext_field} }->{update_triggers} }, $ext_table_trigger;
				}
				
				push @{ $tProps->{fields}->{ $fProps->{expr}->{match}->{int_field} }->{triggers} }, {
					type	=> 'Calc',
					field	=> $materialize_field,
				};
				
				# TODO: дамп текущего состояния наборов заданий и кеша. При любой ошибке печатать первый дамп и хоть общие черты второго.
				
			}
		}
	}
}

sub _upgrade_db {
	my($self) = @_;
	
	my %old_tables = map {$_ => undef} map {@$_} map {@$_} $self->{dbh}->selectall_arrayref("SHOW TABLES");
	
	foreach my $table (values %{ $self->{tables} } ) {
		
		if( exists $old_tables{$table->{name}} ) {
			
			my($old_fields, $old_uniqs) = State::Flow::_TableInfo($self->{dbh}, $table->{name});
			
			my @sq;
			
			foreach my $old_field ( values %$old_fields ) {
				if(! exists $table->{fields}->{ $old_field->{name} }) {
					$self->_warn( "Deleting field $old_field->{name} from $table->{name}" );
					push @sq, "DROP COLUMN ".$self->{dbh}->quote_identifier($old_field->{name});
				}
			}
			
			foreach my $new_field (values %{ $table->{fields} } ) {
				if(! exists $old_fields->{ $new_field->{name} } ) {
					$self->_warn( "Adding field $new_field->{name} to $table->{name}" );
					push @sq, "ADD COLUMN ".$self->{dbh}->quote_identifier($new_field->{name})." INT";
				}
			}
			
			while(my($old_uniq_name, $old_uniq) = each %$old_uniqs) {
				if(! exists $table->{uniqs}->{ join('__', sort @$old_uniq) }) {
					$self->_warn( "Deleting unique index $old_uniq_name from $table->{name}" );
					push @sq, "DROP INDEX ".$self->{dbh}->quote_identifier($old_uniq_name);
				}
			}
			
			while(my($new_uniq_name, $new_uniq) = each %{ $table->{uniqs} }) {
				if(! grep {$new_uniq_name eq $_} map {join('__', sort @$_)} values %$old_uniqs) {
					$self->_warn( "Adding unique index $new_uniq_name to $table->{name}" );
					push @sq, "ADD UNIQUE INDEX ".$self->{dbh}->quote_identifier($new_uniq_name)." ("
						.join(', ', sort @$new_uniq).")";
				}
			}
			
			#foreach 
			#
			#my %uniqs;
			#foreach my $if (map {@$_}
			#	$self->{dbh}->selectall_arrayref("SHOW INDEX FROM ".$self->{dbh}->quote_identifier($table->{name}), {Slice=>{}})
			#) {
			#	next if $if->{Non_unique};
			#	$uniqs{ $if->{Key_name} }->[ $if->{Seq_in_index} - 1 ] = $if->{Column_name};
			#}
			
			$self->{dbh}->do("ALTER TABLE ".$self->{dbh}->quote_identifier($table->{name})."\n".join(",", @sq)) if @sq;
			
		} else {
			my @sq = map {"	".$self->{dbh}->quote_identifier($_->{name})." INT NOT NULL"} values %{ $table->{fields} };
			foreach my $uniq_name ( sort keys %{ $table->{uniqs} } ) {
				push @sq, "	UNIQUE KEY ".$self->{dbh}->quote_identifier($uniq_name)." (".join(', ', map {$self->{dbh}->quote_identifier($_)} @{ $table->{uniqs}->{ $uniq_name } }).")";
			}
			
			$self->_warn( "Creating table $table->{name}" );
			$self->{dbh}->do("CREATE TABLE ".$self->{dbh}->quote_identifier($table->{name})."(\n"
				.join(",\n", @sq)."\n"
				.")");
		}
	}
}

use POSIX qw(strftime);
sub _log {
	my($self, $level, $text) = @_;
	
	return if $level < $self->{log_level};
	
	my $h = $self->{log_handler};
	
	print $h strftime("[%F %X]: ", localtime);
	print $h $text;
	print $h "\n" if substr($text, -1) ne "\n";
}

const my %LOG_LEVEL => ( INFO => 1, WARN => 2, ERROR => 3 );

sub _info	{ shift->_log( $LOG_LEVEL{INFO}, @_ ) }
sub _warn	{ shift->_log( $LOG_LEVEL{WARN}, @_ ) }
sub _error	{ shift->_log( $LOG_LEVEL{ERROR}, @_ ) }

sub new {
	my($class, $declaration, $dbh, %options) = @_;
	
	$options{log_level} = $LOG_LEVEL{$options{log_level} || 'WARN'};
	
	my $self = bless {
		dbh			=> $dbh,
		log_handler	=> \*STDERR,
		%options,
	} => $class;
	$self->_init_struct($declaration);
	$self->_upgrade_db();
	
	return $self;
}

sub option {
	die "Unimplemented"; # TODO:
}

sub _selector_2_uniq_name_key {
	my($self, $selector) = @_;
	
	my %selector;
	foreach my $s (@$selector) {
		die "Only '=' match op is supported now" if $s->[1] ne '='; # TODO: #multi_record_selector
		$selector{ $s->[0] } = $s->[2];
	}
	
	my $u_name = join('__', sort keys %selector);
	my $u_key = join('|', map { $selector{ $_ } } sort keys %selector);
	
	return $u_name, $u_key;
}

=pod Запуск обработки заданий в транзакции. Выполняет переданное задание и все порождённые им в одной транзакции.
Параметры:
	 0	- объект задания StateFlow::_*Task
Результат:
	[0]	- результат выполнения переданного задания, если оно подразумевает результат, а не только побочные эффекты типа обновления БД.
=cut
sub _run {
	my($self, $initialTask) = @_;
	
	my %pkg2tasks = ( ref($initialTask) => [ $initialTask ] );
	
	while(1) {
		my $iterEffect = 0;
		my $tasks_cnt = map {@$_} values %pkg2tasks;
		foreach my $pkg (sort { $a->priority <=> $b->priority } keys %pkg2tasks) {
			next if ! @{ $pkg2tasks{ $pkg } };
			
			my $tasks2run = delete( $pkg2tasks{ $pkg } );
			
			my($nextTasks, $effect) = $pkg->run( $tasks2run );
			
			push @{ $pkg2tasks{ ref($_) } }, $_ foreach @$nextTasks;
			$iterEffect += $effect;
			last if $effect; # Чтобы опять начать с самых приоритетных задач
		}
		
		die "Итерация не принесла никакого эффекта, но остались невыполненные таски ".Dumper(\%pkg2tasks) if $tasks_cnt and ! $iterEffect;
		
		last if ! $tasks_cnt;
	}
	
	# TODO: берём все Record'ы из transaction_storage и сохраняем их суммарные diff'ы в БД
	
}


use State::Flow::_Task::Fetch;
use State::Flow::_Task::UpdatePlain;
use State::Flow::_Task::UpdateExpr;
use State::Flow::_Task::UpdateM13n;
use State::Flow::_TransactionStorage;

sub update {
	my($self, $table, $selector, $changes) = @_;
	
	# TODO: begin
	
	my $trxStorage = State::Flow::_TransactionStorage->new($self);
	
	my $task = State::Flow::_Task::UpdatePlain->new(
		state_flow	=> $self,
		trx_storage	=> $trxStorage,
		table		=> $table,
		selector	=> $selector,
		changes		=> $changes,
	);
	
	$self->_run( $task );
	#warn Dumper($task);
	
	my $records = $trxStorage->get_all();
	#warn Dumper($trxStorage);
	my(%table2records2delete, %table2records2insert, %table2records2update);
	foreach my $record (@$records) {
		my $init_version = $record->initial_version;
		my $cur_version = $record->current_version;
		
		if($init_version and $cur_version) {
			#warn Dumper($record);
			my %upd_vals;
			foreach my $field (keys %{ $self->{tables}->{ $record->table }->{fields} }) {
				if(	defined($init_version->{$field}) != defined($cur_version->{$field})
					or (defined $init_version->{$field} and $init_version->{$field} ne $cur_version->{$field})
				) {
					$upd_vals{$field} = $cur_version->{$field};
				}
			}
			next if ! %upd_vals;
			
			my %primary_vals = map { $_ => $init_version->{$_} } @{ $self->{tables}->{ $record->table }->{uniqs}->{ $self->{tables}->{ $record->table }->{primary} } };
			
			push @{ $table2records2update{ $record->table } }, { primary_vals => \%primary_vals, upd_vals => \%upd_vals };
		}
		elsif($init_version) {
			#warn Dumper($record);
			push @{ $table2records2delete{ $record->table } }, $init_version;
		}
		elsif($cur_version) {
			#warn Dumper($record);
			push @{ $table2records2insert{ $record->table } }, $cur_version;
		}
		else {
			#warn Dumper($record);
			next;
		}
	}
	#warn Dumper({table2records2delete => \%table2records2delete, table2records2insert => \%table2records2insert, table2records2update => \%table2records2update});
	
	# TODO: #first_stable_release нужно соблюсти очерёдность обновлений.
	# Если запись в таблице с уникальным ключом по полю а a=10 стала записью a=11, а запись a=9 стала записью a=10, то только соблюдая очерёдность можно сохранить эти изменения. либо в одном пакетном update'е.
	# Но эту проблему можно отложить
	
	while(my($table, $records2insert) = each %table2records2insert) {
		my @fields = sort keys %{ $self->{tables}->{$table}->{fields} };
		my $sq = "(".join(', ', ('?') x @fields).")";
		my @ph;
		foreach my $record (@$records2insert) {
			push @ph, map { $record->{$_} } @fields;
		}
		$self->{dbh}->do("INSERT INTO ".$self->{dbh}->quote_identifier($table)
			." (".join(', ', map { $self->{dbh}->quote_identifier($_) } @fields).") VALUES\n"
			.join(",\n", ($sq) x @$records2insert),
			undef,
			@ph
		);
	}
	
	while(my($table, $records2update) = each %table2records2update) {
		
		my %changed_fields = map { %{ $_->{upd_vals} } } @$records2update;
		
		my @primary_fields = @{ $self->{tables}->{$table}->{uniqs}->{ $self->{tables}->{$table}->{primary} } };
		
		my(@ph, @sets);
		foreach my $field (keys %changed_fields) {
			my $if_stmt = 'NULL';
			foreach my $r (@$records2update) {
				$if_stmt = "if(".join(' AND ', map {"$_ = ?"} @primary_fields).", ?, $if_stmt)";
				unshift @ph, (map { $r->{primary_vals}->{$_} } @primary_fields), $r->{upd_vals}->{$field};
				push @ph, (map { $r->{primary_vals}->{$_} } @primary_fields);
			}
			push @sets, "$field = $if_stmt";
		}
		
		$self->{dbh}->do("UPDATE ".$self->{dbh}->quote_identifier($table)."
			SET ".join(",\n", @sets)."
			WHERE ".join(' OR ', "(".join(' AND ', map {"$_ = ?"} @primary_fields).")"),
			undef,
			@ph, 
		);
	}
	
	while(my($table, $records2delete) = each %table2records2delete) {
		
		my @primary_fields = @{ $self->{tables}->{$table}->{uniqs}->{ $self->{tables}->{$table}->{primary} } };
		my @ph;
		foreach my $r (@$records2delete) {
			push @ph, map {$r->{$_}} @primary_fields;
		}
		
		$self->{dbh}->do(
			"DELETE FROM ".$self->{dbh}->quote_identifier($table)."
			WHERE ".join(' OR ', "(".join(' AND ', map {"$_ = ?"} @primary_fields).")"),
			undef,
			@ph,
		);
	}
	
	# TODO: commit
}

sub fetch {
	my($self, $table, $selector) = @_;
	
	# TODO: begin
	
	my $trxStorage = State::Flow::_TransactionStorage->new($self);
	
	my $task = State::Flow::_Task::Fetch->new(
		state_flow	=> $self,
	 	trx_storage	=> $trxStorage,
	 	table		=> $table,
	 	selector	=> $selector,
	);
	
	$self->_run( $task );	
	
	# TODO: commit
	
	return $task->result ? $task->result->current_version : undef;
}

1;
