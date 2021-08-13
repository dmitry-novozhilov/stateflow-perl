use strict;
use warnings FATAL => 'all';

{
    sessions => {
        id      => { type => 'uint64', default => 'AUTOINCREMENT' },
        secret  => { type => 'string', max_length => 64 },
        ctime   => { type => 'datetime' },
        atime   => { type => 'datetime' },
        user_id => { type => 'uint64' },
    },
    users    => {
        id        => { type => 'uint64', default => 'AUTOINCREMENT' },
        name      => { type => 'string', max_length => 16 },
        email     => { type => 'string', max_length => 255 },
        password  => { type => 'string', max_length => 255 },
        reg_time  => { type => 'datetime' },
        uobj_type => { const => 1 },
        -indexes    => {
            PRIMARY => [ -uniq => 'id' ],
            name    => [ -uniq => 'name' ],
            email   => [ -uniq => 'email' ],
        },
        -selections => {
            by_id    => { where => [ 'id' ] },
            by_name  => { where => [ 'name' ] },
            by_email => { where => [ 'email' ] },
        },
    }
}
