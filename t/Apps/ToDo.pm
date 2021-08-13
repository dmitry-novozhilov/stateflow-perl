use strict;
use warnings FATAL => 'all';

{
    tasks => {
        id          => { type => 'uint64', default => 'AUTOINCREMENT' },
        text        => { type => 'string', max_length => 255 },
        is_done     => { type => 'bool' },
        -selections => {
            all_by_id => { order => [ 'id' ] },
        },
    },
};
