--- Поле формы: запись в объявлении, проверенная при загрузке.
---
--- Запись поля — список: имя, род и настройки, `{ 'name', 'string', max = 64 }`.
--- Список, а не словарь полей, потому что порядок полей виден снаружи:
--- им идут строки аннотации, свойства и обязательные поля в описании API,
--- и у словаря Lua этого порядка нет — описание переставлялось бы от
--- запуска к запуску, и сверка с документом не сходилась бы никогда.
---
--- Род — имя (`'string'`, `'list'`) либо другая форма `data.define`:
--- вложенный объект. Элемент списка и значение отображения описываются
--- настройкой `of` той же записью, только без имени: `of = 'string'`,
--- `of = Address` либо `of = { 'string', max = 32 }`.
---
--- Настройки проверяются по роду: `max` у логического значения — не
--- умолчание, а опечатка в объявлении, и узнать о ней лучше при загрузке
--- модуля, чем по данным, которые проскочили проверку. Отказ здесь —
--- текст: бросает его фасад, один раз и строкой того, кто объявлял форму.

local explain = require('tnt.must').explain
local show = require('tnt.must.fail').show

local Module = {}

--- Формы, объявленные `data.define`: по этому набору род-форма отличается
--- от записи элемента. Ключи слабые — забытая форма не держится в памяти.
---@type table<table, boolean>
Module.SHAPES = setmetatable({}, { __mode = 'k' })

--- Имя поля — идентификатор Lua: поле зовут `record.name`, и то же имя
--- стоит в строке `---@field` аннотации.
local NAME = '^[%a_][%w_]*$'

--- Описание поля — одна строка: оно встаёт в хвост строки `---@field`,
--- и перевод строки разорвал бы аннотацию.
local ONE_LINE = '^[^\n]*$'

--- Список строк: так пишут `one_of` и `schemes`.
local STRINGS = { '?array_of', 'string' }

--- Границы: длина строки, число, размер списка.
local BOUNDS = { min = '?number', max = '?number' }

--- Настройки по родам. Род без своих настроек — пустая таблица.
---@type table<string, table>
local BY_KIND = {
    string = { min = '?number', max = '?number', pattern = '?string', one_of = STRINGS },
    integer = BOUNDS,
    number = BOUNDS,
    boolean = {},
    uuid = {},
    email = {},
    url = { max = '?integer', schemes = STRINGS },
    date = {},
    datetime = {},
    any = {},
    list = { of = 'string|table', min = '?integer', max = '?integer' },
    map = { of = 'string|table' },
    shape = {},
}

--- Предел длины ссылки и её схемы, когда их не назвали, — те же, что
--- у правила ссылки `tnt-validate`.
---
--- Свои, а не взятые у правила: правило их наружу не отдаёт, а описанию
--- API они нужны. Поле получает их явно и отдаёт правилу явно — так
--- описание и проверка не разойдутся, даже если умолчания правила
--- однажды поменяют.
Module.URL_LIMIT = 2048
Module.URL_SCHEMES = { 'http', 'https' }

--- Роды по порядку — им же они перечисляются в отказе об опечатке.
Module.KINDS = {
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
}

--- Настройки, которые понимает поле с именем. У элемента списка их нет:
--- он не бывает ни необязательным, ни скрытым, а имени снаружи у него нет.
local COMMON = {
    optional = '?boolean',
    default = '?',
    about = { '?matches', ONE_LINE },
    as = '?not_empty',
    hidden = '?boolean',
}

--- Описание настроек поля с именем: общие плюс свои для рода.
---@type table<string, table>
local NAMED = {}

for kind, own in pairs(BY_KIND) do
    NAMED[kind] = table.copy(COMMON)

    for key, check in pairs(own) do
        NAMED[kind][key] = check
    end
end

---@class TntDataField
---@field name string|nil Имя в Lua; у элемента списка его нет
---@field key string|nil Имя снаружи: во входе, в выдаче, в описании API
---@field kind string Род: string, integer, …, list, map либо shape
---@field shape TntDataShape<any>|nil Вложенная форма, если род — форма
---@field of TntDataField|nil Элемент списка либо значение отображения
---@field optional boolean Можно ли не присылать
---@field default any Чем заменить отсутствие; функция зовётся на каждое
---@field about string|nil Что это за поле — для аннотации и описания API
---@field hidden boolean Не отдаётся в выдаче
---@field min number|nil
---@field max number|nil
---@field pattern string|nil Образец Lua
---@field one_of string[]|nil
---@field schemes string[]|nil

--- Разбирает запись по месту рода в ней.
---@param entry table Запись поля либо элемента
---@param position integer Где в записи стоит род: 2 у поля, 1 у элемента
---@param place string Как назвать это место в отказе
---@param specs table<string, table> Описания настроек по родам
---@return TntDataField|nil field
---@return string|nil complaint
local function parse(entry, position, place, specs)
    local kind = entry[position]
    local shape = nil

    if Module.SHAPES[kind] then
        shape = kind
        kind = 'shape'
    end

    local spec = specs[kind]

    if spec == nil then
        return nil,
            ('%s: рода %s нет, бывают %s и форма data.define'):format(
                place,
                show(kind),
                table.concat(Module.KINDS, ', ')
            )
    end

    local options = {}

    for key, value in pairs(entry) do
        if key ~= 1 and key ~= position then
            options[key] = value
        end
    end

    local complaint = explain.options(options, place, spec)

    if complaint ~= nil then
        return nil, complaint
    end

    local field = {
        kind = kind,
        shape = shape,
        optional = options.optional == true,
        default = options.default,
        about = options.about,
        hidden = options.hidden == true,
        min = options.min,
        max = options.max,
        pattern = options.pattern,
        one_of = options.one_of,
        schemes = options.schemes,
    }

    if kind == 'url' then
        field.max = field.max or Module.URL_LIMIT
        field.schemes = field.schemes or Module.URL_SCHEMES
    end

    if options.of ~= nil then
        local item, wrong = Module.item(options.of, place .. ', элемент')

        if item == nil then
            return nil, wrong
        end

        field.of = item
    end

    return field
end

--- Элемент списка либо значение отображения: запись без имени.
---
--- Короткая запись — одно имя рода или форма: `of = 'string'`.
---@param entry any
---@param place string
---@return TntDataField|nil field
---@return string|nil complaint
function Module.item(entry, place)
    local full = entry

    if type(entry) ~= 'table' or Module.SHAPES[entry] then
        full = { entry }
    end

    return parse(full, 1, place, BY_KIND)
end

--- Поле формы: запись с именем.
---@param entry any
---@param place string Как назвать форму в отказе: «форма User»
---@param number integer Место записи в списке полей
---@return TntDataField|nil field
---@return string|nil complaint
function Module.named(entry, place, number)
    local complaint = explain.kind(entry, ('%s, поле №%d'):format(place, number), 'table')

    if complaint ~= nil then
        return nil, complaint
    end

    local name = entry[1]

    if type(name) ~= 'string' or not name:match(NAME) then
        return nil,
            ('%s, поле №%d: первым стоит имя — идентификатор Lua, а не %s'):format(
                place,
                number,
                show(name)
            )
    end

    local field, wrong = parse(entry, 2, ('%s, поле %s'):format(place, name), NAMED)

    if field == nil then
        return nil, wrong
    end

    field.name = name
    field.key = entry.as or name

    return field
end

return Module
