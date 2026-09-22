--- Выдача по форме: таблица, готовая к JSON и msgpack.
---
--- Выдача отдаёт только объявленное. Поле, которого нет в форме, наружу
--- не уходит, даже если лежит в таблице: ответ, собранный из записи
--- хранилища, иначе унёс бы клиенту всё, что в записи было, — служебное
--- поле, хеш пароля, — и никто бы этого не заметил. Скрытое поле
--- (`hidden = true`) принимается на входе и не отдаётся на выходе:
--- пароль в форме входа есть, в ответе — нет.
---
--- Имена снаружи (`as`) — те же, что во входе: клиент получает поле под
--- тем же именем, под которым его прислал.
---
--- Значения Tarantool становятся записью: `uuid` — строкой, `datetime` —
--- записью RFC 3339 со смещением через двоеточие, дата — `ГГГГ-ММ-ДД`.
--- Встроенный JSON пишет смещение без двоеточия (`+0300`), а описание API
--- обещает `format: date-time`, то есть RFC 3339.
---
--- Пустой список уезжает `[]`, пустой объект и пустое отображение — `{}`:
--- без пометки встроенный JSON закодировал бы пустую таблицу списком
--- (`tnt-collection`, «Список или словарь»).
---
--- Выдача не проверяет значения: форму проверяют на входе, а выдачу
--- собирает код, и его ошибку ловят проверки. Проверяется только то,
--- без чего выдачу не собрать: вложенная форма — таблица, список —
--- список. Отказ — текст с местом: `User.address — таблица, а не строка`.

local datetime = require('datetime')
local uuid = require('uuid')

local collection = require('tnt.collection')
local explain = require('tnt.must').explain

local Module = {}

--- Смещение пояса без двоеточия в конце записи момента: так его пишет
--- `tostring` у `datetime`.
local OFFSET = '([+-]%d%d)(%d%d)$'

--- Момент записью RFC 3339.
---@param value any datetime
---@return string
local function moment(value)
    local text = tostring(value):gsub(OFFSET, '%1:%2')

    return text
end

--- Преобразования значений Tarantool по родам поля.
---
--- Значение другого рода идёт как есть: строку, уже проверенную на входе,
--- переписывать незачем.
---@type table<string, fun(value: any): any>
local TRANSFORMS = {
    uuid = function(value)
        if uuid.is_uuid(value) then
            return tostring(value)
        end

        return value
    end,
    datetime = function(value)
        if datetime.is_datetime(value) then
            return moment(value)
        end

        return value
    end,
    date = function(value)
        if datetime.is_datetime(value) then
            return value:format('%Y-%m-%d')
        end

        return value
    end,
}

--- Выдача списка.
---@param field TntDataField
---@param value any
---@param place string
---@return table|nil result
---@return string|nil complaint
local function list_of(field, value, place)
    local complaint = explain.kind(value, place, 'array')

    if complaint ~= nil then
        return nil, complaint
    end

    local result = {}

    for index, item in ipairs(value) do
        local ready, wrong = Module.value(field.of --[[@as TntDataField]], item, ('%s[%d]'):format(place, index))

        if wrong ~= nil then
            return nil, wrong
        end

        result[index] = ready
    end

    return collection.as_array(result)
end

--- Выдача отображения.
---@param field TntDataField
---@param value any
---@param place string
---@return table|nil result
---@return string|nil complaint
local function map_of(field, value, place)
    local complaint = explain.kind(value, place, 'table')

    if complaint ~= nil then
        return nil, complaint
    end

    local result = {}

    for key, item in pairs(value) do
        local ready, wrong =
            Module.value(field.of --[[@as TntDataField]], item, ('%s[%s]'):format(place, tostring(key)))

        if wrong ~= nil then
            return nil, wrong
        end

        result[key] = ready
    end

    return collection.as_map(result)
end

--- Выдача одного значения по его полю.
---@param field TntDataField
---@param value any Есть: пустое поле в выдачу не идёт вовсе
---@param place string Как назвать место в отказе
---@return any result
---@return string|nil complaint
function Module.value(field, value, place)
    if field.kind == 'shape' then
        return Module.record(field.shape --[[@as TntDataAnyShape]], value, place)
    end

    if field.kind == 'list' then
        return list_of(field, value, place)
    end

    if field.kind == 'map' then
        return map_of(field, value, place)
    end

    local transform = TRANSFORMS[field.kind]

    if transform ~= nil then
        return transform(value)
    end

    return value
end

--- Выдача записи формы.
---
--- Пустое поле — `nil` либо `box.NULL` — в выдачу не идёт: необязательное
--- поле описано необязательным, и `null` на его месте клиенту ничего
--- не добавит.
---@param shape TntDataShape<any>
---@param value any
---@param place string
---@return table|nil result
---@return string|nil complaint
function Module.record(shape, value, place)
    local complaint = explain.kind(value, place, 'table')

    if complaint ~= nil then
        return nil, complaint
    end

    local result = {}

    for _, field in ipairs(shape.fields) do
        local item = value[field.name]

        if item ~= nil and not field.hidden then
            local ready, wrong = Module.value(field, item, ('%s.%s'):format(place, field.name))

            if wrong ~= nil then
                return nil, wrong
            end

            result[field.key] = ready
        end
    end

    return collection.as_map(result)
end

return Module
