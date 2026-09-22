rockspec_format = '3.0'

package = 'tnt-data'
version = 'scm-1'

source = {
    url = 'git+https://github.com/tnt-skein/tnt-data.git',
    branch = 'main',
}

description = {
    summary = 'Объект переноса данных: форма один раз — проверка входа, выдача, аннотация, схема OpenAPI',
    detailed = [[
        Форма данных объявляется один раз списком полей, и из объявления
        следуют проверка входа с приведением типов (правилами
        tnt-validate), выдача без скрытых и необъявленных полей, аннотация
        EmmyLua и схема OpenAPI 3.0.

        Три описания одной формы — проверка, аннотация `---@class`
        и описание API — больше не расходятся молча: сверки
        data.annotated и data.described сличают аннотацию в модуле
        и схемы документа с объявлением и называют первое расхождение.

        Отказ входа — пара nil, errors с местом и причиной, как у
        tnt-validate; ошибка в объявлении — исключение при загрузке
        модуля, со строкой того, кто объявлял форму. Умолчание поля
        проверяется его же правилом при объявлении, запись кодируется
        в JSON и msgpack своей выдачей — без скрытых полей.

        Зависимости — tnt-validate (проверка), tnt-collection (вид
        таблицы в JSON, порядок ключей) и tnt-must (тексты отказов).
        Покрытие строк и убитых мутантов — 100 %.
    ]],
    homepage = 'https://github.com/tnt-skein/tnt-data',
    issues_url = 'https://github.com/tnt-skein/tnt-data/issues',
    maintainer = 'tnt-skein',
    license = 'MIT',
    labels = { 'tarantool', 'dto', 'validation', 'openapi', 'emmylua' },
}

dependencies = {
    'lua >= 5.1',
    'tnt-must',
    'tnt-collection',
    'tnt-validate',
}

build = {
    type = 'builtin',
    modules = {
        ['tnt.data'] = 'tnt/data.lua',
        ['tnt.data.annotation'] = 'tnt/data/annotation.lua',
        ['tnt.data.field'] = 'tnt/data/field.lua',
        ['tnt.data.openapi'] = 'tnt/data/openapi.lua',
        ['tnt.data.output'] = 'tnt/data/output.lua',
        ['tnt.data.rules'] = 'tnt/data/rules.lua',
        ['tnt.data.shape'] = 'tnt/data/shape.lua',
    },
}
