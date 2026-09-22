--- Форма: объявление, проверенное при загрузке, и всё, что из него следует.
---
--- Из одного объявления получаются вход (`from`, `collect`), выдача
--- (`to_table` и `json.encode` записи), аннотация (`annotation`) и схема
--- описания API (`schema`). Ошибка в объявлении — ошибка программиста:
--- отсюда она уходит текстом, а бросает её фасад строкой того, кто
--- объявлял форму.

local explain = require('tnt.must').explain
local must = require('tnt.must')

local annotation = require('tnt.data.annotation')
local field = require('tnt.data.field')
local openapi = require('tnt.data.openapi')
local output = require('tnt.data.output')
local rules = require('tnt.data.rules')

local Module = {}

--- Настройки объявления формы.
---
--- Имя — имя класса аннотации и схемы в описании API: идентификатор,
--- в котором разрешены и точки, как у классов с пространством имён (`Panel.User`).
--- `unknown = 'keep'`, который знает `tnt-validate`, здесь не бывает:
--- поле, которого нет в объявлении, в запись формы не попадает никогда.
local SPEC = {
    name = { 'matches', '^[%a_][%w_%.]*$' },
    about = '?string',
    fields = 'array',
    unknown = { '?one_of', { 'error', 'drop' } },
}

--- Настройки входа: приведение типов по просьбе, как у `tnt-validate`.
local OPTIONS = { coerce = '?boolean' }

---@class TntDataOptions
---@field coerce boolean|nil Приводить ли строки к числам и логическим значениям

--- Форма данных; `T` — класс записи из аннотации формы.
---@class TntDataShape<T>
---@field name string Имя класса записи и схемы в описании API
---@field about string|nil Что это за данные
---@field unknown string Что с лишним полем во входе: error либо drop
---@field fields TntDataField[] Поля по порядку объявления
---@field from fun(input: any, opts: TntDataOptions|nil): T|nil, table<string, string>|nil Запись либо отказы
---@field collect fun(input: any, opts: TntDataOptions|nil): T[]|nil, table<string, string>|nil Записи либо отказы
---@field to_table fun(value: table): table Выдача: объявленные поля без скрытых, именами снаружи
---@field annotation fun(): string Аннотация EmmyLua записи
---@field schema fun(): table Схема OpenAPI 3.0 записи

--- Форма с любым классом записи — так её видит сам пакет.
---
--- Псевдоним, а не `TntDataShape<any>` на месте: приведение пишется
--- в строке кода, и генератор мутантов менял бы в нём угловые скобки —
--- мутант в комментарии не убить ничем.
---@alias TntDataAnyShape TntDataShape<any>

--- Поля объявления, проверенные по одному и вместе.
---@param spec table
---@param place string
---@return TntDataField[]|nil fields
---@return string|nil complaint
local function fields_of(spec, place)
    if spec.fields[1] == nil then
        return nil, place .. ': fields — непустой список полей'
    end

    local fields, names, keys = {}, {}, {}

    for number, entry in ipairs(spec.fields) do
        local item, complaint = field.named(entry, place, number)

        if item == nil then
            return nil, complaint
        end

        -- Одно имя Lua у двух полей — второе затёрло бы первое в записи,
        -- одно имя снаружи — во входе и в выдаче. Имена Lua и имена снаружи
        -- живут порознь: поле `a` с `as = 'b'` рядом с полем `b`, у которого
        -- своё `as`, ничему не мешает.
        if names[item.name] then
            return nil, ('%s: поле %s объявлено дважды'):format(place, item.name)
        end

        if keys[item.key] ~= nil then
            return nil,
                ('%s: имя снаружи %s занято полями %s и %s'):format(
                    place,
                    item.key,
                    keys[item.key],
                    item.name
                )
        end

        names[item.name] = true
        keys[item.key] = item.name

        local default, wrong = rules.default_of(item)

        if wrong ~= nil then
            return nil,
                ('%s, поле %s: умолчание не проходит своё правило — %s'):format(
                    place,
                    item.name,
                    wrong
                )
        end

        item.default = default
        table.insert(fields, item)
    end

    return fields
end

--- Умолчания полей в виде выдачи — то, что видит клиент, для описания API.
---
--- Умолчание-функцию описать нечем: её ответ известен только на входе.
---@param shape TntDataShape<any>
---@return table<string, any>
local function defaults_of(shape)
    local defaults = {}

    for _, item in ipairs(shape.fields) do
        if item.default ~= nil and type(item.default) ~= 'function' then
            -- Умолчание прошло своё правило, и выдача из него отказать не может.
            defaults[item.name] = output.value(item, item.default, shape.name)
        end
    end

    return defaults
end

--- Собирает форму по объявлению.
---@param spec any
---@return TntDataShape<any>|nil shape
---@return string|nil complaint
function Module.define(spec)
    local complaint = explain.options(spec, 'форма', SPEC)

    if complaint ~= nil then
        return nil, complaint
    end

    local place = 'форма ' .. spec.name
    local fields, wrong = fields_of(spec, place)

    if fields == nil then
        return nil, wrong
    end

    local shape = {
        name = spec.name,
        about = spec.about,
        unknown = spec.unknown or 'error',
        fields = fields,
    }

    function shape.from(input, opts)
        must.at(2).optional.options(opts, 'настройки', OPTIONS)

        return rules.from(shape, input, opts)
    end

    function shape.collect(input, opts)
        must.at(2).optional.options(opts, 'настройки', OPTIONS)

        return rules.collect(shape, input, opts)
    end

    function shape.to_table(value)
        local result, refusal = output.record(shape, value, shape.name)

        if refusal ~= nil then
            error(refusal, 2)
        end

        return result --[[@as table]]
    end

    function shape.annotation()
        return annotation.text(shape)
    end

    function shape.schema()
        return openapi.shape(shape, defaults_of(shape))
    end

    -- Запись кодируется своей выдачей: `json.encode(record)` и ответ
    -- по net.box уносят то же, что `to_table`, без скрытых полей.
    rules.record(shape, { __serialize = shape.to_table })
    field.SHAPES[shape] = true

    return shape --[[@as TntDataAnyShape]]
end

return Module
