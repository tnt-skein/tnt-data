--- Аннотация EmmyLua по форме и сверка её с текстом модуля.
---
--- Аннотацию нельзя получить из объявления на лету: анализатор типов
--- читает исходники и кода не исполняет. Поэтому она лежит в модуле
--- текстом, а согласие с объявлением держит сверка: проверка модуля зовёт
--- `data.annotated(исходник, { Форма })`, и поле, дописанное в объявление
--- и забытое в аннотации, роняет проверку, а не всплывает через полгода
--- «неизвестным полем» у того, кто поверил аннотации.
---
--- Сверяются строка `---@class` и идущие за ней подряд строки `---@field`:
--- их вид выводится из объявления целиком. Описание над классом — текст
--- для человека, и его сверка не трогает.
---
--- Роды: строковые (`uuid`, `email`, `url`, `date`, `datetime`) — `string`,
--- перечень строк — объединение буквальных строк `"admin"|"viewer"`,
--- список — `T[]`, отображение — `table<string, T>`, вложенная форма —
--- её имя. Необязательное поле без умолчания — `T|nil`: в записи его может
--- не быть, а поле с умолчанием есть всегда.

local Module = {}

--- Роды Lua для простых родов поля.
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
    any = 'any',
}

--- Начало строки поля в аннотации.
local FIELD = '---@field '

--- Знаки, которые в буквальной строке аннотации не записать: кавычка
--- закрыла бы строку, а обратная косая черта и перевод строки
--- анализатором не разбираются.
local UNQUOTABLE = '["\\\n]'

--- Перечень строк объединением буквальных строк; nil, если хоть одну
--- из них так не записать.
---@param values string[]
---@return string|nil
local function literals(values)
    local parts = {}

    for index, value in ipairs(values) do
        if value:find(UNQUOTABLE) ~= nil then
            return nil
        end

        parts[index] = ('"%s"'):format(value)
    end

    return table.concat(parts, '|')
end

--- Род поля в записи аннотации.
---@param field TntDataField
---@return string
local function type_of(field)
    if field.kind == 'shape' then
        return (field.shape --[[@as TntDataAnyShape]]).name
    end

    if field.kind == 'list' then
        local item = type_of(field.of --[[@as TntDataField]])

        -- Без скобок `"a"|"b"[]` читается как «"a" либо список "b"».
        -- Черта в образцах Lua — обычный знак, и поиск идёт без аргументов:
        -- у `find(…, 1, true)` мутанты `0`, `2` и `false` неотличимы — черта
        -- не бывает первым знаком записи рода, а особым знаком не бывает вовсе.
        if item:find('|') ~= nil then
            item = ('(%s)'):format(item)
        end

        return item .. '[]'
    end

    if field.kind == 'map' then
        return ('table<string, %s>'):format(type_of(field.of --[[@as TntDataField]]))
    end

    if field.one_of ~= nil then
        return literals(field.one_of) or TYPES.string
    end

    return TYPES[field.kind]
end

--- Строки аннотации, которые сверяются: класс и его поля.
---@param shape TntDataShape<any>
---@return string[]
function Module.lines(shape)
    local lines = { '---@class ' .. shape.name }

    for _, field in ipairs(shape.fields) do
        local line = FIELD .. field.name .. ' ' .. type_of(field)

        if field.optional and field.default == nil then
            line = line .. '|nil'
        end

        if field.about ~= nil then
            line = line .. ' ' .. field.about
        end

        table.insert(lines, line)
    end

    return lines
end

--- Аннотация целиком: описание формы над классом, затем класс и поля.
---@param shape TntDataShape<any>
---@return string
function Module.text(shape)
    local lines = {}

    if shape.about ~= nil then
        for line in (shape.about .. '\n'):gmatch('([^\n]*)\n') do
            -- Пустая строка описания — голые три черты: пробел на конце
            -- строки снял бы форматировщик, и вставленная аннотация
            -- разошлась бы с выданной.
            table.insert(lines, line == '' and '---' or '--- ' .. line)
        end
    end

    for _, line in ipairs(Module.lines(shape)) do
        table.insert(lines, line)
    end

    return table.concat(lines, '\n') .. '\n'
end

--- Строки текста без пробелов по краям: аннотацию сдвигают отступом
--- вместе с кодом, и это не расхождение.
---@param source string
---@return string[]
local function trimmed(source)
    local lines = {}

    for line in (source .. '\n'):gmatch('([^\n]*)\n') do
        table.insert(lines, line:match('^%s*(.-)%s*$'))
    end

    return lines
end

--- Строки аннотации в тексте: класс и поля подряд за ним.
---@param lines string[]
---@param class string Строка класса
---@return string[]|nil
local function found_in(lines, class)
    for index, line in ipairs(lines) do
        if line == class then
            local found = { line }

            for next_index = index + 1, #lines do
                local next_line = lines[next_index]

                -- Начало строки — срезом от `-#next_line`, а не от единицы:
                -- у `sub(1, n)` мутант `sub(0, n)` даёт ту же строку.
                if next_line:sub(-#next_line, #FIELD) ~= FIELD then
                    break
                end

                table.insert(found, next_line)
            end

            return found
        end
    end

    return nil
end

--- Расхождение аннотации в тексте с объявлением; nil — сходится.
---
--- Называется первая несошедшаяся строка: чинят по одной, а список
--- из двадцати расхождений после переименования одного поля только
--- прятал бы, с чего начать.
---@param source string Текст модуля
---@param shape TntDataShape<any>
---@return string|nil complaint
function Module.drift(source, shape)
    local expected = Module.lines(shape)
    local found = found_in(trimmed(source), expected[1] --[[@as string]])

    if found == nil then
        return ('аннотации %s в тексте нет'):format(expected[1])
    end

    local head = ('аннотация %s расходится с объявлением'):format(shape.name)

    -- Строка класса совпала при поиске, и сравнивать её снова незачем, но
    -- обход идёт с неё: у счёта с двойки мутант `1` неотличим — он лишь
    -- сравнил бы совпавшую строку ещё раз.
    for index, want in ipairs(expected) do
        local have = found[index]

        if have == nil then
            return ('%s: не хватает строки «%s»'):format(head, want)
        end

        if want ~= have then
            return ('%s: ждали «%s», а стоит «%s»'):format(head, want, have)
        end
    end

    local extra = found[#expected + 1]

    if extra ~= nil then
        return ('%s: лишняя строка «%s»'):format(head, extra)
    end

    return nil
end

return Module
