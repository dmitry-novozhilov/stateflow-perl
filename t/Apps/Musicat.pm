use strict;
use warnings FATAL => 'all';

{
    file                => {
        md5         => { type => 'string', max_length => 32 },
        file_id     => { type => 'uint64', default => 'AUTOINCREMENT' },
        rate        => { type => 'float64' },
        cat_trid    => { type => 'uint64' },
        -selections => {
            by_md5_by_rate => { where => [ 'md5' ], order => [ -desc => 'rate', -desc => 'id' ] },
        },
    },
    music               => {
        -extends => 'file',
        cat_arid => { type => 'uint64' },
        cat_alid => { type => 'uint64' },
        cat_trid => { type => 'uint64' },
    },
    musicat_track       => {
        id        => { type => 'uint64' },
        arid      => { type => 'uint64' },
        # top_by(rate) создаёт в music выборку {where=>['cat_trid'], order=>[-desc=>'rate']}, если её нет
        best_md5  => '= music[cat_trid = id].top_by(rate).md5',
        best_file => '= music[cat_trid = id].top_by(rate).id',
    },
    # Выбирает уникальные md5-суммы привязанных к треку файлов и сортирует их по рейтингу,
    # а для каждой суммы ещё отдаёт лучший файл
    musicat_track_files => {
        -src         => 'music',
        -group_by    => [ 'cat_trid', 'md5' ],
        best_file_id => '= music[cat_trid = cat_trid, md5 = md5].top_by(rate).id',
        -selections  => {
            by_cat_trid_by_rate => { where => [ 'cat_trid' ], order => [ -desc => 'rate' ] }
        },
    },
};
