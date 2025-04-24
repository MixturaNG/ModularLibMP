-- libs/config.lua

local Config = {}

-- okTODO: Добавить логгирование ГОТОВО
local Logger = require("libs.logger")
Logger = Logger:clone()
Logger:setPrefix("ConfigLoader")
local function loadConfig(path)
    if not FS.Exists(path) then
        Logger:warn("File Exist is False | Config file not found: " .. path:gsub(FS.ConcatPaths(pluginPath), ""))
        return nil
    end
    local file = io.open(path, "r")

    if not file then
        Logger:error("Config file not found: " .. path)
        return nil
    end

    local content = file:read("*a")
    file:close()
    local status, result = pcall(Util.JsonDecode, content)
    if not status then
        error("Failed to parse config file: " .. result)
    end
    return result
end

local function TryLoadLocalConfig(modulePath)
    local ret = nil
    ret = loadConfig(FS.ConcatPaths(modulePath,"config.json"))
    if not ret or ret == {} then
        ret = loadConfig(FS.ConcatPaths(pluginPath,"config","main_config.json"))
    end
    return ret
end

local function MergesConfig(modulePath)
    local locals = loadConfig(FS.ConcatPaths(modulePath,"config.json"))
    local globals = loadConfig(FS.ConcatPaths(pluginPath,"config","main_config.json"))
    local merged = {}
    if globals then
        for key, value in pairs(globals) do
            merged[key] = value
        end
    end
    if locals then
        for key, value in pairs(locals) do
            merged[key] = value
        end
    end
    return merged
end

-- okTODO: Добавить saveConfig(path, data) ГОТОВО
-- okTODO: Не вся инфа важна, лучше писать ее как debug
local function saveConfig(path, data)
    if not path or path == "" then
        error("Path to config file is invalid or empty.")
    end

    if not data or type(data) ~= "table" then
        error("Data to save must be a table.")
    end

    Logger:debug("Saving config to path: " .. path)

    local content, encodeError = pcall(Util.JsonEncode, data)
    if not content then
        error("Failed to encode data to JSON: " .. encodeError)
    end

    local file, openError = io.open(path, "w")
    if not file then
        error("Failed to open file for writing: " .. openError)
    end

    file:write(content)
    file:close()

    Logger:debug("Config saved successfully.")
end


-- okTODO: Добавить saveConfig ГОТОВО
Config.saveConfig = saveConfig
Config.loadConfig = loadConfig
Config.TryLoadLocalConfig = TryLoadLocalConfig
Config.MergesConfig = MergesConfig
return Config
