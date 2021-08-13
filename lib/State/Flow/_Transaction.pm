package State::Flow::_Transaction;

use strict;
use warnings FATAL => 'all';
use Scalar::Util qw(refaddr);
#use Data::Structure::Util qw(unbless); # TODO: require libdata-structure-util-perl
use Carp;
use State::Flow::_Record;
use State::Flow::_DB;

sub new {
    my($class, $dbh, $struct) = @_;
    
    return bless {
        db                    => State::Flow::_DB->new($dbh),
        storage             => {},
        records             => {},
        # table_name => {
        #     fields            => {},
        #    fields_order    => [],
        #    defaults        => {},
        #    indexes            => {
        #        index_name => { # index_name = is primary ? 'PRIMARY' : join ':', index_fields
        #            is_unique    => bool,
        #            fields        => [],
        #        }
        #    },
        # }
        struct                => $struct,
        in_trx                => 0,
    } => $class;
}

sub _upd_record_in_cache {
    my($self, $record, $before, $after) = @_;

    die "Can't update this record because it's transaction is out" if ! $self->{in_trx};

    while(my($index_name, $index_info) = each $self->{struct}->{ $record->table }->{indexes}->%*) {
        next unless $index_info->{is_unique};

        if( $before     # if something was before
            and (       # and
                ! $after# it has gone
                # or it changed in key fields
                or grep {defined($before->{ $_ }) != defined($after->{ $_ }) or $before->{ $_ } ne $after->{ $_ }}
                $index_info->{fields}->@*
            )
        ) { # then now here is undef

            my $index_key = $self->values_to_index_key({ $before->%{ $index_info->{fields}->@* } });

            $self->{storage}->{ $record->table }->{ $index_name }->{ $index_key } = undef;
        }

        if(    $after    # if something exists after
            and (        # and
            ! $before    # it didn't exists before
                # or it changed in key fields
                or grep {defined($before->{ $_ }) != defined($after->{ $_ }) or $before->{ $_ } ne $after->{ $_ }}
                $index_info->{fields}->@*
        )
        ) {                    # then now here is record
            my $index_key = $self->values_to_index_key({ $after->%{ $index_info->{fields}->@* } });

            die "DUP" if $self->{storage}->{ $record->table }->{ $index_name }->{ $index_key };

            $self->{storage}->{ $record->table }->{ $index_name }->{ $index_key } = $record;
        }
    }
}

sub values_to_index_name {
    my(undef, $values) = @_;
    return join(':', sort keys %$values);
}

sub values_to_index_key {
    my(undef, $values) = @_;
    return join(':', map {$values->{ $_ }} sort keys %$values);
}

# TODO: bulk

# @param table      - from what table to select rows
# @param matches    - filters in hashref format {field=>value,...}
# @result           - record ever existed
# @result           - record if exists, undef otherwise
sub get {
    my($self, $table, $match_conds) = @_;

    my $index_name = $self->values_to_index_name($match_conds->[0]);

    my(@ever_exists, @records);

    foreach my $mconds (@$match_conds) {
        my $index_key = $self->values_to_index_key($mconds);

        if(exists $self->{storage}->{ $table }->{ $index_name }->{ $index_key }) {
            my $record = $self->{storage}->{ $table }->{ $index_name }->{ $index_key };
            push @ever_exists, !! $record;
            push @records, $record;
        } else {
            push @ever_exists, undef;
            push @records, undef;
        }
    }
    return \@ever_exists, \@records;
}

# @param table      - from what table to select rows
# @param matches    - filters in hashref format {field=>value,...}
# @result           - record ever existed
# @result           - record if exists, undef otherwise
sub fetch {
    my($self, $table, $match_conds) = @_;

    my $index_name = $self->values_to_index_name($match_conds->[0]);

    foreach my $mconds (@$match_conds) {
        my $index_key = $self->values_to_index_key($mconds);
        $self->{storage}->{ $table }->{ $index_name }->{ $index_key } ||= undef;
    }
    
    unless($self->{in_trx}) {
        $self->{db}->trx_begin();
        $self->{in_trx} = 1;
    }

    my $rows = $self->{db}->get_and_lock_rows($table, $match_conds);

    foreach my $row (@$rows) {
        my $record = State::Flow::_Record->new($table, $row);

        $self->_upd_record_in_cache($record, undef, $record->current_version);
        $self->{records}->{ refaddr($record) } = $record;
    }

    return $self->get($table, $match_conds); # Это чтобы не зависеть от порядка в @$rows, не соответсвующего порядку в @$match_conds
}

# TODO: test
sub create_record {
    my($self, $table) = @_;

    say STDERR "trx->create_record($table)";
    use Data::Dumper;
    say STDERR "trx->struct=".Dumper($self->{struct});

    my $record = State::Flow::_Record->new($table => undef, $self->{struct}->{ $table }->{defaults});

    $self->{records}->{ refaddr($record) } = $record;

    return $record;
}

# Record updating.
# Params:
#    0    - record.
#   1   - if it is creating of new record or updating of existing record: hashref of changes
#       - if it is deleting of record: undef
# Result:
#   0   - state before changes
#   1   - state after changes
sub update_record {
    my($self, $record, $changes) = @_;

    die "Unknown record. You must use record got from ->get method of this object".Dumper($self) if ! $self->{records}->{ refaddr($record) };

    my($before, $after) = $record->_update($changes);

    $self->_upd_record_in_cache($record, $before, $after);

    return $before, $after;
}

sub _write_records_changes {
    my($self) = @_;

    my(%table2insertions, %table2deletions, %table2updates_vals, %table2updates_match_conds);
    while(my(undef, $record) = each $self->{records}->%*) {
        my $initial_version = $record->initial_version;
        my $current_version = $record->current_version;

        next if ! $initial_version and ! $current_version;

        if($initial_version and ! $current_version) {
            push $table2deletions{ $record->table }->@*, {
                $initial_version->%{ $self->{struct}->{ $record->table }->{indexes}->{PRIMARY}->{fields}->@* }
            };
        }
        elsif(! $initial_version and $current_version) {
            push $table2insertions{ $record->table }->@*, [
                $current_version->@{ $self->{struct}->{ $record->table }->{fields_order}->@* }
            ];
        }
        else {
            push $table2updates_match_conds{ $record->table }->@*, {
                $initial_version->%{ $self->{struct}->{ $record->table }->{indexes}->{PRIMARY}->{fields}->@* }
            };

            push $table2updates_vals{ $record->table }->@*, {
                map {$_ => $current_version->{ $_ }}
                grep {
                    defined($current_version->{ $_ }) != defined($initial_version->{ $_ })
                    or (defined($current_version->{ $_ }) and $current_version->{ $_ } ne $initial_version->{ $_ })
                } keys %$current_version
            };
        }
    }

    while(my($table, $deletions) = each %table2deletions) {
        $self->{db}->delete_rows($table, $self->{struct}->{ $table }->{indexes}->{PRIMARY}->{fields}, $deletions);
    }

    while(my($table, $insertions) = each %table2insertions) {
        $self->{db}->insert_rows($table, $self->{struct}->{ $table }->{fields_order}, $insertions);
    }

    while(my($table, $updates) = each %table2updates_vals) {
        $self->{db}->update_rows($table, $updates, $table2updates_match_conds{ $table });
    }
}

sub commit {
    my($self) = @_;

    die "Attempt to commit out of transaction" if ! $self->{in_trx};

    # dump all changes to DB
    $self->_write_records_changes();


    $self->{db}->trx_commit();

    $self->{in_trx} = 0;

    # Records in this trx are not
    $self->{storage} = {};
    $self->{records} = {};
}

sub rollback {
    my($self) = @_;

    die "Attempt to rollback out of transaction" if ! $self->{in_trx};
    
    # TODO: забыть кеш
    # TODO: испортить все записи с помощью unbless, чтобы они стали первой версией себя
    # Чтобы снаружи транзакций могли только читать эти данные

    $self->{db}->trx_rollback();

    $self->{in_trx} = 0;

    # TODO: забыть кеш, т.к. теперь записи не залочены в нашей транзакции
    $self->{storage} = {};
    $self->{records} = {};
}

sub dump {
    my($self) = @_;
    
    # TODO:
}

sub DESTROY {
    my($self) = @_;
    if($self->{in_trx}) {
        $self->rollback();
        croak "Lost transaction!";
    }
}

1;
