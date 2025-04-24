-- Базовый класс таблицы (используем предыдущий код с небольшими изменениями)
local Table = require("Table")

--- Управляющий класс базы данных
---@class Database
local Database = {}
Database.__index = Database

function Database:new(path)
    local obj = setmetatable({}, self)
    obj.Logger = require("libs.logger") -- Инициализация логгера
    obj.Logger:setPrefix("Database")

    obj.tables = {} -- Хранилище таблиц
    obj.path = path or "data"
    obj.transactions = {} -- Стек транзакций
    obj.indexes = {} -- Общий индекс для базы

    self.transactions = {}
    self.current_transaction = nil
    self.locks = {} -- Механизм блокировок

    return obj
end

--- Начало новой транзакции
function Database:begin_transaction()
    local new_tx = {
        id = tostring(os.time()),
        started_at = os.time(),
        changes = {},
        locks = {}
    }

    -- Сохраняем текущее состояние всех таблиц
    for name, table in pairs(self.tables) do
        new_tx.changes[name] = {
            data = self:deep_copy(table.data),
            hash = self:deep_copy(table.hash)
        }
    end

    table.insert(self.transactions, new_tx)
    self.current_transaction = new_tx
end

--- Фиксация транзакции
function Database:commit()
    local tx = self.current_transaction
    if not tx then return end

    -- Применяем изменения к основным данным
    for table_name, state in pairs(tx.changes) do
        local table_instance = self.tables[table_name]
        table_instance.data = self:deep_copy(state.data)
        table_instance.hash = self:deep_copy(state.hash)
        table_instance:save_data()
        table_instance:save_hash()
    end

    -- Очищаем транзакцию
    table.remove(self.transactions)
    self.current_transaction = self.transactions[#self.transactions]
end

--- Откат транзакции
function Database:rollback()
    local tx = self.current_transaction
    if not tx then return end

    -- Восстанавливаем исходное состояние
    for table_name, state in pairs(tx.changes) do
        local table_instance = self.tables[table_name]
        table_instance.data = self:deep_copy(state.data)
        table_instance.hash = self:deep_copy(state.hash)
    end

    table.remove(self.transactions)
    self.current_transaction = self.transactions[#self.transactions]
end

--- Уровень изоляции REPEATABLE READ
function Database:acquire_lock(table_name, record_id)
    local tx = self.current_transaction
    if not tx then return end

    tx.locks[table_name] = tx.locks[table_name] or {}
    tx.locks[table_name][record_id] = true
end

--- Реализация deep_copy для таблиц
function Database:deep_copy(obj)
    if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do
        res[k] = self:deep_copy(v)
    end
    return res
end

--- Метод вставки с транзакцией
function Table:insert(record)
    local tx = self.database.current_transaction
    if tx then
        local tx_state = tx.changes[self.filename]
        tx_state.data[record[self.key_field]] = record
    else
        self.data[record[self.key_field]] = record
        self.hash[record[self.key_field]] = true
        self:save_data()
        self:save_hash()
    end
end

--- Метод обновления с транзакцией
function Table:update(condition, updates)
    local tx = self.database.current_transaction
    if tx then
        local tx_state = tx.changes[self.filename]
        for key, record in pairs(tx_state.data) do
            if self:record_matches(record, condition) then
                for field, value in pairs(updates) do
                    record[field] = value
                end
            end
        end
    else
        -- Обычное обновление
        -- ... предыдущая реализация ...
    end
end

--- Проверка совпадения записи
function Table:record_matches(record, condition)
    for field, value in pairs(condition) do
        if record[field] ~= value then return false end
    end
    return true
end


--- Создание новой таблицы
---@param name string Название таблицы
---@param template table Схема данных
---@param key_field string Первичный ключ (по умолчанию "id")
---@return Table Новый экземпляр таблицы
function Database:create_table(name, template, key_field)
    local table_instance = Table:new(self.path, name, template, key_field)
    self.tables[name] = table_instance
    return table_instance
end

--- Добавление метода синхронизации в Database
function Database:sync(target_db, source_table, target_table, options)
    options = options or {}

    -- Проверка существования таблиц
    local source = self:get_table(source_table)
    local target = target_db:get_table(target_table)

    if not source or not target then
        error("Source or target table doesn't exist")
    end

    -- Разбор параметров
    local source_key = options.from_key or "id"
    local target_key = options.to_key or "id"
    local fields_map = options.fields or {}

    -- Выборка данных из источника
    local source_data = source.data
    for _, row in pairs(source_data) do
        -- Создаем/обновляем запись в целевой таблице
        local target_row = {}
        for src_field, tgt_field in pairs(fields_map) do
            target_row[tgt_field] = row[src_field]
        end

        -- Установка ключа для связи
        target_row[target_key] = row[source_key]

        -- Проверяем существование записи
        if target.data[target_row[target_key]] then
            -- Обновление существующей записи
            target:update({
                [target_key] = target_row[target_key]
            }, target_row)
        else
            -- Вставка новой записи
            target:insert(target_row)
        end
    end

    self.Logger:debug("Sync completed from " .. self.name .. " to " .. target_db.name)
end

--[[
-- Инициализация баз
local rp_db = Database:new("rp_data")
local races_db = Database:new("races_data")

-- Создание таблиц
rp_db:create_table("players", {
    id = 0,
    nickname = "",
    total_score = 0
}, "id")

races_db:create_table("race_participants", {
    race_id = 0,
    player_id = 0,
    game_time = 0,
    max_speed = 0
}, "race_id")

-- Заполнение гонок
races_db:get_table("race_participants"):insert({
    race_id = 1,
    player_id = 42,
    game_time = 125.3,
    max_speed = 210
})

-- Синхронизация данных
rp_db:sync(races_db, "race_participants", "players", {
    from_key = "player_id",
    to_key = "id",
    fields = {
        game_time = "last_race_time",
        max_speed = "record_speed"
    }
})

-- Результат: в таблицу players базы rp добавится запись:
-- {
--   id = 42,
--   nickname = "", -- Значение по умолчанию из шаблона
--   total_score = 0,
--   last_race_time = 125.3,
--   record_speed = 210
-- }
--]]

-- Генерация шаблона для базы данных
function Database:generate_all_templates()
    local templates = {}
    for table_name, table_instance in pairs(self.tables) do
        templates[table_name] = table_instance:generate_template()
    end
    return templates
end

-- Использование
--local all_templates = rp_db:generate_all_templates()
--print(all_templates.players) --> {id=1, name="Alice", ...}

--- Получение таблицы по имени
---@param name string Название таблицы
---@return Table|nil Таблица или nil
function Database:get_table(name)
    return self.tables[name]
end

--- Выполнение JOIN двух таблиц
---@param left_table string Название левой таблицы
---@param right_table string Название правой таблицы
---@param on_field string Поле для объединения
---@return table Результат JOIN
function Database:join(left_table_name, right_table_name, on_field)
    local left_table = self:get_table(left_table_name)
    local right_table = self:get_table(right_table_name)

    if not left_table or not right_table then
        error("Invalid table names")
    end

    local result = {}
    local left_data = left_table.data
    local right_data = right_table.data

    for key, left_row in pairs(left_data) do
        local join_key = left_row[on_field]
        for _, right_row in ipairs(right_table:select({[on_field] = join_key})) do
            local merged = {}
            for k, v in pairs(left_row) do merged[k] = v end
            for k, v in pairs(right_row) do merged[k] = v end
            table.insert(result, merged)
        end
    end

    return result
end

--- Простой SQL-парсер (поддерживает базовые операции)
---@param query string SQL-запрос
---@return table Результат выполнения
function Database:execute(query)
    local tokens = self:tokenize_query(query)
    if not tokens then return end

    if tokens.type == "SELECT" then
        return self:parse_select(tokens)
    elseif tokens.type == "INSERT" then
        return self:parse_insert(tokens)
    -- Добавить обработку других типов запросов
    end
end

--- Токенизация SQL-запроса
---@param query string Входной запрос
---@return table Токены
function Database:tokenize_query(query)
    -- Простой парсер для примера
    local _, _, type, rest = string.find(query:upper(), "^([A-Z]+) (.*)")
    if not type then return end

    local tokens = {type = type}

    if type == "SELECT" then
        -- Разбор SELECT * FROM table WHERE...
        -- Пример: SELECT * FROM users WHERE age > 18
        -- Нужно разбить на части
        local _, _, fields_part, from_part, where_part =
            string.find(rest, "([%*%w, ]+) FROM ([%w]+)(.*)")

        tokens.fields = fields_part:match("%*") and "*" or
            {fields_part:match("(%w+)")}
        tokens.table_name = from_part
        tokens.where = where_part:sub(3) -- Убираем "WHERE "
    end

    return tokens
end

--- Обработка SELECT-запроса
---@param tokens table Токены
---@return table Результат
function Database:parse_select(tokens)
    local table_instance = self:get_table(tokens.table_name)
    if not table_instance then return {} end

    local condition = {}
    if tokens.where then
        -- Простая обработка условия вида age > 18
        local _, _, field, op, value =
            string.find(tokens.where, "(%w+)([%<%>!=]+)(%d+)")
        condition[field] = {op = op, value = tonumber(value)}
    end

    -- Выполняем запрос с условием
    local results = table_instance:select(condition)

    return results
end

--- Транзакционные операции
function Database:begin_transaction()
    table.insert(self.transactions, {})
    self.Logger:debug("Transaction started")
end

function Database:commit()
    if #self.transactions == 0 then return end
    self.transactions[#self.transactions] = nil
    self.Logger:debug("Transaction committed")
end

function Database:rollback()
    if #self.transactions == 0 then return end
    -- Реализация отката изменений (здесь требуются дополнительные механизмы)
    self.Logger:debug("Transaction rolled back")
end

--- Создание индекса для поля таблицы
---@param table_name string Имя таблицы
---@param field string Имя поля
function Database:create_index(table_name, field)
    local table_instance = self:get_table(table_name)
    if not table_instance then return end

    -- Создаем индекс в виде таблицы {значение = {ключи}}
    self.indexes[table_name] = self.indexes[table_name] or {}
    self.indexes[table_name][field] = {}

    for key, row in pairs(table_instance.data) do
        local value = row[field]
        self.indexes[table_name][field][value] = self.indexes[table_name][field][value] or {}
        table.insert(self.indexes[table_name][field][value], key)
    end

    self.Logger:debug("Index created for " .. table_name .. "." .. field)
end

--- Поиск с использованием индекса
---@param table_name string Имя таблицы
---@param field string Имя поля
---@param value any Значение для поиска
---@return table Результат
function Database:index_search(table_name, field, value)
    local index = self.indexes[table_name] and self.indexes[table_name][field]
    if not index then return {} end

    local keys = index[value] or {}
    local results = {}

    for _, key in ipairs(keys) do
        table.insert(results, self:get_table(table_name).data[key])
    end

    return results
end

-- Пример использования:
local db = Database:new("data")

-- Создаем таблицы
local users = db:create_table("users", {
    id = 0,
    name = "",
    age = 0
}, "id")

local orders = db:create_table("orders", {
    order_id = 0,
    user_id = 0,
    amount = 0
}, "order_id")

-- Вставка данных
users:insert({id = 1, name = "Alice", age = 30})
orders:insert({order_id = 101, user_id = 1, amount = 100})

-- Пример JOIN
local joined_data = db:join("users", "orders", "id")
-- Результат будет содержать объединенные данные

-- Пример SQL-запроса
local results = db:execute("SELECT * FROM users WHERE age > 25")
-- Вернет запись Alice

-- Транзакции
db:begin_transaction()
users:insert({id = 2, name = "Bob", age = 22})
-- ... какие-то операции ...
db:commit()

-- Индексирование
db:create_index("users", "age")
local found = db:index_search("users", "age", 30)
-- Вернет Alice