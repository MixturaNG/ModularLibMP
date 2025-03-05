-- libs/logger.lua

local function loadConfig(path)
    local file = io.open(path, "r")
    if not file then
        error("Config file not found: " .. path)
    end

    local content = file:read("*a")
    file:close()

    local status, result = pcall(Util.JsonDecode, content)
    if not status then
        error("Failed to parse config file: " .. result)
    end
    return result
end

local inspect = require("libs.inspect")

-- Utility function to get the current timestamp
local function getTimestamp()
    return os.date("[%d.%m.%Y %H:%M:%S]")
end


local Logger = {}
Logger.__index = Logger

function Logger:init()
    local obj = setmetatable({}, self)

    local privat = {}
        privat.logLevel = loadConfig("Resources/Server/ModularLibMP/config/main_config.json").logLevel
        privat.logToFile = true
        privat.logFilePath = "Resources/Server/ModularLibMP/logs/ModularLibMP.log"
        privat.enableColors = true
        privat.prefix = nil
        privat.levels = {
            DEBUG = 1,
            INFO = 2,
            WARN = 3,
            ERROR = 4
        }

        privat.colors = {
            reset = "\27[0m",
            debug = "\27[36m",  -- Cyan
            info = "\27[32m",   -- Green
            warn = "\27[33m",   -- Yellow
            error = "\27[31m"   -- Red
        }

    -- Ensure log directory exists using FS
    function privat:ensureLogDirectoryExists()
        local logDir = FS.GetParentFolder(privat.logFilePath)
        if not FS.Exists(logDir) then
            local success, err = FS.CreateDirectory(logDir)
            if not success then
                print(string.format("%s [ERROR] Failed to create log directory: %s", getTimestamp(), err))
            end
        end
    end

    function obj:setIntLevel(level)
        if not level then return end
        if level >= 1 and level <= 4 then
            privat.logLevel = level
        else
            obj.warn("Invalid log level: " .. tostring(level))
        end
    end

    function obj:setPrefix(prefix)
        if not prefix then return end
        privat.prefix = prefix
    end

    function obj:enableFileLogging(filePath)
        privat.logToFile = true
        if filePath then
            privat.logFilePath = filePath
        end
        privat:ensureLogDirectoryExists() -- Ensure the directory exists
    end

    function obj:log(level, levelName, message)
        if level < privat.logLevel then return end

        local color = ""
        if privat.enableColors then
            if levelName == "DEBUG" then
                color = privat.colors.debug
            elseif levelName == "INFO" then
                color = privat.colors.info
            elseif levelName == "WARN" then
                color = privat.colors.warn
            elseif levelName == "ERROR" then
                color = privat.colors.error
            end
        end

            -- Функция для обработки вывода inspect
        local function customProcess(item, path)
            if type(item) == "table" then
                -- Преобразуем все элементы таблицы в строки
                local stringElements = {}
                for i, v in ipairs(item) do
                    if type(v) == "table" then
                        -- Если элемент — таблица, рекурсивно обрабатываем его
                        stringElements[i] = customProcess(v, path)
                    else
                        -- Иначе просто преобразуем в строку
                        stringElements[i] = tostring(v)
                    end
                end
                -- Объединяем элементы в строку
                local end_str = table.concat(stringElements, " ")
            return end_str
        end
            if type(item) == "string" then
                return string.format("%s", item)

            end
        end

        local function getFunctionName(level)
            level = level or 5
            if level == 3 then return "lambda" end
            local info = debug.getinfo(level,'n')
            if not info then return getFunctionName(level - 1) end
            if info.namewhat == "" or info.name == "debug" then
                return getFunctionName(level - 1)
            else
                return info.name
            end
        end
        local LogMes = inspect(message, { process = customProcess })
        LogMes = LogMes:match("\"(.*)\"")
        local LogPrefix = string.format("%s [%s]\t", getTimestamp(), levelName)
        if privat.prefix then
            if #privat.prefix >= 14 then
                privat.prefix = string.sub(privat.prefix, 1, 11)
                privat.prefix = privat.prefix .. ".."
            end

            local prefixLength = #privat.prefix
            local padding = math.floor((13 - prefixLength) / 2)
            local paddedPrefix = string.rep(" ", padding) .. privat.prefix .. string.rep(" ", padding)
            if #paddedPrefix < 13 then
                paddedPrefix = paddedPrefix .. " "
            end

            local levelNameLength = #levelName
            local paddingLevel = math.floor((7 - levelNameLength) / 2)
            levelName = string.rep(" ", paddingLevel) .. levelName .. string.rep(" ", paddingLevel + ( levelNameLength % 2 == 0 and 1 or 0))

            LogPrefix = string.format("%s [%s]\t[%s]\t[%s]", getTimestamp(),levelName, paddedPrefix, getFunctionName())
        end
        local logMessage = string.format("%s -> %s", LogPrefix, LogMes)
        printRaw(color .. logMessage .. privat.colors.reset)

        if privat.logToFile then
            privat:ensureLogDirectoryExists()
            local file, err = io.open(privat.logFilePath, "a")
            if file then
                file:write(logMessage .. "\n")
                file:close()
            else
                print(string.format("%s [ERROR] Failed to write to log file: %s", getTimestamp(), err))
            end
        end
    end

    -- Добавляем метод clone
    function obj:clone()
        return Logger:init()
    end

    return obj
end

-- TODO: Добавить откуда вызывается log (https://www.lua.org/pil/23.1.html)
--[[
--print(debug.traceback())
local info = debug.getinfo(2,'n')
local funcname = info.name or debug.getinfo(1,'n').name
printRaw("["..M.pluginName.."] ["..type.."] ["..funcname.."] ".. color .. message .. "\27[0m")
--]]


-- Log debug messages
function Logger:debug(...)
    self:log(1, "DEBUG", { ... } )
end

-- Log info messages
function Logger:info(...)
    self:log(2, "INFO", { ... })
end

-- Log warning messages
function Logger:warn(...)
    self:log(3, "WARN", { ... })
end

-- Log error messages
function Logger:error(...)
    self:log(4, "ERROR", { ... })
end

return Logger:init()
