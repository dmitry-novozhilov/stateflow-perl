use strict;
use warnings FATAL => 'all';

use Const::Fast;

const my %USER_TYPES => (REGULAR => 1, GUEST => 2);
const my %OBJ_TYPES => (PICTURE => 7, VIDEO => 25);
const my %FB_TYPES => (VIEW => 1, LIKE => 2, DISLIKE => 3, REC_DEL => 4);
const my %FB_TYPE2SIMILARITY => (
    $FB_TYPES{VIEW}    => 0,
    $FB_TYPES{LIKE}    => 1,
    $FB_TYPES{DISLIKE} => -2,
    $FB_TYPES{REC_DEL} => 1,
);


{
    date_cursors         => {
        name     => { type => 'string', max_length => '255' },
        value    => { type => 'datetime' },
        -indexes => {
            PRIMARY => [ -uniq => 'name' ],
        }
    },
    feedback             => {
        user        => {
            type  => { type => 'uint8' },
            TYPES => \%USER_TYPES,
            id    => { type => 'uint64' },
        },
        obj         => {
            type  => { type => 'uint8' },
            TYPES => \%OBJ_TYPES,
            id    => { type => 'uint64' },
        },
        fb_type     => { type => 'uint8' },
        FB_TYPES    => \%FB_TYPES,
        ctime       => { type => 'datetime' },
        is_outdated => '= ctime < date_cursors[name = \'outdate\'].value',
    },
    user_stats           => {
        -src      => 'feedback',
        -group_by => [ 'user' ], # == user.type, user.id
        -filter   => '! is_outdated',
        cnt       => '= count',
        is_ok     => '= count >= 3 && count <= 1000',
        # `SELECT user_type, user_id, count(*) AS cnt
        # FROM feedback
        # WHERE ctime > (SELECT value FROM date_cursors WHERE name = 'outdate' LIMIT 1)
        # GROUP BY user_type, user_id`,
    },
    obj_stats            => {
        -src      => 'feedback',
        -group_by => [ 'obj' ],
        -filter   => '! is_outdated',
        cnt       => '= count',
        is_ok     => '= count >= 10 && count <= 100',
        # `SELECT obj_type, obj_id, count(*) AS cnt
        # FROM recom_collab_feedback
        # WHERE ctime > (SELECT value FROM recom_collab_cursors WHERE name = 'outdate' LIMIT 1)
        # GROUP BY obj_type, obj_id`,
    },
    feedback_in_work     => {
        -src    => 'feedback',
        -filter => 'user_stats[user = user].is_ok && obj_stats[obj = obj].is_ok && ! is_outdated',
    },
    same_objs_poten      => {
        -src       => [ 'feedback_in_work', -as => 'a', -join => 'feedback_in_work', as => 'b', -on => 'a.obj.type = b.obj.type, a.user = b.user' ],
        -filter    => [ 'similarity.FB_TYPE_TO_SIMILARITY[a.fb_type]', 'similarity.FB_TYPE_TO_SIMILARITY[b.fb_type]' ],
        obj        => {
            type => 'obj.type',
            a_id => 'a.obj.id',
            b_id => 'b.obj.id',
        },
        similarity => {
            FB_TYPE_TO_SIMILARITY => \%FB_TYPE2SIMILARITY,
            a_val                 => '= FB_TYPE_TO_SIMILARITY[a.fb_type]',
            b_val                 => '= FB_TYPE_TO_SIMILARITY[b.fb_type]',
            value                 => q{= (a_val < 0 && b_val < 0) ? 0 : (a_val > 0 && b_val > 0) ? 1 : -1) * (a_val + b_val)},
            neg                   => '= value < 0 ? value : 0',
            pos                   => '= value > 0 ? value : 0',
        },
    },
    same_objs_poten_uniq => {
        -src       => 'same_objs_poten',
        -group_by  => [ 'obj' ],
        obj        => 'obj',
        similarity => {
            neg => 'sum(neg)',
            pos => 'sum(pos)',
        },
        # SELECT
        #     low.obj_type AS obj_type,
        #     low.obj_id AS low_obj_id,
        #     hi.obj_id AS hi_obj_id,
        #     sum(
        #         if(
        #             low.fb_type IN(3,4) AND hi.fb_type IN(3,4),
        #             0,
        #             (
        #                 + abs(CASE low.fb_type WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN -2 WHEN 4 THEN -1 END)
        #                 + abs(CASE hi.fb_type WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN -2 WHEN 4 THEN -1 END)
        #             )
        #             * if(
        #                 low.fb_type = 2 AND low.fb_type = 2,
        #                 0,
        #                 1
        #            )
        #         )
        #     ) AS similarity_neg,
        #     sum(
        #         if(
        #             low.fb_type IN(3,4) AND hi.fb_type IN(3,4),
        #             0,
        #             (
        #                 + abs(CASE low.fb_type WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN -2 WHEN 4 THEN -1 END)
        #                 + abs(CASE hi.fb_type WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN -2 WHEN 4 THEN -1 END)
        #             )
        #             * if(
        #                 low.fb_type = 2 AND hi.fb_type = 2,
        #                 1,
        #                 0
        #             )
        #         )
        #     ) AS similarity_pos
        # FROM spaces_recom_collab_feedback_in_work AS low
        # LEFT JOIN spaces_recom_collab_feedback_in_work AS hi USING(user_type, user_id, obj_type)
        # WHERE low.fb_type != 1 AND hi.fb_type != 1 AND low.obj_id < hi.obj_id
        # GROUP BY obj_type, left_obj_id, right_obj_id
    },
    same_objs            => {
        -src       => 'same_objs_poten_uniq',
        -filter    => [ 'similarity.pos > similarity.neg * 10', 'similarity.pos - similarity.net > 3' ],
        obj        => '= obj',
        similarity => 'similarity.pos - similarity.neg',
        # SELECT obj_type, left_obj_id, right_obj_id, if(similarity_pos > similarity_neg * 10, similarity_pos - similarity_neg, 0) AS similarity
        #     FROM same_objs_poten
        #     HAVING similarity > 3
    },
    recs_poten_a         => {
        -src       => [ 'feedback_in_work', -join => 'same_objs', -on => 'feedback_in_work.obj.type = same_objs.obj.type && feedback_in_work.obj.id = same_objs.obj.a_id' ],
        -filter    => [ 'fb_type != feedback.FB_TYPES.VIEW' ],
        -group_by  => [ 'user', 'same_objs.obj.type', 'same_objs.obj.a_id' ],
        similarity => 'sum(similarity)',
        obj        => {
            type => 'feedback_in_work.obj.type',
            id   => 'same_objs.obj.b_id',
        },
    },
    recs_poten_b         => {
        -src       => [ 'feedback_in_work', -join => 'same_objs', -on => 'feedback_in_work.obj.type = same_objs.obj.type && feedback_in_work.obj.id = same_objs.obj.b_id' ],
        -filter    => [ 'fb_type != feedback.FB_TYPES.VIEW' ],
        -group_by  => [ 'user', 'same_objs.obj.type', 'same_objs.obj.b_id' ],
        similarity => 'sum(similarity)',
        obj        => {
            type => 'feedback_in_work.obj.type',
            id   => 'same_objs.obj.a_id',
        },
    },
    recs_poten           => {
        -src      => [ 'recs_poten_a', 'recs_poten_b' ],
        -group_by => [ 'user', 'obj' ],
        # SELECT user_type, user_id, obj_type, obj_id, sum(score_neg) AS score_neg, sum(score_pos) AS score_pos
        # FROM (
        #         (
        #             SELECT fb.user_type, fb.user_id, fb.obj_type, s.hi_obj_id AS obj_id,
        #                 sum(s.similarity * CASE fb.fb_type WHEN 3 THEN 20 WHEN 4 THEN 10 ELSE 0 END) AS score_neg,
        #                 sum(s.similarity * CASE fb.fb_type WHEN 1 THEN 1 WHEN 2 THEN 10 ELSE 0 END) AS score_pos,
        #             FROM feedback_in_work AS fb
        #             LEFT JOIN same_objs AS s ON fb.obj_type = s.obj_type AND fb.obj_id = s.low_obj_id
        #             GROUP BY user_type, user_id, obj_type, s.hi_obj_id
        #         ) UNION ALL (
        #             SELECT fb.user_type, fb.user_id, fb.obj_type, s.low_obj_id AS obj_id,
        #                 sum(s.similarity * CASE fb.fb_type WHEN 3 THEN 20 WHEN 4 THEN 10 ELSE 0 END) AS score_neg,
        #                 sum(s.similarity * CASE fb.fb_type WHEN 1 THEN 1 WHEN 2 THEN 10 ELSE 0 END) AS score_pos,
        #             FROM feedback_in_work AS fb
        #             LEFT JOIN same_objs AS s ON fb.obj_type = s.obj_type AND fb.obj_id = s.hi_obj_id
        #             GROUP BY user_type, user_id, obj_type, s.low_obj_id
        #         )
        #     ) AS rp
        #     GROUP BY user_type, user_id, obj_type, obj_id
    },
    recs    => {
        -src    => 'recs_poten',
        -filter => 'similarity > 10',
    },
}

