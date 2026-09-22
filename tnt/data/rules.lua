--- Вход по форме: правила `tnt-validate` из полей, запись с именами Lua.
---
--- Проверяет `tnt-validate`, и его договор здесь не меняется: все отказы
--- сразу, путь до места — `items[2].price`, лишнее поле — отказ, приведение
--- типов только по просьбе. Пакет добавляет три вещи. Вложенная форма
--- приходит записью своей формы, а не голой таблицей. Имя снаружи (`as`)
--- стоит в пути отказа — клиент читает свой запрос, а не наш код, —
--- а в записи поле зовётся именем Lua. И умолчание проверяется своим же
--- правилом при объявлении: `default = 'root'` рядом с `one_of = { 'admin',
--- 'viewer' }` — ошибка в объявлении, а не значение, которое тихо уедет
--- в хранилище мимо проверки.
---
--- Правила собираются один раз, при объявлении формы: правило — значение,
--- и собирать его на каждый запрос значило бы платить за объявление при
--- каждой проверке.

local collection = require('tnt.collection')
local validate = require('tnt.validate')

local Module = {}

--- Проверка записи по форме — функция правила `tnt-validate`. Держится
--- здесь, а не полем формы: форма — то, что видит вызывающий, а эта
--- функция — кухня входа. Ключи слабые, как у всех таблиц форм.
---@type table<TntDataShape<any>, fun(value: any, node: table): any, string|nil>
local RECORDS = setmetatable({}, { __mode = 'k' })

--- Правило записи целиком: вход `from`.
---@type table<TntDataShape<any>, TntValidateRule>
local ROOTS = setmetatable({}, { __mode = 'k' })

--- Правило списка записей: вход `collect`.
---@type table<TntDataShape<any>, TntValidateRule>
local LISTS = setmetatable({}, { __mode = 'k' })

--- Имя ключа отображения — строка: JSON других не знает, и аннотация
--- обещает `table<string, …>`. Из msgpack ключ приходит и числом —
--- такой вход отказ, а не словарь, который потом не закодировать в ответ.
local KEY = validate.string()

--- Как называется корень в пути отказа — тем же знаком, что у `tnt-validate`.
local ROOT = '$'

--- Правила по родам. Настройки у всех одним списком: чужих роду здесь
--- нет — их отсёк разбор поля, — а отсутствующие приходят пустыми.
---@type table<string, fun(opts: table): TntValidateRule>
local BUILDERS = {
    string = validate.string,
    integer = validate.integer,
    number = validate.number,
    boolean = validate.boolean,
    uuid = validate.uuid,
    email = validate.email,
    url = validate.url,
    date = validate.date,
    datetime = validate.datetime,
    any = validate.any,
    list = validate.list,
    map = validate.map,
    shape = validate.rule,
}

--- Правило `tnt-validate` для поля либо элемента.
---
--- Скрытое поле — ещё и тайна для отказа: его значение не уходит наружу
--- выдачей, и отказ, показывающий присланное, унёс бы его в ответ 422
--- и в журнал. Догадка `tnt-validate` по имени (`password`, `token`)
--- поле `pin` не узнала бы.
---@param field TntDataField
---@return TntValidateRule
function Module.rule_of(field)
    local opts = {
        optional = field.optional,
        default = field.default,
        secret = field.hidden or nil,
        min = field.min,
        max = field.max,
        pattern = field.pattern,
        one_of = field.one_of,
        schemes = field.schemes,
    }

    if field.kind == 'list' then
        opts.of = Module.rule_of(field.of --[[@as TntDataField]])
    elseif field.kind == 'map' then
        opts.keys = KEY
        opts.values = Module.rule_of(field.of --[[@as TntDataField]])
    elseif field.kind == 'shape' then
        local shape = field.shape --[[@as TntDataAnyShape]]

        opts.name = shape.name
        opts.check = RECORDS[shape]
    end

    return BUILDERS[field.kind](opts)
end

--- Отказы одной строкой: место и причина, по порядку мест.
---@param errors table<string, string>
---@return string
local function joined(errors)
    local parts = {}

    for _, path in ipairs(collection.keys(errors)) do
        local reason = errors[path]

        if path ~= ROOT then
            reason = ('%s %s'):format(path, reason)
        end

        table.insert(parts, reason)
    end

    return table.concat(parts, '; ')
end

--- Умолчание, проверенное правилом своего поля.
---
--- Отдаётся проверенное, а не написанное: у вложенной формы это запись
--- формы, у опознавателя — строка в нижнем регистре, то есть ровно то,
--- что дала бы проверка присланного значения. Умолчание-функцию проверить
--- заранее нечем — она зовётся на каждый вход, и её ответ идёт как есть.
---@param field TntDataField
---@return any default
---@return string|nil complaint
function Module.default_of(field)
    local default = field.default

    if default == nil or type(default) == 'function' then
        return default
    end

    local bare = table.copy(field) --[[@as TntDataField]]

    bare.default = nil

    local value, errors = validate.check(default, Module.rule_of(bare))

    if errors ~= nil then
        return nil, joined(errors)
    end

    return value
end

--- Собирает вход формы: проверку записи и правила `from` и `collect`.
---
--- Запись — новая таблица с именами Lua и метатаблицей формы: имя снаружи
--- (`as`) остаётся во входе и в пути отказа, а в коде поле зовётся своим
--- именем. Недостающее поле остаётся пустым — отказ о нём уже накоплен,
--- и запись всё равно не дойдёт до вызывающего.
---@param shape TntDataShape<any>
---@param meta table Метатаблица записей формы
function Module.record(shape, meta)
    local fields = {}

    for _, field in ipairs(shape.fields) do
        fields[field.key] = Module.rule_of(field)
    end

    local whole = validate.table({ fields = fields, unknown = shape.unknown })

    local function check(value, node)
        local ready, reason = whole.check(value, node)

        if reason ~= nil then
            return nil, reason
        end

        local record = {}

        for _, field in ipairs(shape.fields) do
            record[field.name] = ready[field.key]
        end

        return setmetatable(record, meta)
    end

    RECORDS[shape] = check
    ROOTS[shape] = validate.rule({ name = shape.name, check = check })
    LISTS[shape] = validate.list({ of = ROOTS[shape] })
end

--- Запись по форме либо отказы «место → причина».
---@param shape TntDataShape<any>
---@param input any
---@param opts table|nil
---@return table|nil record
---@return table<string, string>|nil errors
function Module.from(shape, input, opts)
    return validate.check(input, ROOTS[shape], opts)
end

--- Список записей по форме либо отказы «место → причина».
---@param shape TntDataShape<any>
---@param input any
---@param opts table|nil
---@return table[]|nil records
---@return table<string, string>|nil errors
function Module.collect(shape, input, opts)
    return validate.check(input, LISTS[shape], opts)
end

return Module
