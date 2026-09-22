--- Тесты описания API: схема по объявлению, набор схем и сверка с документом.

local json = require('json')
local t = require('luatest')
local yaml = require('yaml')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.data.openapi')

local data = helper.data

---@type TntDataShape<table>
local Address

---@type TntDataShape<table>
local Tag

---@type TntDataShape<table>
local User

helper.declare(g, function()
    Address = data.define({
        name = 'Address',
        about = 'Адрес доставки',
        unknown = 'drop',
        fields = {
            { 'city', 'string', min = 1, max = 64 },
            { 'zip', 'string', pattern = '^%d+$', optional = true },
        },
    })

    Tag = data.define({ name = 'Tag', fields = { { 'label', 'string' } } })

    User = data.define({
        name = 'User',
        fields = {
            { 'id', 'integer', min = 1, max = 99 },
            { 'weight', 'number', min = 0.5 },
            { 'admin', 'boolean', default = false },
            { 'name', 'string', about = 'Имя' },
            { 'role', 'string', one_of = { 'admin', 'viewer' }, default = 'viewer' },
            { 'password', 'string', hidden = true },
            { 'key', 'uuid', optional = true },
            { 'mail', 'email', optional = true },
            { 'site', 'url', optional = true },
            { 'repo', 'url', max = 100, schemes = { 'git' }, optional = true },
            { 'born', 'date', optional = true },
            { 'seen_at', 'datetime', as = 'seenAt', optional = true },
            { 'extra', 'any', optional = true },
            { 'home', Address },
            { 'work', Address, about = 'Работа', optional = true },
            { 'secret', Address, hidden = true },
            { 'tags', 'list', of = Tag, min = 1, max = 5 },
            { 'grid', 'list', of = { 'list', of = 'integer' }, default = { { 1 } } },
            { 'places', 'map', of = Address, optional = true },
            {
                'made',
                'integer',
                default = function()
                    return 1
                end,
            },
        },
    })
end)

--- Ожидаемая схема `User`.
local USER = {
    type = 'object',
    additionalProperties = false,
    required = { 'id', 'weight', 'name', 'password', 'home', 'secret', 'tags' },
    properties = {
        id = { type = 'integer', minimum = 1, maximum = 99 },
        weight = { type = 'number', minimum = 0.5 },
        admin = { type = 'boolean', default = false, nullable = true },
        name = { type = 'string', description = 'Имя' },
        role = { type = 'string', enum = { 'admin', 'viewer' }, default = 'viewer', nullable = true },
        password = { type = 'string', writeOnly = true },
        key = { type = 'string', format = 'uuid', nullable = true },
        mail = { type = 'string', format = 'email', nullable = true },
        site = {
            type = 'string',
            format = 'uri',
            maxLength = 2048,
            ['x-schemes'] = { 'http', 'https' },
            nullable = true,
        },
        repo = { type = 'string', format = 'uri', maxLength = 100, ['x-schemes'] = { 'git' }, nullable = true },
        born = { type = 'string', format = 'date', nullable = true },
        seenAt = { type = 'string', format = 'date-time', nullable = true },
        extra = { nullable = true },
        home = { ['$ref'] = '#/components/schemas/Address' },
        work = {
            allOf = { { ['$ref'] = '#/components/schemas/Address' } },
            description = 'Работа',
            nullable = true,
        },
        secret = { allOf = { { ['$ref'] = '#/components/schemas/Address' } }, writeOnly = true },
        tags = { type = 'array', items = { ['$ref'] = '#/components/schemas/Tag' }, minItems = 1, maxItems = 5 },
        grid = {
            type = 'array',
            items = { type = 'array', items = { type = 'integer' } },
            default = { { 1 } },
            nullable = true,
        },
        places = {
            type = 'object',
            additionalProperties = { ['$ref'] = '#/components/schemas/Address' },
            nullable = true,
        },
        made = { type = 'integer', nullable = true },
    },
}

--- Ожидаемая схема `Address`.
local ADDRESS = {
    type = 'object',
    description = 'Адрес доставки',
    required = { 'city' },
    properties = {
        city = { type = 'string', minLength = 1, maxLength = 64 },
        zip = { type = 'string', ['x-lua-pattern'] = '^%d+$', nullable = true },
    },
}

g.test_the_schema_follows_the_declaration = function()
    t.assert_equals(User.schema(), USER)
    t.assert_equals(Address.schema(), ADDRESS)
end

g.test_a_shape_with_optional_fields_only_has_no_required_list = function()
    local Loose = data.define({ name = 'Loose', fields = { { 'a', 'string', optional = true } } })

    t.assert_equals(Loose.schema(), {
        type = 'object',
        additionalProperties = false,
        properties = { a = { type = 'string', nullable = true } },
    })
end

g.test_the_schema_is_valid_json_with_objects_where_objects_are = function()
    local encoded = json.encode(User.schema())

    t.assert_str_contains(encoded, '"extra":{"nullable":true}')
    t.assert_equals(json.encode(helper.single({ 'extra', 'list', of = 'any' }).schema().properties.extra.items), '{}')
    t.assert_equals(json.decode(encoded), json.decode(json.encode(USER)))
end

g.test_a_schema_is_a_fresh_copy_every_time = function()
    local first = User.schema()

    table.insert(first.properties.role.enum, 'root')
    table.insert(first.properties.site['x-schemes'], 'ftp')

    t.assert_equals(User.schema(), USER)
    t.assert_equals((User.fields[5] --[[@as TntDataField]]).one_of, { 'admin', 'viewer' })
end

g.test_a_default_is_described_as_it_goes_out = function()
    local Box = data.define({
        name = 'Box',
        fields = {
            { 'address', Address, default = { city = 'Ока', zip = '1' } },
            { 'shown', 'string', default = 'x', hidden = true },
        },
    })

    t.assert_equals(Box.schema().properties, {
        address = {
            allOf = { { ['$ref'] = '#/components/schemas/Address' } },
            default = { city = 'Ока', zip = '1' },
            nullable = true,
        },
        shown = { type = 'string', default = 'x', writeOnly = true, nullable = true },
    })
end

g.test_components_collect_named_and_nested_shapes = function()
    local schemas = data.components({ User })

    t.assert_equals(schemas, { User = USER, Address = ADDRESS, Tag = Tag.schema() })
    t.assert_equals(data.components({ Address, Address }), { Address = ADDRESS })
    t.assert_equals(data.components({}), {})
end

g.test_two_shapes_under_one_name_are_refused = function()
    local Other = data.define({ name = 'Address', fields = { { 'street', 'string' } } })
    local Holder = data.define({ name = 'Holder', fields = { { 'a', Address }, { 'b', 'list', of = Other } } })

    for _, shapes in ipairs({ { Address, Other }, { Holder } }) do
        local line
        local message = helper.thrown(function()
            line = helper.here() + 1
            data.components(shapes)
        end)

        t.assert_equals(
            { message:match('openapi_test%.lua:(%d+): (.*)$') },
            { tostring(line), 'две разные формы зовутся Address' }
        )
    end
end

g.test_a_document_written_from_the_components_agrees = function()
    local document = yaml.decode(yaml.encode({ components = { schemas = data.components({ User }) } }))

    document.components.schemas.Refusal = { type = 'object' }

    t.assert_equals({ data.described(document.components.schemas, { User }) }, { true })
    t.assert_equals({ data.described({ Tag = Tag.schema() }, { Tag }) }, { true })
end

g.test_the_first_difference_is_named_by_its_path = function()
    local function described(edit)
        local schemas = yaml.decode(yaml.encode(data.components({ User })))

        edit(schemas)

        return { data.described(schemas, { User }) }
    end

    t.assert_equals(
        described(function(schemas)
            schemas.Tag = nil
        end),
        { nil, 'в описании нет схемы Tag' }
    )
    t.assert_equals(
        described(function(schemas)
            schemas.User.properties.name.description = 'Фамилия'
        end),
        {
            nil,
            'описание расходится с объявлением: '
                .. 'User.properties.name.description — в описании «Фамилия», в объявлении «Имя»',
        }
    )
    t.assert_equals(
        described(function(schemas)
            schemas.User.required[3] = 'nick'
        end),
        {
            nil,
            'описание расходится с объявлением: User.required[3] — в описании «nick», в объявлении «name»',
        }
    )
    t.assert_equals(
        described(function(schemas)
            schemas.Address.properties.city.format = 'email'
        end),
        {
            nil,
            'описание расходится с объявлением: Address.properties.city.format — в описании «email», в объявлении нет',
        }
    )
    t.assert_equals(
        described(function(schemas)
            schemas.User.properties.tags = 'список'
        end),
        {
            nil,
            'описание расходится с объявлением: User.properties.tags — в описании «список», в объявлении таблица',
        }
    )
    t.assert_equals(
        described(function(schemas)
            schemas.User.properties.id.maximum = 100
            schemas.User.properties.id.minimum = 0
        end),
        {
            nil,
            'описание расходится с объявлением: User.properties.id.maximum — в описании 100, в объявлении 99',
        }
    )
end

g.test_wrong_arguments_of_described_are_refused_at_the_caller = function()
    local cases = {
        {
            helper.wrong('схемы'),
            { User },
            'схемы описания — таблица, а не строка',
        },
        { {}, helper.wrong({ 'User' }), 'формы[1] — форма data.define, а не «User»' },
    }

    for _, case in ipairs(cases) do
        local line
        local message = helper.thrown(function()
            line = helper.here() + 1
            data.described(case[1], case[2])
        end)

        t.assert_equals({ message:match('openapi_test%.lua:(%d+): (.*)$') }, { tostring(line), case[3] })
    end

    local line
    local message = helper.thrown(function()
        line = helper.here() + 1
        data.components(helper.wrong({ shape = User }))
    end)

    t.assert_equals(
        { message:match('openapi_test%.lua:(%d+): (.*)$') },
        { tostring(line), 'формы — массив, а не таблица с ключом «shape»' }
    )
end
