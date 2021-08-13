package State::Flow::_DB;

# TODO: try SQL::Abstract

use strict;
use warnings FATAL => 'all';
use DBI::Const::GetInfoType;
use Carp; our @CARP_NOT = qw(State::Flow);

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
    
    return bless {dbh => $dbh} => $pkg;
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
        push @rows, '('.join(', ', map {"'$rows->[ $q ]->[ $_ ]'"} 0 .. $#$fields_order).')';
    }

    $self->{dbh}->do("INSERT INTO `$table` (".join(', ', map {"`$_`"} @$fields_order).") VALUES "
        .join(', ', @rows));
}

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


    $self->{dbh}->do("UPDATE `$table` SET ".join(', ', @sets)." WHERE $where");

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

# TODO: SELECT ... WHERE (a=1 AND b=2) OR (a=11 AND b=22)

sub get_and_lock_rows {
    my($self, $table, $matches) = @_;

    my $where = $self->_match_conds_to_sql_where($matches);

    return $self->{dbh}->selectall_arrayref("SELECT * FROM `$table` WHERE $where", {Slice=>{}});
}

sub insert_rows {
    my($self, $table, $fields_order, $rows) = @_;

    # TODO: chunks

    my @rows;
    for(my $q = 0; $q <= $#$rows; $q++) {
        push @rows, "SELECT ".join(', ', map {"'$rows->[ $q ]->[ $_ ]' AS `$fields_order->[ $_ ]`"} 0 .. $#$fields_order);
    }

    $self->{dbh}->do("INSERT INTO `$table` ".join(' UNION ALL ', @rows));
}

package State::Flow::_DB::MySQL;

use strict;
use warnings FATAL => 'all';
use parent 'State::Flow::_DB';

sub get_and_lock_rows {
    my($self, $table, $matches) = @_;

    my $where = $self->_match_conds_to_sql_where($matches);

    return $self->{dbh}->selectall_arrayref("SELECT * FROM `$table` WHERE $where FOR UPDATE", {Slice=>{}});
}

1;
