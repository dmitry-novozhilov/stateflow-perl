use strict;
use warnings FATAL => 'all';
{
    posts    => {
        id           => { type => 'uint64', default => 'AUTOINCREMENT' },
        text         => { type => 'string', max_length => 4096 },
        title        => { type => 'string', max_length => 255 },
        ctime        => { type => 'datetime' },
        comments_cnt => { expr => 'comments[post_id = id].count()', type => 'uint32' }, # TODO: remove type
        uobj_type    => { const => 2 },
        likes_cnt    => { expr => 'votes[target_uobj_type = uobj_type][target_uobj_id = id][is_like = 1].count()', type => 'uint32' }, # TODO: remove type (implement autodetection)
        dislikes_cnt => { expr => 'votes[target_uobj_type = uobj_type][target_uobj_id = id][is_like = 0].count()', type => 'uint32' }, # TODO: remove type (implement autodetection)
        -indexes     => {
            PRIMARY => [ -uniq => 'id' ],
        },
        -selections  => {
            by_id        => { where => [ 'id' ] },
            all_by_ctime => { order => [ 'id' ] }
        },
    },
    comments => {
        id           => { type => 'uint64', default => 'AUTOINCREMENT' },
        post_id      => { type => 'uint64' },
        author_id    => { type => 'uint64' },
        text         => { type => 'string', max_length => 4096 },
        parent_id    => { type => 'uint64' },
        ctime        => { type => 'datetime' },
        uobj_type    => { const => 3 },
        likes_cnt    => { expr => 'votes[target_uobj_type = uobj_type][target_uobj_id = id][is_like = 1].count()', type => 'uint32' }, # TODO: remove type
        dislikes_cnt => { expr => 'votes[target_uobj_type = uobj_type][target_uobj_id = id][is_like = 0].count()', type => 'uint32' }, # TODO: remove type
        -indexes     => {
            PRIMARY    => [ -uniq => 'id' ],
            post_id_id => [ -uniq => 'post_id', 'id' ],
        },
        -selections  => {
            by_id      => { where => [ 'id' ] },
            by_post_id => { where => [ 'post_id' ], order => [ 'id' ] },
        },
    },
    votes    => {
        target_uobj_type => { type => 'uint8' },
        target_uobj_id   => { type => 'uint64' },
        owner_id         => { type => 'uint64' },
        ctime            => { type => 'datetime' },
        is_like          => { type => 'bool' },
        -indexes => {
            PRIMARY => [-uniq => 'target_uobj_type', 'target_uobj_id', 'owner_id']
        }
    }
};
