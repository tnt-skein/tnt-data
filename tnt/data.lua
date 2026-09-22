--- Объект переноса данных: форма объявляется один раз.
---
--- Форма одних и тех же данных описывалась трижды — схемой проверки
--- `tnt-validate`, аннотацией `---@class` и описанием API, — и три описания
--- расходились молча: проверка пропускала поле, которого нет в аннотации, а
--- в описании API оно значилось обязательным. Здесь объявление одно, и из
--- него следуют проверка входа с приведением типов, выдача, аннотация и
--- схема описания API:
---
---     local data = require('tnt.data')
---
---     ---@class User
---     ---@field id integer
---     ---@field name string Имя, как его видят в панели
---     ---@field role "admin"|"viewer"
---     ---@field password string
---     ---@field tags string[]
---
---     ---@type TntDataShape<User>
---     local User = data.define({
---         name = 'User',
---         fields = {
---             { 'id', 'integer', min = 1 },
---             { 'name', 'string', min = 1, max = 64, about = 'Имя, как его видят в панели' },
---             { 'role', 'string', one_of = { 'admin', 'viewer' }, default = 'viewer' },
---             { 'password', 'string', min = 12, hidden = true },
---             { 'tags', 'list', of = 'string', default = {} },
---         },
---     })
---
---     local user, errors = User.from(request.body)     -- запись либо «место → причина»
---     local page = User.from(request.query, { coerce = true })
---     json.encode(user)                                 -- без скрытого пароля
---     User.annotation()                                 -- класс выше, текстом
---     User.schema()                                     -- схема OpenAPI 3.0
---
--- Согласие держат две сверки, и обе отвечают парой: `true` либо `nil`
--- и первое расхождение. `data.annotated(исходник, { User })` сличает
--- аннотацию в модуле с объявлением, `data.described(схемы, { User })` —
--- схемы `components.schemas` документа API. Их ставят в проверки того,
--- кто объявил форму: поле, дописанное в объявление и забытое в аннотации
--- или в документе, роняет проверку.
---
--- Отказ входа — пара `nil, errors`, как у `tnt-validate`, с тем же видом
--- мест и причин. Исключение — ошибка программиста: негодное объявление,
--- негодный аргумент, выдача, которую не собрать из того, что дал код.
--- Отказ указывает на строку вызывающего.
---
--- Настроек и состояния у пакета нет — ни `configure`, ни `new`,
--- ни `default`, ни `status`: форма — значение, собранное объявлением,
--- а внешних средств пакет не берёт. Подробно — `docs/data.md`.

local explain = require('tnt.must').explain
local show = require('tnt.must.fail').show

local collection = require('tnt.collection')

local annotation = require('tnt.data.annotation')
local field = require('tnt.data.field')
local openapi = require('tnt.data.openapi')
local shape = require('tnt.data.shape')

local Module = {}

--- Роды полей по имени; сверх них родом служит другая форма.
Module.KINDS = field.KINDS

--- Отказ о списке форм; nil — список годный.
---@param shapes any
---@return string|nil
local function refused_shapes(shapes)
    local complaint = explain.kind(shapes, 'формы', 'array')

    if complaint ~= nil then
        return complaint
    end

    for index, item in ipairs(shapes) do
        if not field.SHAPES[item] then
            return ('формы[%d] — форма data.define, а не %s'):format(index, show(item))
        end
    end

    return nil
end

--- Форма ли это — значение, собранное `data.define`.
---
--- Нужно тому, кто принимает форму аргументом и строит на ней своё —
--- например, белый список полей запроса по её полям: таблица с теми же
--- ключами формой не станет, и узнать об этом лучше при объявлении.
---@param value any
---@return boolean
function Module.is(value)
    return field.SHAPES[value] == true
end

--- Объявляет форму данных.
---@param spec table name, fields, about, unknown
---@return TntDataShape<any>
function Module.define(spec)
    local made, complaint = shape.define(spec)

    if made == nil then
        error(complaint, 2)
    end

    return made
end

--- Схемы форм по именам либо отказ о списке форм.
---@param shapes any
---@return table<string, table>|nil schemas
---@return string|nil complaint
local function schemas_of(shapes)
    local complaint = refused_shapes(shapes)
    local found

    if complaint == nil then
        found, complaint = openapi.collect(shapes)
    end

    if found == nil then
        return nil, complaint
    end

    local schemas = {}

    for name, item in pairs(found) do
        schemas[name] = item.schema()
    end

    return schemas
end

--- Схемы форм для `components.schemas` документа OpenAPI: названные
--- и все вложенные, по именам.
---@param shapes TntDataShape<any>[]
---@return table<string, table>
function Module.components(shapes)
    local schemas, complaint = schemas_of(shapes)

    if schemas == nil then
        error(complaint, 2)
    end

    return schemas
end

--- Сходится ли аннотация в тексте модуля с объявлением форм.
---@param source string Текст модуля
---@param shapes TntDataShape<any>[]
---@return true|nil ok
---@return string|nil err Первое расхождение
function Module.annotated(source, shapes)
    local complaint = explain.kind(source, 'текст модуля', 'string') or refused_shapes(shapes)

    if complaint ~= nil then
        error(complaint, 2)
    end

    for _, item in ipairs(shapes) do
        local drift = annotation.drift(source, item)

        if drift ~= nil then
            return nil, drift
        end
    end

    return true
end

--- Сходятся ли схемы документа API с объявлением форм.
---
--- Сверяются схемы названных форм и всех вложенных; прочие схемы
--- документа — тела отказов, чужие формы — не трогаются.
---@param schemas table `components.schemas` документа
---@param shapes TntDataShape<any>[]
---@return true|nil ok
---@return string|nil err Первое расхождение
function Module.described(schemas, shapes)
    local complaint = explain.kind(schemas, 'схемы описания', 'table')
    local expected

    if complaint == nil then
        expected, complaint = schemas_of(shapes)
    end

    if expected == nil then
        error(complaint, 2)
    end

    for _, name in ipairs(collection.keys(expected)) do
        if schemas[name] == nil then
            return nil, ('в описании нет схемы %s'):format(name)
        end

        local drift = openapi.difference(expected[name], schemas[name], name)

        if drift ~= nil then
            return nil, ('описание расходится с объявлением: %s'):format(drift)
        end
    end

    return true
end

return Module
