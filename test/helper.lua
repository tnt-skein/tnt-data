--- Общие средства проверок форм данных.
---
--- Отказы и тексты сравниваются целиком и дословно: текст отказа,
--- аннотация и схема и есть то, ради чего пакет написан, и «где-то там
--- сказано про поле» их не проверяет.
---
--- Исходники грузятся с диска, а не через `require`: у Tarantool свой
--- загрузчик `.rocks`, он идёт раньше `package.path` и подсунул бы
--- установленную копию пакета, если она есть. Проверки тогда шли бы
--- против вчерашнего кода, а покрытие считалось бы по нему. Поэтому
--- файлы читаются сами, в порядке зависимостей, и кладутся
--- в `package.loaded` под именами модулей: `require` изнутри пакета
--- находит их первыми. Зависимости `tnt-must`, `tnt-collection`
--- и `tnt-validate` стоят в `.rocks`, и их модули пакет берёт обычным
--- `require`.

local fio = require('fio')

local helper = {}

--- Модули пакета в порядке зависимостей.
helper.MODULES = {
    { name = 'tnt.data.field', path = 'tnt/data/field.lua' },
    { name = 'tnt.data.rules', path = 'tnt/data/rules.lua' },
    { name = 'tnt.data.output', path = 'tnt/data/output.lua' },
    { name = 'tnt.data.annotation', path = 'tnt/data/annotation.lua' },
    { name = 'tnt.data.openapi', path = 'tnt/data/openapi.lua' },
    { name = 'tnt.data.shape', path = 'tnt/data/shape.lua' },
    { name = 'tnt.data', path = 'tnt/data.lua' },
}

--- Части пакета: имя модуля → его таблица.
---
--- Собираются при загрузке этого помощника, то есть по разу на каждый файл
--- проверок, который его берёт, — а не перед каждой проверкой: своего
--- состояния у пакета нет, а формы, объявленные одной проверкой, другой
--- не мешают.
---@type table<string, any>
local PARTS = {}

for _, module in ipairs(helper.MODULES) do
    local chunk, failure = loadfile(fio.abspath(module.path))

    if chunk == nil then
        error(('исходник %s не читается: %s'):format(module.name, tostring(failure)))
    end

    local value = chunk()

    -- Пустое значение в `package.loaded` для `require` значит «не загружен»,
    -- и следующий модуль списка молча взял бы зависимость из `.rocks`.
    if value == nil then
        error(('исходник %s не вернул модуль'):format(module.name))
    end

    package.loaded[module.name] = value
    PARTS[module.name] = value
end

--- Фасад пакета, собранный из исходников.
helper.data = PARTS['tnt.data']

--- Отдельный модуль пакета из той же загрузки.
---@param name string
---@return any
function helper.part(name)
    local part = PARTS[name]

    if part == nil then
        error(('модуль %s не из пакета tnt-data'):format(name))
    end

    return part
end

--- Негодный аргумент — нарочно.
---
--- Проверки отказов передают то, чего договор не допускает. Анализатор
--- типов о таком намерении знать не может и справедливо ругается
--- на каждую такую строку.
---@param value any
---@return any
function helper.wrong(value)
    return value
end

--- Номер строки, с которой позвали эту функцию: так проверки узнают
--- строку, на которую обязан указать отказ.
---@return integer
function helper.here()
    return (debug.getinfo(2, 'l') --[[@as { currentline: integer }]]).currentline
end

--- Объявляет формы группы перед её проверками.
---
--- Не при загрузке файла: мутант, сломавший объявление, иначе ронял бы
--- загрузку, и гейт мутаций не отличил бы его от проверок, которые
--- не запустились вовсе.
---@param g table Группа luatest
---@param declare fun()
function helper.declare(g, declare)
    g.before_all(declare)
end

--- Текст исключения, брошенного вызовом.
---@param call function
---@return string
function helper.thrown(call)
    local ok, err = pcall(call)

    assert(not ok, 'вызов не бросил исключения')

    return tostring(err)
end

--- Текст отказа объявления без места впереди.
---
--- `pcall` зовёт `define` сам, и `error(msg, 2)` упирается в его кадр C:
--- места в сообщении нет. Что место есть при вызове из кода на Lua,
--- проверяется отдельно и нарочно.
---@param spec any
---@return string
function helper.refusal(spec)
    local message = helper.thrown(function()
        helper.data.define(spec)
    end)

    return (message:gsub('^[^:]+:%d+: ', ''))
end

--- Форма из одного поля: так проверяют род и его настройки.
---@param entry table Запись поля
---@return TntDataShape<table>
function helper.single(entry)
    return helper.data.define({ name = 'Single', fields = { entry } })
end

return helper
