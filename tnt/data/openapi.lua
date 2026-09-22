--- Описание API по форме: схема OpenAPI 3.0 и сверка её с документом.
---
--- Схема выводится из того же объявления, что проверка и аннотация,
--- и говорит то же, что проверка делает: обязательные поля — те, что
--- без `optional` и без умолчания; границы — `minLength`, `minimum`,
--- `minItems`; перечень — `enum`; лишнее поле — `additionalProperties:
--- false`, если форма его отвергает. Имена свойств — имена снаружи (`as`).
--- Скрытое поле — `writeOnly`: его присылают, но не получают.
--- Необязательное — `nullable`: `null` на его месте проверка читает как
--- отсутствие и принимает.
---
--- Две вещи описанию не передать, и они названы своими ключами `x-`,
--- которые OpenAPI разрешает. Образец строки — образец Lua, а не
--- регулярное выражение ECMA, которого ждёт `pattern`: `%d` там значит
--- другое, и клиент, поверивший ему, проверял бы не то. Он уходит
--- в `x-lua-pattern`. Схемы ссылки — в `x-schemes`: `format: uri`
--- их не ограничивает.
---
--- Вложенная форма — ссылка `#/components/schemas/<имя>`; все формы,
--- на которые ссылается объявление, собирает `components`. Сверка
--- называет первое расхождение путём: `User.properties.tags.items.type`.

local collection = require('tnt.collection')
local show = require('tnt.must.fail').show

local Module = {}

--- Где лежат схемы форм в документе.
Module.REF = '#/components/schemas/'

--- Род JSON по роду поля; у `any` рода нет — годится всё.
---@type table<string, string>
local TYPES = {
    string = 'string',
    integer = 'integer',
    number = 'number',
    boolean = 'boolean',
    uuid = 'string',
    email = 'string',
    url = 'string',
    date = 'string',
    datetime = 'string',
    list = 'array',
    map = 'object',
}

--- Вид строки по роду поля.
---@type table<string, string>
local FORMATS = {
    uuid = 'uuid',
    email = 'email',
    url = 'uri',
    date = 'date',
    datetime = 'date-time',
}

--- Настройки поля → ключи схемы, по родам.
---@type table<string, table<string, string>>
local KEYWORDS = {
    string = { min = 'minLength', max = 'maxLength', one_of = 'enum', pattern = 'x-lua-pattern' },
    integer = { min = 'minimum', max = 'maximum' },
    number = { min = 'minimum', max = 'maximum' },
    url = { max = 'maxLength', schemes = 'x-schemes' },
    list = { min = 'minItems', max = 'maxItems' },
}

--- Обязательно ли поле: без него запись не пройдёт проверку.
---@param field TntDataField
---@return boolean
function Module.required(field)
    return not field.optional and field.default == nil
end

--- Схема значения поля либо элемента, без того, что знает только поле.
---@param field TntDataField
---@return table
local function value_of(field)
    if field.kind == 'shape' then
        return {
            ['$ref'] = Module.REF .. (field.shape --[[@as TntDataAnyShape]]).name,
        }
    end

    -- Пометка словаря: схема `any` пуста, а пустая таблица без неё уехала
    -- бы в JSON списком `[]`, которого OpenAPI схемой не считает.
    local schema = collection.as_map({ type = TYPES[field.kind], format = FORMATS[field.kind] })

    -- Копией: перечень и схемы ссылки — таблицы поля, и правка выданной
    -- схемы поменяла бы и аннотацию, и следующую схему.
    for option, keyword in pairs(KEYWORDS[field.kind] or {}) do
        schema[keyword] = table.deepcopy(field[option])
    end

    if field.kind == 'list' then
        schema.items = value_of(field.of --[[@as TntDataField]])
    elseif field.kind == 'map' then
        schema.additionalProperties = value_of(field.of --[[@as TntDataField]])
    end

    return schema
end

--- Схема свойства: значение плюс описание, умолчание и признаки поля.
---
--- У ссылки соседние ключи OpenAPI 3.0 не читает, поэтому ссылка с ними
--- заворачивается в `allOf`.
---@param field TntDataField
---@param default any Умолчание в виде выдачи; nil — описывать нечего
---@return table
local function property_of(field, default)
    local schema = value_of(field)
    local extra = {
        description = field.about,
        default = default,
        writeOnly = field.hidden or nil,
        nullable = not Module.required(field) or nil,
    }

    if field.kind == 'shape' and next(extra) ~= nil then
        schema = { allOf = { schema } }
    end

    for key, value in pairs(extra) do
        schema[key] = value
    end

    return schema
end

--- Схема формы.
---@param shape TntDataShape<any>
---@param defaults table<string, any> Умолчания полей в виде выдачи, по именам Lua
---@return table
function Module.shape(shape, defaults)
    local properties, required = {}, {}

    for _, field in ipairs(shape.fields) do
        properties[field.key] = property_of(field, defaults[field.name])

        if Module.required(field) then
            table.insert(required, field.key)
        end
    end

    local schema = { type = 'object', description = shape.about, properties = properties }

    -- Пустой `required` OpenAPI 3.0 запрещает: список, если он есть,
    -- обязан быть непустым.
    if required[1] ~= nil then
        schema.required = required
    end

    if shape.unknown == 'error' then
        schema.additionalProperties = false
    end

    return schema
end

--- Форма, которая стоит за полем: у списка и отображения — за элементом.
---@param field TntDataField
---@return TntDataShape<any>|nil
local function nested(field)
    local inner = field

    while inner.of ~= nil do
        inner = inner.of
    end

    return inner.shape
end

--- Формы, названные и вложенные, по именам.
---@param shapes TntDataShape<any>[]
---@return table<string, TntDataShape<any>>|nil found
---@return string|nil complaint
function Module.collect(shapes)
    local found = {}
    local queue = table.copy(shapes)
    local index = 1

    while queue[index] ~= nil do
        local shape = queue[index] --[[@as TntDataAnyShape]]
        local known = found[shape.name]

        if known == nil then
            found[shape.name] = shape

            for _, field in ipairs(shape.fields) do
                local inner = nested(field)

                if inner ~= nil then
                    table.insert(queue, inner)
                end
            end
        elseif known ~= shape then
            return nil, ('две разные формы зовутся %s'):format(shape.name)
        end

        index = index + 1
    end

    return found
end

--- Как назвать значение в отказе сверки.
---@param value any
---@return string
local function shown(value)
    if value == nil then
        return 'нет'
    end

    return show(value)
end

--- Первое расхождение двух схем; nil — сходятся.
---
--- Ключи обходятся по порядку записи, а не как их отдаёт `pairs`: иначе
--- из двух расхождений называлось бы то одно, то другое.
---@param expected any Из объявления
---@param actual any Из документа
---@param path string
---@return string|nil
function Module.difference(expected, actual, path)
    if type(expected) ~= 'table' or type(actual) ~= 'table' then
        if expected == actual then
            return nil
        end

        return ('%s — в описании %s, в объявлении %s'):format(
            path,
            shown(actual),
            shown(expected)
        )
    end

    local keys = {}

    for key in pairs(expected) do
        table.insert(keys, key)
    end

    -- Ключ, который есть с обеих сторон, уже взят: сравнивать его дважды
    -- незачем. `false` на месте значения — тоже значение, а не отсутствие.
    for key in pairs(actual) do
        if expected[key] == nil then
            table.insert(keys, key)
        end
    end

    -- По записи ключа: у списка и словаря, перепутанных в документе, ключи
    -- разного рода, и сравнить их иначе нечем.
    for _, key in ipairs(collection.sort_by(keys, tostring)) do
        local place = ('%s.%s'):format(path, key)

        if type(key) == 'number' then
            place = ('%s[%d]'):format(path, key)
        end

        local complaint = Module.difference(expected[key], actual[key], place)

        if complaint ~= nil then
            return complaint
        end
    end

    return nil
end

return Module
