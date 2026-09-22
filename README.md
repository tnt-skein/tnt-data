# tnt-data

Объект переноса данных для Tarantool: форма объявляется один раз списком
полей, и из объявления следуют проверка входа с приведением типов, выдача
без скрытых и необъявленных полей, аннотация EmmyLua и схема OpenAPI 3.0.
Две сверки держат аннотацию в модуле и схемы документа API в согласии
с объявлением.

```lua
local data = require('tnt.data')

---@class User
---@field id integer
---@field name string
---@field role "admin"|"viewer"
---@field password string

---@type TntDataShape<User>
local User = data.define({
    name = 'User',
    fields = {
        { 'id', 'integer', min = 1 },
        { 'name', 'string', min = 1, max = 64 },
        { 'role', 'string', one_of = { 'admin', 'viewer' }, default = 'viewer' },
        { 'password', 'string', min = 12, hidden = true },
    },
})

local user, errors = User.from(request.body)     -- запись либо nil, «место → причина»
json.encode(user)                                -- выдача: без скрытого пароля
User.annotation()                                -- класс выше, текстом
User.schema()                                    -- схема OpenAPI 3.0
```

```lua
errors.id        --> 'должно быть целым числом не меньше 1, а не 0'
errors.password  --> 'обязательное поле'
errors.extra     --> 'неизвестное поле'
```

Зависимости — [tnt-validate](https://github.com/tnt-skein/tnt-validate)
(проверка), [tnt-collection](https://github.com/tnt-skein/tnt-collection)
(вид таблицы в JSON, порядок ключей)
и [tnt-must](https://github.com/tnt-skein/tnt-must) (тексты отказов).

## Зачем

Форма одних и тех же данных описывается трижды — схемой проверки,
аннотацией `---@class` и описанием API — и три описания расходятся
молча: каждое проверяется само с собой. Пакет делает объявление
единственным источником:

- **Вход.** Проверяют правила `tnt-validate` с тем же видом отказа:
  все отказы сразу, путь до места — `items[2].price`, имя снаружи (`as`)
  в пути, имя Lua в записи. Приведение типов — только по просьбе.
- **Выдача.** Только объявленные поля, без скрытых, под именами снаружи;
  `uuid` и `datetime` — записью RFC 3339. Запись кодируется выдачей сама:
  `json.encode`, `msgpack.encode`, ответ по net.box.
- **Аннотация и схема** — из того же объявления, и сверки `data.annotated`
  и `data.described` называют первое расхождение путём.
- **Ошибка в объявлении — при загрузке модуля.** Настройка чужого рода,
  негодный род, умолчание, которое не проходит своё правило, —
  исключение со строкой того, кто объявлял форму.

## Установка

```sh
tt rocks install tnt-data --server=https://tnt-skein.github.io/rocks
```

Или из исходников:

```sh
git clone https://github.com/tnt-skein/tnt-data.git
cd tnt-data && tt rocks make
```

## Как пользоваться

| Вызов | Что делает |
|---|---|
| `data.define(spec)` | объявляет форму: `name`, `fields`, `about`, `unknown` |
| `Shape.from(input, opts)` | запись либо `nil, errors`; `opts.coerce` — приведение строк |
| `Shape.collect(input, opts)` | список записей либо `nil, errors` с местами `[2].name` |
| `Shape.to_table(value)` | выдача: объявленные видимые поля именами снаружи |
| `Shape.annotation()` | аннотация EmmyLua записи текстом |
| `Shape.schema()` | схема OpenAPI 3.0 записи |
| `data.components(shapes)` | схемы форм и всех вложенных — для `components.schemas` |
| `data.annotated(source, shapes)` | `true` либо `nil` и первое расхождение аннотации в тексте модуля |
| `data.described(schemas, shapes)` | `true` либо `nil` и первое расхождение схем документа API |
| `data.is(value)` | форма ли это — значение `data.define` |

Роды полей: `string`, `integer`, `number`, `boolean`, `uuid`, `email`,
`url`, `date`, `datetime`, `any`, `list`, `map` и другая форма — вложенный
объект. Элемент списка и значение отображения — `of`: `of = 'string'`,
`of = Address`, `of = { 'string', max = 32 }`. Настройки поля: `optional`,
`default`, `about`, `as`, `hidden` и свои у рода — `min`, `max`, `pattern`,
`one_of`, `schemes`.

### Сверки в проверках модуля

```lua
local source = io.open('app/data/user.lua'):read('*a')
local document = yaml.decode(io.open('api/openapi.yaml'):read('*a'))

t.assert_equals({ data.annotated(source, { User, Address }) }, { true })
t.assert_equals({ data.described(document.components.schemas, { User }) }, { true })
```

```
аннотация Address расходится с объявлением: ждали «---@field city string», а стоит «---@field city integer»
описание расходится с объявлением: User.required[3] — в описании «nick», в объявлении «password»
```

## Проверки

```sh
make deps          # luatest, luacheck, luacov с cluacov и tnt-must, tnt-collection, tnt-validate в .rocks
make check         # форматирование, линт, проверки, покрытие с порогом 100 %
make mutants-all   # мутационное тестирование утилитой tnt-mutants из PATH, порог 100 % убитых
```

Покрытие строк — 100 %, убитых мутантов — 100 % (60 проверок, 304 мутанта
в семи модулях). Отказы, аннотации и схемы сверяются текстом целиком;
значения Tarantool в выдаче — `uuid`, `datetime` — настоящие, кодирование
записи проверяется настоящими `json`, `msgpack` и `yaml`.

## Документ

Полное описание с обоснованием решений: [docs/data.md](docs/data.md).

## Лицензия

MIT.
