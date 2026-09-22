--- Тесты объявления формы: что принимается, что отвергается и каким текстом.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.data.define')

local data = helper.data
local refusal = helper.refusal

--- Форма с одним полем адреса: на неё ссылаются вложенные поля.
---@type TntDataShape<table>
local Address

helper.declare(g, function()
    Address = data.define({ name = 'Address', fields = { { 'city', 'string' } } })
end)

g.test_a_shape_keeps_its_name_about_policy_and_fields_in_order = function()
    local User = data.define({
        name = 'Panel.User',
        about = 'Пользователь',
        unknown = 'drop',
        fields = {
            { 'id', 'integer', min = 1, max = 9 },
            { 'name', 'string', as = 'login', about = 'Вход', hidden = true, optional = true },
        },
    })

    t.assert_equals(User.name, 'Panel.User')
    t.assert_equals(User.about, 'Пользователь')
    t.assert_equals(User.unknown, 'drop')
    t.assert_equals(User.fields, {
        {
            name = 'id',
            key = 'id',
            kind = 'integer',
            optional = false,
            hidden = false,
            min = 1,
            max = 9,
        },
        {
            name = 'name',
            key = 'login',
            kind = 'string',
            optional = true,
            hidden = true,
            about = 'Вход',
        },
    })
end

g.test_a_shape_rejects_unknown_input_fields_by_default = function()
    t.assert_equals(helper.single({ 'id', 'integer' }).unknown, 'error')
end

g.test_the_kinds_are_listed_in_order = function()
    t.assert_equals(data.KINDS, {
        'string',
        'integer',
        'number',
        'boolean',
        'uuid',
        'email',
        'url',
        'date',
        'datetime',
        'any',
        'list',
        'map',
    })
end

g.test_a_nested_shape_and_items_are_parsed_into_fields = function()
    local shape = data.define({
        name = 'Order',
        fields = {
            { 'address', Address },
            { 'lines', 'list', of = { 'string', max = 3 }, min = 1 },
            { 'places', 'map', of = Address },
            { 'codes', 'list', of = 'integer' },
        },
    })

    t.assert_is(shape.fields[1].shape, Address)
    t.assert_equals(shape.fields[1].kind, 'shape')
    t.assert_equals(shape.fields[2].of, { kind = 'string', max = 3, optional = false, hidden = false })
    t.assert_equals(shape.fields[2].min, 1)
    t.assert_is(shape.fields[3].of.shape, Address)
    t.assert_equals(shape.fields[3].of.kind, 'shape')
    t.assert_equals(shape.fields[4].of.kind, 'integer')
end

g.test_a_link_gets_the_limit_and_schemes_of_the_validator_explicitly = function()
    local shape = data.define({
        name = 'Links',
        fields = {
            { 'site', 'url' },
            { 'repo', 'url', max = 100, schemes = { 'git' } },
        },
    })

    t.assert_equals({ shape.fields[1].max, shape.fields[1].schemes }, { 2048, { 'http', 'https' } })
    t.assert_equals({ shape.fields[2].max, shape.fields[2].schemes }, { 100, { 'git' } })
end

g.test_the_spec_is_checked_as_options = function()
    t.assert_equals(refusal(helper.wrong('User')), 'форма — таблица, а не строка')
    t.assert_equals(
        refusal({ name = 'User', fields = {}, feilds = {} }),
        'форма: ключа «feilds» нет, есть about, fields, name, unknown'
    )
    t.assert_equals(
        refusal({ name = 'User bad', fields = {} }),
        'форма.name — строка по образцу ^[%a_][%w_%.]*$, а не «User bad»'
    )
    t.assert_equals(
        refusal({ name = '1User', fields = {} }),
        'форма.name — строка по образцу ^[%a_][%w_%.]*$, а не «1User»'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { name = 'x' } }),
        'форма.fields — массив, а не таблица с ключом «name»'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'id', 'integer' } }, unknown = 'keep' }),
        'форма.unknown — одно из «error», «drop», а не «keep»'
    )
    t.assert_equals(
        refusal({ name = 'User', about = 1, fields = {} }),
        'форма.about — строка, а не число'
    )
end

g.test_fields_must_not_be_empty = function()
    t.assert_equals(
        refusal({ name = 'User', fields = {} }),
        'форма User: fields — непустой список полей'
    )
end

g.test_a_field_is_a_table_with_a_lua_name_first = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { 'id' } }),
        'форма User, поле №1 — таблица, а не строка'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'id', 'integer' }, { 'user-name', 'string' } } }),
        'форма User, поле №2: первым стоит имя — идентификатор Lua, а не «user-name»'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 42, 'integer' } } }),
        'форма User, поле №1: первым стоит имя — идентификатор Lua, а не 42'
    )
end

g.test_an_unknown_kind_lists_the_known_ones = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'id', 'int' } } }),
        'форма User, поле id: рода «int» нет, бывают string, integer, number, boolean, uuid, email, url, '
            .. 'date, datetime, any, list, map и форма data.define'
    )
    t.assert_str_contains(
        refusal({ name = 'User', fields = { { 'id' } } }),
        'форма User, поле id: рода nil нет'
    )
    t.assert_str_contains(
        refusal({ name = 'User', fields = { { 'id', { name = 'Address' } } } }),
        'форма User, поле id: рода таблица нет'
    )
end

g.test_options_are_checked_by_kind = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'name', 'string', mim = 1 } } }),
        'форма User, поле name: ключа «mim» нет, есть about, as, default, hidden, max, min, one_of, optional, pattern'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'admin', 'boolean', max = 1 } } }),
        'форма User, поле admin: ключа «max» нет, есть about, as, default, hidden, optional'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'name', 'string', 'extra' } } }),
        'форма User, поле name: ключа «3» нет, есть about, as, default, hidden, max, min, one_of, optional, pattern'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'name', 'string', min = '1' } } }),
        'форма User, поле name.min — число, а не строка'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'role', 'string', one_of = { 'a', 1 } } } }),
        'форма User, поле role.one_of[2] — строка, а не число'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'name', 'string', optional = 'yes' } } }),
        'форма User, поле name.optional — логическое значение, а не строка'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'name', 'string', hidden = 1 } } }),
        'форма User, поле name.hidden — логическое значение, а не число'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'name', 'string', as = '' } } }),
        'форма User, поле name.as — непустая строка, а не пустая'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'site', 'url', max = 1.5 } } }),
        'форма User, поле site.max — целое число, а не 1.5'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'tags', 'list', of = 'string', max = 1.5 } } }),
        'форма User, поле tags.max — целое число, а не 1.5'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'n', 'number', min = '0' } } }),
        'форма User, поле n.min — число, а не строка'
    )
end

g.test_an_about_of_a_field_is_one_line = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'name', 'string', about = 'Имя\nи фамилия' } } }),
        'форма User, поле name.about — строка по образцу ^[^\n]*$, а не «Имя\nи фамилия»'
    )
end

g.test_a_list_and_a_map_need_their_item = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'tags', 'list' } } }),
        'форма User, поле tags.of — строка или таблица, а не nil'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'meta', 'map', of = 1 } } }),
        'форма User, поле meta.of — строка или таблица, а не 1'
    )
end

g.test_an_item_has_no_field_options = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'tags', 'list', of = { 'string', optional = true } } } }),
        'форма User, поле tags, элемент: ключа «optional» нет, есть max, min, one_of, pattern'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'tags', 'list', of = 'strin' } } }),
        'форма User, поле tags, элемент: рода «strin» нет, бывают string, integer, number, boolean, uuid, '
            .. 'email, url, date, datetime, any, list, map и форма data.define'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'grid', 'list', of = { 'list' } } } }),
        'форма User, поле grid, элемент.of — строка или таблица, а не nil'
    )
end

g.test_names_inside_lua_and_outside_are_unique_each = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'id', 'integer' }, { 'id', 'string', as = 'other' } } }),
        'форма User: поле id объявлено дважды'
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'id', 'integer', as = 'key' }, { 'key', 'string' } } }),
        'форма User: имя снаружи key занято полями id и key'
    )

    -- Имена Lua и имена снаружи — разные пространства.
    local swapped = data.define({
        name = 'Swapped',
        fields = { { 'a', 'string', as = 'b' }, { 'b', 'string', as = 'a' } },
    })

    t.assert_equals({ swapped.fields[1].key, swapped.fields[2].key }, { 'b', 'a' })
end

g.test_a_default_must_pass_its_own_rule = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'role', 'string', one_of = { 'admin', 'viewer' }, default = 'root' } } }),
        'форма User, поле role: умолчание не проходит своё правило — '
            .. "должно быть одним из: 'admin', 'viewer', а не 'root'"
    )
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'tags', 'list', of = 'string', default = { 'a', 2, 3 } } } }),
        'форма User, поле tags: умолчание не проходит своё правило — '
            .. '[2] должно быть строкой, а не 2; [3] должно быть строкой, а не 3'
    )
end

g.test_a_checked_default_is_what_the_check_gives = function()
    local shape = data.define({
        name = 'Defaults',
        fields = {
            { 'id', 'uuid', default = 'A1B2C3D4-0000-4000-8000-000000000000' },
            { 'address', Address, default = { city = 'Москва' } },
            {
                'made',
                'integer',
                default = function()
                    return 1
                end,
            },
        },
    })

    t.assert_equals(shape.fields[1].default, 'a1b2c3d4-0000-4000-8000-000000000000')
    t.assert_equals(shape.fields[2].default, { city = 'Москва' })
    t.assert_not_equals(getmetatable(shape.fields[2].default), nil)
    t.assert_equals(type(shape.fields[3].default), 'function')
end

g.test_a_refusal_points_at_the_line_that_declared_the_shape = function()
    local line
    local ok, err = pcall(function()
        line = helper.here() + 1
        data.define({ name = 'User', fields = {} })
    end)

    t.assert_equals(ok, false)
    t.assert_equals(
        { tostring(err):match('define_test%.lua:(%d+): (.*)$') },
        { tostring(line), 'форма User: fields — непустой список полей' }
    )
end

g.test_a_shape_is_known_as_a_kind_only_after_it_is_declared = function()
    t.assert_equals(
        refusal({ name = 'User', fields = { { 'address', Address.fields } } }),
        'форма User, поле address: рода таблица нет, бывают string, integer, number, boolean, uuid, email, url, '
            .. 'date, datetime, any, list, map и форма data.define'
    )
end

g.test_only_a_declared_shape_is_a_shape = function()
    t.assert_equals(data.is(Address), true)
    t.assert_equals(data.is({ name = 'Address', fields = Address.fields }), false)
    t.assert_equals(data.is(nil), false)
    t.assert_equals(data.is('Address'), false)
end
