package State::Flow::_DB;

# TODO: try SQL::Abstract

use strict;
use warnings FATAL => 'all';
use DBI::Const::GetInfoType;
use Carp; our @CARP_NOT = qw(State::Flow);
use Data::Dmp;

sub dbh_to_package {
    my($dbh) = @_;

    my $dbms_name = $dbh->get_info($GetInfoType{SQL_DBMS_NAME});
    my $pkg = __PACKAGE__.'::'.$dbms_name;
    croak "$dbms_name DBD driver doesn't supported now" unless $pkg->isa(__PACKAGE__);

    return $pkg;
}

sub new {
    my($pkg, $dbh) = @_;

    return dbh_to_package($dbh)->new($dbh) if $pkg eq __PACKAGE__;

    return $pkg->new($dbh);
}

sub __match_conds_to_sql_where {

    my @sql;
    foreach my $n (sort keys $_[0]->%*) {
        my $sql = $n;
        my $subn = $_[0]->{ $n };
        if(%$subn) {
            my $subsql = __match_conds_to_sql_where($subn);
            $sql = "($sql AND $subsql)";
        }
        push @sql, $sql;
    }

    return '('.join(' OR ', @sql).')';
}

sub _match_conds_to_sql_where {
    my($self, $match_conds) = @_;

    my @fields = sort keys $match_conds->[0]->%*;

    my %where;
    foreach my $mconds (@$match_conds) {
        my $node = \%where;
        foreach my $field (@fields) {
            my $key = "`$field` = ".$self->{dbh}->quote($mconds->{ $field });
            $node->{ $key } ||= {};
            $node = $node->{ $key };
        }
    }

    return __match_conds_to_sql_where(\%where);
}

sub delete_rows {
    my($self, $table, $match_conds) = @_;

    # TODO: chunks

    my $where = $self->_match_conds_to_sql_where($match_conds);

    $self->{dbh}->do("DELETE FROM `$table` WHERE $where");
}

sub insert_rows {
    my($self, $table, $fields_order, $rows) = @_;

    # TODO: chunks

    my @rows;
    for(my $q = 0; $q <= $#$rows; $q++) {
        # TODO: do not quote numbers
        push @rows, '('
            .join(', ', map {
                defined $rows->[ $q ]->[ $_ ] ? "'$rows->[ $q ]->[ $_ ]'" : 'NULL'
            } 0 .. $#$fields_order)
            .')';
    }

    $self->{dbh}->do("INSERT INTO `$table` (".join(', ', map {"`$_`"} @$fields_order).") VALUES "
        .join(', ', @rows));
}

sub last_insert_id {shift->{dbh}->last_insert_id}

sub _update_rows_gen_sql_sets {
    # 0 - node, 1 - deep, 2 - pk_fields, 3 - field
    # node - struct {
    #    pk_field_1_value_1 => {
    #        pk_field_2_value_1 => value_1
    #        pk_field_2_value_2 => value_2
    #    }
    # }

    my $sets = '';
    foreach my $k (sort keys $_[0]->%*) {
    #while(my($k, $v) = each $_[0]->%*) {
        $sets .= " WHEN '$k' THEN"; # TODO: maybe no quote ints?
        my $v = $_[0]->{ $k };
        if(ref $v) {
            $sets .= ' '._update_rows_gen_sql_sets($v, $_[1] + 1, $_[2], $_[3]);
        } else {
            $sets .= " '$v'"; # TODO: maybe no quote ints?
        }
    }

    return "CASE `$_[2]->[ $_[1] ]`$sets ELSE `$_[3]` END";
};

sub _update_rows_get_sql_wheres {
    # 0 - wheres_tree - struct {
    #    "`pk_field_1` = 'pk_1_value_1'" => {
    #        "`pk_field_2` = 'pk_1_value_1'" => undef,
    #        "`pk_field_2` = 'pk_1_value_2'" => undef,
    #    }
    # }
    # pk_field_1` = 'pk_1_value_1' AND (`pk_field_2` = 'pk_1_value_1' OR `pk_field_2` = 'pk_1_value_2')

    my @wheres;
    while(my($k, $v) = each $_[0]->%*) {
        if(defined $v) {
            push @wheres, "($k AND ("._update_rows_get_sql_wheres($v)."))";
        } else {
            push @wheres, $k;
        }
    }
    return join(' OR ', @wheres);
}

sub update_rows {
    my($self, $table, $updates, $match_conds) = @_;

    my @pk_fields = sort keys $match_conds->[0]->%*;
    my %sets_tree;
    for my $q (0 .. $#$updates) {
        confess "Empty update # $q in table $table by match_conds ".dmp($match_conds) unless $updates->[ $q ]->%*;
        while(my($set_field, $set_value) = each $updates->[ $q ]->%*) {
            $sets_tree{ $set_field } ||= {};
            my $node = $sets_tree{ $set_field };
            for(my $w = 0; $w <= $#pk_fields; $w++) {
                my $next_node = $w == $#pk_fields ? $set_value : {};
                $node->{ $match_conds->[ $q ]->{ $pk_fields[ $w ] } } = $next_node;
                $node = $next_node;
            }
        }
    }

    my @sets;
    foreach my $field (sort keys %sets_tree) {
        push @sets, "`$field` = "._update_rows_gen_sql_sets($sets_tree{ $field }, 0, \@pk_fields, $field);
    }

    my $where = $self->_match_conds_to_sql_where($match_conds);


    eval {
        $self->{dbh}->do("UPDATE `$table` SET ".join(', ', @sets)." WHERE $where");
    };
    croak "Query 'UPDATE `$table` SET ".join(', ', @sets)." WHERE $where' failed: $@ (updates: ".dmp($updates).")" if $@;

    # SET
    #     val_c = CASE pk_a
    #         WHEN 1 THEN
    #             CASE pk_b
    #                 WHEN 11 THEN
    #                     "zz"
    #                 WHEN 12 THEN
    #                     "zxc"
    #                 ELSE val_c
    #             END
    #         WHEN 2 THEN
    #             CASE pk_b
    #                 WHEN 22 THEN
    #             "asd"
    #                 WHEN 20 THEN
    #             "aaa"
    #                 ELSE val_c
    #             END
    #         END
    #     WHERE
    #         (pk_a = 1 AND
    #             (pk_b = 11 OR pk_b = 12)
    #         )
    #         OR
    #         (pk_a = 2 AND
    #             (pk_b = 22 OR pk_b = 20)
    #         )
}

sub trx_begin { shift->{dbh}->begin_work() }

sub trx_commit { shift->{dbh}->commit() }

sub trx_rollback { shift->{dbh}->rollback() }


package State::Flow::_DB::SQLite;

use strict;
use warnings FATAL => 'all';
use parent 'State::Flow::_DB';
use Carp;

sub new {
    my($class, $dbh) = @_;

    my($sqlite_version) = $dbh->selectrow_array("SELECT sqlite_version()");

    return bless {dbh => $dbh, sqlite_version => $sqlite_version} => $class;
}

# TODO: SELECT ... WHERE (a=1 AND b=2) OR (a=11 AND b=22)

sub get_and_lock_rows {
    my($self, $table, $matches) = @_;

    my $where = $self->_match_conds_to_sql_where($matches);

    return $self->{dbh}->selectall_arrayref("SELECT * FROM `$table` WHERE $where", {Slice=>{}});
}

sub insert_rows {
    my($self, $table, $fields_order, $rows, $records_to_upd_autoincrement) = @_;

    # TODO: chunks

    # TODO: use INSERT ... RETURNING autoincrement_field since SQLite v3.35

    my @rows;
    for(my $q = 0; $q <= $#$rows; $q++) {
        # TODO: do not quote numbers
        push @rows,
             '('.join(', ', map {defined $rows->[ $q ]->[ $_ ] ? "'$rows->[ $q ]->[ $_ ]'" : 'NULL'} 0 .. $#$fields_order).')';
    }

    $self->{dbh}->do("INSERT INTO `$table` (".join(', ', map {"`$_`"} @$fields_order).") VALUES ".join(', ', @rows));

    return [] unless $records_to_upd_autoincrement;

    my $last_id = $self->{dbh}->last_insert_id();
    my @ids = $last_id;
    unshift @ids, --$last_id for 1 .. $#$records_to_upd_autoincrement;
    return \@ids;
}

sub check_table {
    my($self, $table) = @_;

    my $exists;
    foreach my $sqlite_master (qw/sqlite_master sqlite_temp_master/) {
        ($exists) = $self->{dbh}->selectrow_array("SELECT count(*) FROM $sqlite_master WHERE type = 'table' AND name = ?",
            undef, $table->{name});
    }
    return ['not exists'] unless $exists;

    # # To autocreate sqlite_sequence table
    # $self->{dbh}->do('CREATE TEMPORARY TABLE IF NOT EXISTS _bump_sqlite_sequence_ (id INTEGER PRIMARY KEY AUTOINCREMENT)');
    # $self->{dbh}->do('DROP TABLE _bump_sqlite_sequence_');
    #
    # my($autoincrement) = $self->{dbh}->selectrow_array('SELECT seq FROM sqlite_sequence WHERE name = ?', undef, $table->{name});
    #

    my @errors;

    my $fields_rs = $self->{dbh}->selectall_arrayref("PRAGMA table_info(`$table->{name}`)", {Slice=>{}});
    foreach my $r (@$fields_rs) {
        unless(exists $table->{fields}->{ $r->{name} }) {
            push @errors, "extra field $r->{name}";
            next;
        }

        my $field_errors = $self->is_field_valid($table->{fields}->{ $r->{name} }, $r->{type});
        push @errors, map {"field $r->{name} $_"} @$field_errors;
    }

    my $indexes_rs = $self->{dbh}->selectall_arrayref("PRAGMA index_list(`$table->{name}`)", {Slice=>{}});
    foreach my $r (@$indexes_rs) {
        my $name;
        if($r->{name} =~ /^sqlite_autoindex_$table->{name}_\d+$/ and $r->{origin} eq 'pk') {
            $name = 'PRIMARY';
        }
        elsif($r->{name} =~ /^$table->{name}_(.*)$/) {
            $name = $1;
        }
        else {
            push @errors, "unknown index '$r->{name}'";
            next;
        }

        if(not exists $table->{indexes}->{ $name } and $r->{unique}) {
            push @errors, "extra unique index $r->{name}";
            next;
        }

        my $db_is_unique = $r->{unique} ? 1 : 0;
        my $decl_is_unique = $table->{indexes}->{ $name }->{is_unique} ? 1 : 0;
        if($decl_is_unique != $db_is_unique) {
            push @errors, sprintf("%s index '%s' %s unique", $table->{name}, $name, $db_is_unique ? 'is' : 'is not');
        }

        my $db_fields = join(', ', map {$_->{name}} $self->{dbh}->selectall_arrayref("PRAGMA index_info(`$r->{name}`)", {Slice=>{}})->@*);
        my $decl_fields = join(', ', $table->{indexes}->{ $name }->{fields}->@*);
        if($db_fields ne $decl_fields) {
            push @errors, sprintf("%s index '%s' fields is %s", $table->{name}, $name, $db_fields);
        }
    }

    return \@errors;
}

sub _to_db_type {
    my($self, $type, $max_length) = @_;

    return 'INTEGER' if $type =~ /^(u?)int(8|16|32|64)$/ or $type eq 'datetime' or $type eq 'bool';
    return 'REAL' if $type =~ /^float(32|64)$/;
    return 'STRING' if $type eq 'string';
    croak "Unknown type $type";
}

sub is_field_valid {
    my($self, $sf_decl, $db_type) = @_;

    my @errors;

    # Can't check for field is autoincrement

    # if($sf_type =~ /^(u?)int(8|16|32|64)$/) {
    #     my $max = 2 ** $2;
    #     my $min = $1 ? 0 : - $max / 2;
    #     $max += $min - 1;
    # }

    if( ($sf_decl->{type} =~ /^(u?)int(8|16|32|64)$/ and $db_type ne 'INTEGER')
        or ($sf_decl->{type} eq 'string' and $db_type ne 'STRING')
        or ($sf_decl->{type} eq 'datetime' and $db_type ne 'INTEGER')
        or ($sf_decl->{type} eq 'bool' and $db_type ne 'INTEGER')
    ) {
        push @errors, "has wrong type $db_type";
    }

    return \@errors;
}

sub create_table {
    my($self, $table, $mode) = @_;

    my(@sql, @ph);

    foreach my $field (values $table->{fields}->%*) {
        my @f_decl = "`$field->{name}`";
        push @f_decl, $self->_to_db_type( $field->{type}, $field->{max_length} );
        if(exists $field->{default}) {
            push @f_decl, 'DEFAULT ?';
            push @ph, $field->{default};
        }
        # In SQLite this doesnt' works
        #$f_decl[-1] .= "($field->{max_length})" if exists $field->{max_length};
        push @f_decl, 'PRIMARY KEY AUTOINCREMENT' if $field->{autoincrement};
        push @sql, join(' ', @f_decl);
    }

    foreach my $index (values $table->{indexes}->%*) {
        # Non primary indexes adds in next sql queries
        next unless $index->{name} eq 'PRIMARY' and $index->{is_unique};
        if($table->{autoincrement_field}) {
            # Already declared in field with autoincrement
            next if $index->{fields}->@* == 1 and $index->{fields}->[0] eq $table->{autoincrement_field};
            croak "Can't create table with one autoincrement field and more than one fields in primary key";
        }
        push @sql, sprintf('PRIMARY KEY (%s)', join(', ', $index->{fields}->@*));
    }

    my $sql = sprintf("CREATE %s TABLE `%s` (\n\t%s\n)",
        ($mode eq 'TEMP' ? 'TEMPORARY' : ''), $table->{name}, join ",\n\t", @sql);

    #warn $sql;

    $self->{dbh}->do($sql, undef, @ph);

    foreach my $index (values $table->{indexes}->%*) {
        next if $index->{name} eq 'PRIMARY';

        my $sql = sprintf('CREATE %s INDEX %s.`%s` ON `%s` (%s)',
            ($index->{is_unique} ? 'UNIQUE' : ''),
            ($ENV{STATEFLOW_AUTOCREATE_TABLES} and $ENV{STATEFLOW_AUTOCREATE_TABLES} eq 'TEMP' ? 'temp' : 'main'),
            "$table->{name}_$index->{name}",
            $table->{name},
            join(', ', $index->{fields}->@*),
        );

        #warn $sql;

        $self->{dbh}->do($sql);
    }
}


package State::Flow::_DB::MySQL;

use strict;
use warnings FATAL => 'all';
use parent 'State::Flow::_DB';

use constant TYPE2MYSQL_TYPE => {
    int8    => 'TINYINT',
    int16   => 'SMALLINT',
    int32   => 'INT',
    int64   => 'BIGINT',
    uint8   => 'TINYINT UNSIGNED',
    uint16  => 'SMALLINT UNSIGNED',
    uint32  => 'INT UNSIGNED',
    uint64  => 'BIGINT UNSIGNED',
    float32 => 'FLOAT',
    float64 => 'DOUBLE',
    string  => 'VARCHAR',
    datetime=> 'DATETIME',
    bool    => 'TINYINT',
};

sub new {
    my($class, $dbh) = @_;
    return bless {dbh => $dbh} => $class;
}

sub get_and_lock_rows {
    my($self, $table, $matches) = @_;

    my $where = $self->_match_conds_to_sql_where($matches);

    return $self->{dbh}->selectall_arrayref("SELECT * FROM `$table` WHERE $where FOR UPDATE", {Slice=>{}});
}

sub check_table {
    my($self, $table) = @_;

    # MySQL don't show temporary tables;
    eval {$self->{dbh}->selectrow_array("SELECT 1 FROM `$table->{name}`") };
    return [$@] if $@;

    my $rs = $self->{dbh}->selectall_arrayref("SHOW FIELDS FROM `$table->{name}`", {Slice=>{}});

    my %fields;
    foreach my $r (@$rs) {
        $fields{ $r->{Field} } = {
            type    => $r->{Type},
            default => $r->{Default},
            ($r->{Extra} =~ 'auto_increment' ? (autoincrement => 1) : ()),
        };
    }

    $rs = $self->{dbh}->selectall_arrayref("SHOW KEYS FROM `$table->{name}`", {Slice=>{}});

    my %indexes;
    foreach my $r (@$rs) {
        $indexes{ $r->{Key_name} }->{is_unique} = ! $r->{Non_unique};
        $indexes{ $r->{Key_name} }->{fields}->[ $r->{Seq_in_index} - 1] = $r->{Column_name};
    }

    return [];
}

sub create_table {
    my($self, $table, $mode) = @_;

    my(@sql, @ph);

    foreach my $field (values $table->{fields}->%*) {
        my @f_decl = "`$field->{name}`";
        push @f_decl, TYPE2MYSQL_TYPE()->{ $field->{type} };
        if(exists $field->{default}) {
            push @f_decl, 'DEFAULT ?';
            push @ph, $field->{default};
        }
        $f_decl[-1] .= "($field->{max_length})" if exists $field->{max_length};
        push @f_decl, 'AUTO_INCREMENT' if $field->{autoincrement};
        push @sql, join(' ', @f_decl);
    }

    foreach my $index (values $table->{indexes}->%*) {
        my $name;
        if($index->{name} eq 'PRIMARY' and $index->{is_unique}) {
            $name = 'PRIMARY KEY';
        }
        elsif($index->{is_unique}) {
            $name = "UNIQUE INDEX `$index->{name}`";
        }
        else {
            $name = "INDEX `$index->{name}`";
        }
        push @sql, sprintf('%s (%s)', $name, join(', ', $index->{fields}->@*));
    }

    my $sql = sprintf("CREATE %s TABLE `%s` (\n\t%s\n)",
        ($mode eq 'TEMP' ? 'TEMPORARY' : ''), $table->{name}, join ",\n\t", @sql);

    $self->{dbh}->do($sql, undef, @ph);
}

1;
