#!/usr/bin/perl

use strict;
use warnings;
use Test::Spec;
use Data::Dmp;
use PerlX::Maybe qw/maybe/;
use State::Flow::_Struct::_expr;

describe _expr => sub {
    it _tokenize => sub {
        my $tokens = State::Flow::_Struct::_tokenize('e_tbl[e_fld=i_fld][e_fld=5]["text"=i_fld].count()');

        is_deeply [map {{ type => $_->{type}, maybe value => $_->{value} }} @$tokens],
            [
                {type => 'NAME', value => 'e_tbl'},
                {type => '['},
                {type => 'NAME', value => 'e_fld'},
                {type => '='},
                {type => 'NAME', value => 'i_fld'},
                {type => ']'},
                {type => '['},
                {type => 'NAME', value => 'e_fld'},
                {type => '='},
                {type => 'DIGIT', value => 5},
                {type => ']'},
                {type => '['},
                {type => 'STRING', value => 'text'},
                {type => '='},
                {type => 'NAME', value => 'i_fld'},
                {type => ']'},
                {type => '.'},
                {type => 'NAME', value => 'count'},
                {type => '('},
                {type => ')'},
            ];

        $tokens = State::Flow::_Struct::_tokenize('field2');

        is_deeply [map {{ type => $_->{type}, maybe value => $_->{value} }} @$tokens],
            [{type => 'NAME', value => 'field2'}];
    };

    it _parse_simple_expr => sub {

        my %struct = (i_tbl => {fields => {fld => {expr => 'a + b / c * d'}}});

        my($code, $links) = State::Flow::_Struct::_expr_parse(
            \%struct, i_tbl => 'fld', $struct{i_tbl}->{fields}->{fld}->{expr});

        is_deeply $links, {};

        is ref($code), 'CODE';

        is $code->({a=>1,b=>2,c=>3,d=>4}), 1 + 2 / 3 * 4;
    };

    it _parse_negtives => sub {

        my %struct = (i_tbl => {fields => {fld => {expr => '-a -b -5'}}});
        my($code, $links) = State::Flow::_Struct::_expr_parse(
            \%struct, i_tbl => 'fld', $struct{i_tbl}->{fields}->{fld}->{expr});

        is_deeply $links, {};

        is ref($code), 'CODE';

        is $code->({a=>1,b=>2}), -1-2-5;
    };

    it _parse_link2count => sub {

        my %struct = (
            i_tbl => {fields => {fld => {expr => 'e_tbl[e_fld=i_fld].count()'}, i_fld => {}}},
            e_tbl => {fields => {e_fld => {}}},
        );

        my($code, $links) = State::Flow::_Struct::_expr_parse(
            \%struct, i_tbl => 'fld', $struct{i_tbl}->{fields}->{fld}->{expr});

        is_deeply $links, {
            'e_tbl[e_fld=i_fld].count()->i_tbl' => {
                name        => 'e_tbl[e_fld=i_fld].count()->i_tbl',
                table       => 'e_tbl',
                match_conds => {e_fld => 'i_fld'},
                src_filters => {},
                dst_filters => {},
                aggregate   => 'count',
            }
        };

        is ref($code), 'CODE';

        is $code->({'_sf_m13n_e_tbl[e_fld=i_fld].count()->i_tbl'=>'%CNT%'}), '%CNT%';
    };

    it _parse_link2field => sub {

        my %struct = (
            i_tbl => {fields => {fld => {expr => 'e_tbl[e_fld=i_fld].e_fld2'}, i_fld => {}}},
            e_tbl => {fields => {e_fld => {}, e_fld2 => {}}},
        );

        my($code, $links) = State::Flow::_Struct::_expr_parse(
            \%struct, i_tbl => fld => $struct{i_tbl}->{fields}->{fld}->{expr},
        );

        is_deeply $links, {
            'e_tbl[e_fld=i_fld].e_fld2->i_tbl' => {
                name        => 'e_tbl[e_fld=i_fld].e_fld2->i_tbl',
                table       => 'e_tbl',
                match_conds => {e_fld => 'i_fld'},
                src_filters => {},
                dst_filters => {},
                field       => 'e_fld2',
            }
        };

        is ref($code), 'CODE';

        is $code->({'_sf_m13n_e_tbl[e_fld=i_fld].e_fld2->i_tbl'=>'%VAL%'}), '%VAL%';

        %struct = (
            i_tbl => { fields => { i_fld => {}, fld => { expr => 'e_tbl[e_fld=i_fld][e_fld=5]["text"=i_fld].e_fld2' } } },
            e_tbl => { fields => { e_fld => {}, e_fld2 => {} } },
        );

        ($code, $links) = State::Flow::_Struct::_expr_parse(
            \%struct, i_tbl => fld => $struct{i_tbl}->{fields}->{fld}->{expr});

        is_deeply $links, {
            'e_tbl[e_fld=i_fld][e_fld=5][text=i_fld].e_fld2->i_tbl' => {
                name        => 'e_tbl[e_fld=i_fld][e_fld=5][text=i_fld].e_fld2->i_tbl',
                table       => 'e_tbl',
                match_conds => {e_fld => 'i_fld'},
                src_filters => {e_fld => 5},
                dst_filters => {i_fld => 'text'},
                field       => 'e_fld2',
            }
        };
    };

    it _parse_link2field_using_const_field => sub {
        my %struct = (
            i_tbl => {
                fields => {
                    i_fld => {},
                    i_const_fld => {const => 123},
                    fld => { expr => 'e_tbl[e_fld=i_const_fld][e_const_field=i_fld].e_fld2' },
                },
            },
            e_tbl => {
                fields => {
                    e_fld => {},
                    e_fld2 => {},
                    e_const_field => {const => 234},
                },
            },
        );
        my($code, $links) = State::Flow::_Struct::_expr_parse(
            \%struct, i_tbl => fld => $struct{i_tbl}->{fields}->{fld}->{expr});

        is_deeply $links, {
            'e_tbl[e_fld=123][234=i_fld].e_fld2->i_tbl' => {
                name        => 'e_tbl[e_fld=123][234=i_fld].e_fld2->i_tbl',
                table       => 'e_tbl',
                match_conds => {},
                src_filters => {e_fld => 123},
                dst_filters => {i_fld => 234},
                field       => 'e_fld2',
            }
        };
    };
};

runtests unless caller;

1;
