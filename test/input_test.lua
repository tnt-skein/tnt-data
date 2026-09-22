--- Тесты входа: запись по форме, отказы, приведение, умолчания, вложенность.

local json = require('json')
local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.data.input')

local data = helper.data

---@type TntDataShape<table>
local Address

---@type TntDataShape<table>
local User

helper.declare(g, function()
    Address = data.define({
        name = 'Address',
        fields = {
            { 'city', 'string', min = 1 },
            { 'code', 'string', hidden = true, optional = true },
        },
    })

    User = data.define({
        name = 'User',
        fields = {
            { 'id', 'integer', min = 1 },
            { 'name', 'string', min = 1, max = 8 },
            { 'role', 'string', one_of = { 'admin', 'viewer' }, default = 'viewer' },
            { 'created_at', 'datetime', as = 'createdAt', optional = true },
            { 'address', Address, optional = true },
            { 'tags', 'list', of = 'string', default = {} },
        },
    })
end)

g.test_a_record_has_lua_names_defaults_and_the_shape_metatable = function()
    local user, errors = User.from({ id = 7, name = 'Мария', createdAt = '2026-09-19T10:00:00+03:00' })

    t.assert_equals(errors, nil)
    t.assert_equals(user, {
        id = 7,
        name = 'Мария',
        role = 'viewer',
        created_at = '2026-09-19T10:00:00+03:00',
        tags = {},
    })
    t.assert_equals(
        json.decode(json.encode(user)),
        { id = 7, name = 'Мария', role = 'viewer', createdAt = '2026-09-19T10:00:00+03:00', tags = {} }
    )
end

g.test_every_refusal_is_named_at_once_by_the_outside_name = function()
    local user, errors = User.from({ id = 0, name = '', createdAt = 'вчера', extra = 1, address = { city = 5 } })

    t.assert_equals(user, nil)
    t.assert_equals(errors, {
        id = 'должно быть целым числом не меньше 1, а не 0',
        name = 'должно быть строкой длиной от 1 до 8 знаков, а сейчас 0 знаков',
        createdAt = "должно быть датой со временем и поясом вида ГГГГ-ММ-ДДTЧЧ:ММ:ССZ, а не 'вчера'",
        extra = 'неизвестное поле',
        ['address.city'] = 'должно быть строкой длиной не меньше 1 знака, а не 5',
    })
end

g.test_the_input_must_be_a_table = function()
    t.assert_equals({ User.from(nil) }, { nil, { ['$'] = 'обязательное поле' } })
    t.assert_equals({ User.from(5) }, { nil, { ['$'] = 'должно быть таблицей, а не 5' } })
end

g.test_a_nested_shape_comes_as_its_record = function()
    local user = User.from({ id = 1, name = 'a', address = { city = 'Москва', code = '101000' } })
    local address = (user --[[@as table]]).address

    t.assert_equals(address, { city = 'Москва', code = '101000' })
    t.assert_equals(json.decode(json.encode(address)), { city = 'Москва' })
end

g.test_an_absent_optional_field_stays_empty = function()
    local user = User.from({ id = 1, name = 'a', address = box.NULL }) --[[@as table]]

    t.assert_equals(user.address, nil)
    t.assert_equals(user.created_at, nil)
end

g.test_a_default_table_is_a_copy_for_each_record = function()
    local first = User.from({ id = 1, name = 'a' }) --[[@as table]]
    local second = User.from({ id = 2, name = 'b' }) --[[@as table]]

    table.insert(first.tags, 'x')

    t.assert_equals(second.tags, {})
    t.assert_equals((User.fields[6] --[[@as TntDataField]]).default, {})
end

g.test_a_default_function_is_called_for_each_record = function()
    local calls = 0
    local Counter = data.define({
        name = 'Counter',
        fields = {
            {
                'number',
                'integer',
                default = function()
                    calls = calls + 1

                    return calls
                end,
            },
        },
    })

    t.assert_equals({ Counter.from({}), Counter.from({}) }, { { number = 1 }, { number = 2 } })
end

g.test_strings_become_numbers_only_on_request = function()
    local input = { id = '5', name = 'a' }

    t.assert_equals(
        select(2, User.from(input)),
        { id = "должно быть целым числом не меньше 1, а не '5'" }
    )
    t.assert_equals(
        select(2, User.from(input, { coerce = false })),
        { id = "должно быть целым числом не меньше 1, а не '5'" }
    )
    t.assert_equals(User.from(input, { coerce = true }), { id = 5, name = 'a', role = 'viewer', tags = {} })
end

g.test_a_hidden_field_does_not_show_its_value_in_a_refusal = function()
    local Login = data.define({
        name = 'Login',
        fields = {
            { 'pin', 'string', pattern = '^%d+$', hidden = true },
            { 'code', 'string', pattern = '^%d+$' },
            { 'backup', Address, hidden = true, optional = true },
        },
    })

    t.assert_equals(select(2, Login.from({ pin = 'abc1', code = 'abc2', backup = { city = 7 } })), {
        pin = 'должно быть строкой по образцу ^%d+$, а не присланным значением',
        code = "должно быть строкой по образцу ^%d+$, а не 'abc2'",
        ['backup.city'] = 'должно быть строкой длиной не меньше 1 знака, а не присланным значением',
    })
end

g.test_a_dropping_shape_drops_unknown_fields = function()
    local Loose = data.define({ name = 'Loose', unknown = 'drop', fields = { { 'id', 'integer' } } })

    t.assert_equals({ Loose.from({ id = 1, extra = 2 }) }, { { id = 1 } })
end

g.test_each_kind_checks_with_its_rule = function()
    local Kinds = data.define({
        name = 'Kinds',
        fields = {
            { 'n', 'number', max = 1 },
            { 'b', 'boolean' },
            { 'u', 'uuid' },
            { 'e', 'email' },
            { 'd', 'date' },
            { 'a', 'any' },
            { 'p', 'string', pattern = '^%d+$' },
            { 'l', 'list', of = 'integer', min = 2, max = 3 },
            { 'm', 'map', of = 'boolean' },
        },
    })

    t.assert_equals(
        Kinds.from({
            n = 0.5,
            b = true,
            u = 'A1B2C3D4-0000-4000-8000-000000000000',
            e = 'a@example.org',
            d = '2026-09-19',
            a = { 1 },
            p = '42',
            l = { 1, 2 },
            m = { on = true },
        }),
        {
            n = 0.5,
            b = true,
            u = 'a1b2c3d4-0000-4000-8000-000000000000',
            e = 'a@example.org',
            d = '2026-09-19',
            a = { 1 },
            p = '42',
            l = { 1, 2 },
            m = { on = true },
        }
    )

    local _, errors = Kinds.from({
        n = 2,
        b = 'да',
        u = 'x',
        e = 'x',
        d = '2026-02-30',
        p = 'a',
        l = { 1 },
        m = { [1] = true, on = 'да' },
    })

    t.assert_equals(errors, {
        n = 'должно быть числом не больше 1, а не 2',
        b = "должно быть логическим значением, а не 'да'",
        u = "должно быть UUID, а не 'x'",
        e = "должно быть почтовым адресом, а не 'x'",
        d = "должно быть датой вида ГГГГ-ММ-ДД, а не '2026-02-30'",
        a = 'обязательное поле',
        p = "должно быть строкой по образцу ^%d+$, а не 'a'",
        l = 'должно быть списком от 2 до 3 элементов, а сейчас 1 элемент',
        ['m[1]'] = 'имя ключа должно быть строкой, а не 1',
        ['m.on'] = "должно быть логическим значением, а не 'да'",
    })
end

g.test_a_link_is_checked_by_its_limit_and_schemes = function()
    local Links = data.define({
        name = 'Links',
        fields = {
            { 'site', 'url', optional = true },
            { 'repo', 'url', max = 20, schemes = { 'git' }, optional = true },
        },
    })

    t.assert_equals(select(2, Links.from({ site = 'ftp://example.org' })), {
        site = "должно быть ссылкой http или https, а не 'ftp://example.org'",
    })
    t.assert_equals(Links.from({ repo = 'git://example.org' }), { repo = 'git://example.org' })
    t.assert_equals(select(2, Links.from({ repo = 'git://example.org/very/long' })), {
        repo = 'должно быть ссылкой git длиной не больше 20 знаков, а сейчас 27 знаков',
    })
end

g.test_lists_and_maps_of_shapes_come_as_records = function()
    local Book = data.define({
        name = 'Book',
        fields = {
            { 'places', 'list', of = Address },
            { 'by_name', 'map', of = Address, optional = true },
        },
    })

    local book =
        Book.from({ places = { { city = 'Тверь', code = '1' } }, by_name = { home = { city = 'Ока' } } })

    t.assert_equals(
        json.decode(json.encode(book)),
        { places = { { city = 'Тверь' } }, by_name = { home = { city = 'Ока' } } }
    )
    t.assert_equals(select(2, Book.from({ places = { { city = '' } } })), {
        ['places[1].city'] = 'должно быть строкой длиной не меньше 1 знака, а сейчас 0 знаков',
    })
end

g.test_collect_gives_records_or_refusals_by_position = function()
    local users = User.collect({ { id = 1, name = 'a' }, { id = 2, name = 'b' } }) --[[@as table[] ]]

    t.assert_equals(#users, 2)
    t.assert_equals(users[2], { id = 2, name = 'b', role = 'viewer', tags = {} })
    t.assert_equals(json.decode(json.encode(users[1])), { id = 1, name = 'a', role = 'viewer', tags = {} })
    t.assert_equals({ User.collect({ { id = 1, name = 'a' }, { id = 0, name = 'b' } }) }, {
        nil,
        { ['[2].id'] = 'должно быть целым числом не меньше 1, а не 0' },
    })
    t.assert_equals({ User.collect({ id = 1 }) }, {
        nil,
        {
            ['$'] = 'должно быть списком, а не таблицей с именованными полями',
        },
    })
    local coerced = User.collect({ { id = '3', name = 'c' } }, { coerce = true }) --[[@as table[] ]]

    t.assert_equals(coerced, { { id = 3, name = 'c', role = 'viewer', tags = {} } })
end

g.test_input_options_are_checked_at_the_caller = function()
    for _, call in ipairs({ User.from, User.collect }) do
        local line
        local message = helper.thrown(function()
            line = helper.here() + 1
            call({}, { coerse = true })
        end)

        t.assert_equals(
            { message:match('input_test%.lua:(%d+): (.*)$') },
            { tostring(line), 'настройки: ключа «coerse» нет, есть coerce' }
        )
    end

    t.assert_str_contains(
        helper.thrown(function()
            User.from({}, helper.wrong('coerce'))
        end),
        'настройки — таблица, а не строка'
    )
end
