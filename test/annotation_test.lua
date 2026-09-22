--- Тесты аннотации: текст по объявлению и сверка его с модулем.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.data.annotation')

local data = helper.data

---@type TntDataShape<table>
local Address

---@type TntDataShape<table>
local User

helper.declare(g, function()
    Address = data.define({
        name = 'Address',
        about = 'Адрес доставки',
        fields = { { 'city', 'string' } },
    })

    User = data.define({
        name = 'Panel.User',
        about = 'Пользователь панели\n\nзаводится оператором',
        fields = {
            { 'id', 'integer' },
            { 'weight', 'number', optional = true },
            { 'admin', 'boolean', default = false },
            { 'name', 'string', about = 'Имя, как его видят в панели' },
            { 'role', 'string', one_of = { 'admin', 'viewer' }, default = 'viewer' },
            { 'quote', 'string', one_of = { 'a"b', 'c' }, optional = true },
            { 'key', 'uuid' },
            { 'mail', 'email' },
            { 'site', 'url' },
            { 'born', 'date' },
            { 'seen_at', 'datetime', as = 'seenAt' },
            { 'extra', 'any', optional = true },
            { 'address', Address, optional = true },
            { 'tags', 'list', of = 'string' },
            { 'grid', 'list', of = { 'list', of = 'integer' } },
            { 'modes', 'list', of = { 'string', one_of = { 'r', 'w' } } },
            { 'places', 'map', of = Address },
            { 'flags', 'map', of = { 'string', one_of = { 'on' } }, optional = true },
        },
    })
end)

--- Аннотация `User` так, как её пишут в модуле.
local USER_LINES = {
    '---@class Panel.User',
    '---@field id integer',
    '---@field weight number|nil',
    '---@field admin boolean',
    '---@field name string Имя, как его видят в панели',
    '---@field role "admin"|"viewer"',
    '---@field quote string|nil',
    '---@field key string',
    '---@field mail string',
    '---@field site string',
    '---@field born string',
    '---@field seen_at string',
    '---@field extra any|nil',
    '---@field address Address|nil',
    '---@field tags string[]',
    '---@field grid integer[][]',
    '---@field modes ("r"|"w")[]',
    '---@field places table<string, Address>',
    '---@field flags table<string, "on">|nil',
}

g.test_the_annotation_follows_the_declaration = function()
    t.assert_equals(
        User.annotation(),
        '--- Пользователь панели\n---\n--- заводится оператором\n'
            .. table.concat(USER_LINES, '\n')
            .. '\n'
    )
    t.assert_equals(Address.annotation(), '--- Адрес доставки\n---@class Address\n---@field city string\n')
    t.assert_equals(helper.single({ 'id', 'integer' }).annotation(), '---@class Single\n---@field id integer\n')
end

g.test_an_annotation_in_the_source_agrees_with_the_declaration = function()
    local source = table.concat({
        'local data = require("tnt.data")',
        '',
        '    ' .. table.concat(USER_LINES, '  \n    '),
        '',
        '--- Адрес',
        '---@class Address',
        '---@field city string',
        'local User = data.define({})',
    }, '\n')

    t.assert_equals({ data.annotated(source, { User, Address }) }, { true })
    t.assert_equals({ data.annotated(Address.annotation(), { Address }) }, { true })
    t.assert_equals({ data.annotated('x', {}) }, { true })
end

g.test_a_missing_annotation_is_named = function()
    t.assert_equals(
        { data.annotated('---@class User\n---@field city string\n', { Address }) },
        { nil, 'аннотации ---@class Address в тексте нет' }
    )
end

g.test_the_first_difference_is_named = function()
    t.assert_equals({ data.annotated('---@class Address\n---@field city integer\n', { Address }) }, {
        nil,
        'аннотация Address расходится с объявлением: ждали «---@field city string», а стоит «---@field city integer»',
    })
    t.assert_equals({ data.annotated('---@class Address\nlocal x = 1\n---@field city string\n', { Address }) }, {
        nil,
        'аннотация Address расходится с объявлением: не хватает строки «---@field city string»',
    })
    t.assert_equals(
        { data.annotated('---@class Address\n---@field city string\n---@field zip string\n', { Address }) },
        {
            nil,
            'аннотация Address расходится с объявлением: лишняя строка «---@field zip string»',
        }
    )
    t.assert_equals({
        data.annotated('---@class Address\n---@field city string\n---@field zip string\n---@field a b\n', { Address }),
    }, {
        nil,
        'аннотация Address расходится с объявлением: лишняя строка «---@field zip string»',
    })
end

g.test_only_the_lines_right_after_the_class_are_compared = function()
    local source = '---@field city integer\n---@class Address\n---@field city string\n\n---@field zip string\n'

    t.assert_equals({ data.annotated(source, { Address }) }, { true })
end

g.test_every_named_shape_is_checked = function()
    t.assert_equals(
        { data.annotated(Address.annotation(), { Address, User }) },
        { nil, 'аннотации ---@class Panel.User в тексте нет' }
    )
end

g.test_wrong_arguments_are_refused_at_the_caller = function()
    local cases = {
        { helper.wrong(5), { Address }, 'текст модуля — строка, а не число' },
        {
            '',
            helper.wrong({ shape = Address }),
            'формы — массив, а не таблица с ключом «shape»',
        },
        { '', helper.wrong({ Address, 'User' }), 'формы[2] — форма data.define, а не «User»' },
        { '', helper.wrong({ Address.fields }), 'формы[1] — форма data.define, а не таблица' },
    }

    for _, case in ipairs(cases) do
        local line
        local message = helper.thrown(function()
            line = helper.here() + 1
            data.annotated(case[1], case[2])
        end)

        t.assert_equals({ message:match('annotation_test%.lua:(%d+): (.*)$') }, { tostring(line), case[3] })
    end
end
