use strict;
use warnings FATAL => 'all';

use constant DECLARATION => {
    user_obj                => {
        TYPES => {
            USER      => 1,
            COMMUNITY => 2,
            FILE      => 3,
            DIRECTORY => 4,
        },
        owner => {
            type => {
                type       => 'uint8',
                validators => { 'Only user or community allowed' => '_ = user_obj.TYPES.USER or _ = user_obj.TYPES.COMMUNITY' },
            },
            id   => { type => 'uint64' },
        },
        id    => { type => 'uint64' }
        #'subscribers':    user_obj, file, dir, // ???
    },
    users_group             => {
        TYPES => {
            SYSTEM  => 1,
            FRIENDS => 2,
        },
        SYSTEM_IDS  => {
            USERS   => 1,
            ADMINS  => 2,
        },
        type  => { type => 'uint8' },
        id    => { type => 'uint64' },
        title => { type => 'string', max_length => 64 },
    },
    users_group_members     => {
        group          => {
            type => { type => 'uint8' },
            id   => { type => 'uint64' },
        },
        member_user_id => { type => 'uint64' },
    },
    acl_setting_hierarhical => {
        -extends        => 'user_obj',
        group_of_access => {
            own       => { # Это массив групп, которым доступен данный объект
                # Такое может жить только сериализуемом мета-поле
                -array => {
                    type => { type => 'uint8' },
                    id   => { type => 'uint64' },
                }
            },
            effective => <<~'EXPR', # Это бинарь (для участия в индексе), в котором записано всё о доступе
                pack( # Пакуем в бинарь
                    sort( # Сортируем для дедупликации
                        pack( # Пакуем в бинарь
                            sort(group_of_access.own) # Сортируем для дедупликации
                        ),
                        # Добавляем группы доступа родителя
                        parent_obj.id
                            ? pack(parent_obj.group_of_access.effective)
                            : ()
                    )
                )
            EXPR
            password  => { type => 'string', max_length => 255 },
        }
    },
    file                    => {
        -extends    => 'acl_setting_hierarhical',
        parent_obj  => {
            type => { -const => 'user_obj.TYPES.DIRECTORY' },
            id   => { type => 'uint64' },
        },
        name        => { type => 'string', max_length => 255 },
        ctime       => { type => 'datetime' },
        rate        => { type => 'float64' },
        # 'subscribers': files_of_dir, files_of_owner; // ???
        -selections => {
            by_owner_by_size            => { where => [ 'owner' ], order => [ 'size' ] },
            # Как пользоваться:
            # Запрашиваем все уникальные group_of_access.effective где owner = нужному
            # Проверяем, какие из них нам подходят
            # Запрашиваем UNION выборок по указанному owner и нафильтрованным group_of_access.effective
            by_owner_by_access_by_rate  => { where => [ 'owner', 'group_of_access.effective' ], order => [ 'rate' ] },
            by_owner_by_access_by_ctime => { where => [ 'owner', 'group_of_access.effective' ], order => [ 'ctime' ] },
            by_dir_by_access_by_rate    => { where => [ 'parent_obj.id', 'group_of_access.effective' ], order => [ 'rate' ] },
            by_dir_by_access_by_ctime   => { where => [ 'parent_obj.id', 'group_of_access.effective' ], order => [ 'ctime' ] },
        }
    },
    directory               => {
        -extends    => 'acl_settings_hierarhical',
        parent_obj  => {
            type => { -const => 'user_obj.TYPES.DIRECTORY' },
            id   => { type => 'uint64' },
        },
        name        => { type => 'string', max_length => 255 },
        files_cnt   => { expr => 'directory[parent_obj.id = id].sum(files_cnt) + files[parent_obj.id = id].count' },
        -selections => {
            by_parent_dir           => { where => [ 'parent_obj.id' ], order => [ 'name' ] },
            # Пользоваться так же, как и файловой аналогичной выборкой,
            # но проверка доступности отвечает 'да' на все запароленное
            by_parent_dir_by_access => { where => [ 'parent_obj.id', 'group_of_access.effective' ], order => [ 'name' ] },
        },
    },
};

1;
