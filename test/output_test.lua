--- Тесты выдачи: только объявленное, без скрытого, именами снаружи.

local datetime = require('datetime')
local json = require('json')
local msgpack = require('msgpack')
local t = require('luatest')
local uuid = require('uuid')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.data.output')

local data = helper.data

---@type TntDataShape<table>
local User

---@type TntDataShape<table>
local Address

helper.declare(g, function()
    Address = data.define({
        name = 'Address',
        fields = {
            { 'city', 'string' },
            { 'code', 'string', hidden = true, optional = true },
        },
    })

    User = data.define({
        name = 'User',
        fields = {
            { 'id', 'uuid' },
            { 'name', 'string', as = 'login' },
            { 'password', 'string', hidden = true },
            { 'born', 'date', optional = true },
            { 'seen_at', 'datetime', optional = true },
            { 'address', Address, optional = true },
            { 'tags', 'list', of = 'string', optional = true },
            { 'places', 'map', of = Address, optional = true },
            { 'extra', 'any', optional = true },
        },
    })
end)

local ID = uuid.fromstr('a1b2c3d4-0000-4000-8000-000000000000')

g.test_only_declared_visible_fields_go_out_by_outside_names = function()
    local out =
        User.to_table({ id = 'x', name = 'Мария', password = 'тайна', internal = 1, login = 'чужое' })

    t.assert_equals(out, { id = 'x', login = 'Мария' })
    t.assert_equals(json.encode(out.address), 'null')
end

g.test_values_of_tarantool_become_their_records = function()
    local out = User.to_table({
        id = ID,
        name = 'a',
        born = datetime.new({ year = 2026, month = 9, day = 19 }),
        seen_at = datetime.parse('2026-09-19T10:20:30.5+03:00'),
    })

    t.assert_equals(out, {
        id = 'a1b2c3d4-0000-4000-8000-000000000000',
        login = 'a',
        born = '2026-09-19',
        seen_at = '2026-09-19T10:20:30.500+03:00',
    })
    t.assert_equals(
        User.to_table({ id = 'x', name = 'a', seen_at = datetime.new({ year = 2026, month = 9, day = 19 }) }).seen_at,
        '2026-09-19T00:00:00Z'
    )
    t.assert_equals(
        User.to_table({ id = 'x', name = 'a', seen_at = datetime.parse('2026-09-19T10:20:30-0930') }).seen_at,
        '2026-09-19T10:20:30-09:30'
    )
end

g.test_strings_pass_as_they_are = function()
    t.assert_equals(
        User.to_table({ id = 'x', name = 'a', born = '2026-09-19', seen_at = '2026-09-19T10:20:30+0300' }),
        { id = 'x', login = 'a', born = '2026-09-19', seen_at = '2026-09-19T10:20:30+0300' }
    )
end

g.test_nested_lists_and_maps_follow_their_shapes = function()
    local out = User.to_table({
        id = 'x',
        name = 'a',
        address = { city = 'Ока', code = '1', other = 2 },
        tags = { 'b', 'c' },
        places = { home = { city = 'Тверь', code = '2' } },
        extra = { any = { 1, 2 } },
    })

    t.assert_equals(out, {
        id = 'x',
        login = 'a',
        address = { city = 'Ока' },
        tags = { 'b', 'c' },
        places = { home = { city = 'Тверь' } },
        extra = { any = { 1, 2 } },
    })
end

g.test_empty_objects_lists_and_maps_keep_their_kind_in_json = function()
    local out = User.to_table({ id = 'x', name = 'a', address = { code = '1' }, tags = {}, places = {} })

    t.assert_equals(json.decode(json.encode(out)), { id = 'x', login = 'a', address = {}, tags = {}, places = {} })
    t.assert_str_contains(json.encode(out), '"address":{}')
    t.assert_str_contains(json.encode(out), '"tags":[]')
    t.assert_str_contains(json.encode(out), '"places":{}')
    t.assert_equals(json.encode(Address.to_table({})), '{}')
end

g.test_a_record_encodes_itself_by_its_output = function()
    local user = User.from({ id = 'A1B2C3D4-0000-4000-8000-000000000000', login = 'a', password = 'тайна' })
    local expected = { id = 'a1b2c3d4-0000-4000-8000-000000000000', login = 'a' }

    t.assert_equals(json.decode(json.encode(user)), expected)
    t.assert_equals(msgpack.decode(msgpack.encode(user)), expected)
    t.assert_equals(User.to_table(user --[[@as table]]), expected)
end

g.test_output_that_cannot_be_built_is_refused_with_its_place = function()
    t.assert_equals(
        helper
            .thrown(function()
                User.to_table(helper.wrong('x'))
            end)
            :match('output_test%.lua:%d+: (.*)$'),
        'User — таблица, а не строка'
    )

    local cases = {
        { { id = 'x', name = 'a', address = 'Москва' }, 'User.address — таблица, а не строка' },
        {
            { id = 'x', name = 'a', tags = { name = 'a' } },
            'User.tags — массив, а не таблица с ключом «name»',
        },
        { { id = 'x', name = 'a', places = 'Москва' }, 'User.places — таблица, а не строка' },
        { { id = 'x', name = 'a', places = { home = 5 } }, 'User.places[home] — таблица, а не число' },
    }

    for _, case in ipairs(cases) do
        t.assert_equals(
            helper
                .thrown(function()
                    User.to_table(case[1])
                end)
                :match('output_test%.lua:%d+: (.*)$'),
            case[2]
        )
    end

    local Shelf = data.define({ name = 'Shelf', fields = { { 'books', 'list', of = Address } } })

    t.assert_equals(
        helper
            .thrown(function()
                Shelf.to_table({ books = { { city = 'a' }, 7 } })
            end)
            :match('output_test%.lua:%d+: (.*)$'),
        'Shelf.books[2] — таблица, а не число'
    )
end

g.test_a_refusal_points_at_the_line_that_asked_for_output = function()
    local line
    local message = helper.thrown(function()
        line = helper.here() + 1
        User.to_table({ id = 'x', name = 'a', address = 5 })
    end)

    t.assert_equals(
        { message:match('output_test%.lua:(%d+): (.*)$') },
        { tostring(line), 'User.address — таблица, а не число' }
    )
end

g.test_a_record_that_cannot_be_encoded_refuses_inside_the_encoder = function()
    local input = { id = 'a1b2c3d4-0000-4000-8000-000000000000', login = 'a', password = 'тайна' }
    local user = User.from(input) --[[@as table]]

    user.address = 'Москва'

    local ok, err = pcall(json.encode, user)

    -- Кодировщик заворачивает брошенное в ошибку box; места в тексте нет:
    -- над выдачей стоит кадр C кодировщика.
    t.assert_equals(ok, false)
    t.assert_equals(
        (err --[[@as { message: string }]]).message,
        'User.address — таблица, а не строка'
    )
end
