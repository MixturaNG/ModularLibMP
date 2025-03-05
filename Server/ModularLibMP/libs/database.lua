local Logger = require("libs.logger")
-- Define the Database class
---@class Database
local Database = {}
Database.__index = Database

-- Class constructor
function Database:new(path,filename, template, key_field)
    local obj = setmetatable({}, self)
    obj.Logger = Logger:clone()
    local subname = filename:sub(1, 5)
    obj.Logger:setPrefix("DB <" .. filename .. ">")
    assert(type(path) == "string", "Path must be a string")
    assert(type(filename) == "string", "Filename must be a string")
    obj.filename = filename .. ".ixt"
    obj.pathFilename = FS.ConcatPaths(path, filename .. ".ixt")
    obj.pathHashfile = FS.ConcatPaths(path, filename .. ".hixt")
    obj.template = template
    obj.key_field = key_field or "id"
    obj.hash = obj:load_hash()
    obj.data = obj:load_data()
    obj.last_edit = nil
    obj.last_access = os.time()
    obj.save_interval = 1 -- in seconds
    obj.inactivity_threshold = 15 -- in minutes
    obj.Logger:debug("Database initialized: " .. obj.filename)
    return obj
end

function Database:load_hash()
    if not FS.Exists(self.pathHashfile) then
        self.Logger:warn("Hash file does not exist: " .. self.pathHashfile)
        return {}
    end
    local hash_file = io.open(self.pathHashfile, "r")
    if not hash_file then
        self.Logger:error("Failed to open hash file: " .. self.pathHashfile)
        return {}
    end
    local content = hash_file:read("*all")
    hash_file:close()
    local hash = Util.JsonDecode(content)
    if not hash then
        self.Logger:error("Failed to decode hash file content")
        return {}
    end
    self.Logger:debug("Loaded hash file database: " .. self.filename)
    return hash
end

function Database:load_data()
    if not FS.Exists(self.pathFilename) then
        self.Logger:warn("Data file does not exist: " .. self.pathFilename)
        return {}
    end
    local data_file = io.open(self.pathFilename, "r")
    if not data_file then
        self.Logger:error("Failed to open data file: " .. self.pathFilename)
        return {}
    end
    local rawdata = data_file:read("*all")
    local data = Util.JsonDecode(rawdata)
    data_file:close()
    return data
end

function Database:save_hash()
    local hash_file = io.open(self.pathHashfile, "w")
    if hash_file then
        hash_file:write(Util.JsonPrettify(Util.JsonEncode(self.hash)))
        hash_file:close()
        self.Logger:debug("Saved hash file database: " .. self.filename)
    end
end

function Database:save_data()
    local data_file = io.open(self.pathFilename, "w")
    if data_file then
        data_file:write(Util.JsonPrettify(Util.JsonEncode(self.data)) .. "\n")
        data_file:close()
        self.last_save_time = os.time()
        self.last_edit = nil
        self.Logger:debug("Saved data file database: " .. self.filename)
    end
end

-- Insert a new record
function Database:insert(userdata)
    local key = userdata[self.key_field]
    assert(userdata[self.key_field], "Missing key field in userdata")
    if self.data[key] then
        error("Record with key '" .. key .. "' already exists.")
    end
    self.data[key] = userdata
    self.hash[key] = {deleted = false}
    self.last_edit = os.time()
    self.last_access = os.time()
end

function Database:update(condition, updates)
    for key, userdata in pairs(self.data) do
        local match = true
        for k, v in pairs(condition) do
            if userdata[k] ~= v then
                match = false
                break
            end
        end
        if match then
            for k, v in pairs(updates) do
                if type(v) == "table" and v.fn and type(v.fn) == "function" then
                    if userdata[k] == nil then
                         userdata[k] = v.default or {}
                    end
                    userdata[k] = v.fn(userdata[k])
                elseif type(v) == "function" then
                    if userdata[k] == nil then
                         userdata[k] = {} -- Default empty table
                    end
                    userdata[k] = v(userdata[k])
                else
                    userdata[k] = v
                end
            end
            self.last_edit = os.time()
            self.last_access = os.time()
        end
    end
end

function Database:delete(condition)
    for key, userdata in pairs(self.data) do
        local match = true
        for k, v in pairs(condition) do
            if userdata[k] ~= v then
                match = false
                break
            end
        end
        if match then
            userdata.deleted = true
            self.hash[key].deleted = true
            self.last_edit = os.time()
            self.last_access = os.time()
        end
    end
end

function Database:select(condition)
    local results = {}
    for key, userdata in pairs(self.data) do
        if not userdata.deleted then
            local match = true
            for k, v in pairs(condition) do
                if userdata[k] ~= v then
                    match = false
                    break
                end
            end
            if match then
                table.insert(results, userdata)
            end
        end
    end
    self.last_access = os.time()
    return results
end

function Database:check_save()
    if self.last_edit and os.difftime(os.time(), self.last_edit) >= self.save_interval then
        self:save_data()
        self:save_hash()
    end
end

function Database:check_unload()
    if os.difftime(os.time(), self.last_access) >= self.inactivity_threshold * 60 then
        self.data = nil
    end
end

function Database:reload_data()
    self.data = self:load_data()
    self.last_access = os.time()
end

function Database:close()
    if self.last_edit then
        self:save_data()
        self:save_hash()
    end
    self.data = nil
    self.hash = nil
end

return Database

-- TODO: ADD LUAORM (https://github.com/wesen1/LuaORM/tree/e2b1da1d642a9ce232a988875c6c082688e085e5)
-- TODO: Install luasql.mysql in Docker
--[[
-- Create a new database instance
local db = Database:new("mydb", {id = nil, name = "", age = 0}, "id")

-- Insert sample records
db:insert({id = 1, name = "Alice", age = 30})
db:insert({id = 2, name = "Bob", age = 25})

-- Update Alice's age using a function
db:update({name = "Alice"}, {age = function(current) return current + 1 end})

-- Select and print all users
local users = db:select({})
for _, user in ipairs(users) do
    print("ID: " .. user.id .. ", Name: " .. user.name .. ", Age: " .. user.age)
end

-- Expected output:
-- ID: 1, Name: Alice, Age: 31
-- ID: 2, Name: Bob, Age: 25

-- Delete Bob
db:delete({name = "Bob"})

-- Select and print all users after deletion
local users = db:select({})
for _, user in ipairs(users) do
    print("ID: " .. user.id .. ", Name: " .. user.name .. ", Age: " .. user.age)
end

-- Expected output:
-- ID: 1, Name: Alice, Age: 31

local db = Database:new("path/to/database", "mydb", {id = nil, name = "", age = 0}, "id")

-- Perform database operations
db:insert({id = 1, name = "Alice", age = 30})
db:update({name = "Alice"}, {age = function(current) return current + 1 end})
db:delete({name = "Alice"})

-- Close the database
db:close()
--]]