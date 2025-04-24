local M = {}
local config = require(FS.ConcatPaths("libs","config_loader"):gsub("/",".")).loadConfig(FS.ConcatPaths(pluginPath,"config","main_config.json"))
local Logger = require(FS.ConcatPaths("libs","logger"):gsub("/","."))
Logger:setPrefix("I18Text")
M.TranslatorLines = {}
M.TranslatorLines.edited = false
M.ConvertedTranslatorLines = {}
M.subscribesToUpdate = {}
M.cachedTexts = {}
--TODO: Добавить проверку на затирание полей
local function deepMerge(module,t2,first)
    if first == nil then first = false end
    local t1 = module
    if M.TranslatorLines[module] == nil and first == true then
        M.TranslatorLines[module] = t2
        return true
    elseif first == false then
        local tt2 = type(t2) == "table" and #t2 == 0 and "<empty Table>" or t2 -- Optimization By DeepSeek
        local tTraTab = M.TranslatorLines[module] == nil and "<nil>" or "<table>"
        if M.TranslatorLines[module] ~= nil then
            Logger:warn("Overwriting module: [" .. module .. "] with previous value: " .. tTraTab .. " new value: " .. tt2)
        end
        M.TranslatorLines[module] = M.TranslatorLines[module] or {}
        t1 = M.TranslatorLines[module]
    end
    if t2 == nil then
        Logger:error("FILE TRANSLATOR IS BROKEN")
        return false
    end
    for key, value in pairs(t2) do
        if type(value) == "table" then
            if type(t1[key] or false) == "table" then
                deepMerge(t1[key], value, true)
            else
                if not (key == "edited" or key == "author" or key == "version" or key == "uploaded") then
                    if t1[key] == nil then
                        t1[key] = value
                    else
                        Logger:warn("Overwriting field: " .. key .. " with previous value: " .. t1[key] .. " new value: " .. value)
                        t1[key] = value
                    end
                end
            end
        else
            if not (key == "edited" or key == "author" or key == "version" or key == "uploaded") then
                if t1[key] == nil then
                    t1[key] = value
                else
                    Logger:warn("Overwriting field: " .. key .. " with previous value: " .. t1[key] .. " new value: " .. value)
                    t1[key] = value
                end
            end
        end
    end
    M.TranslatorLines.edited = true
    return true
end

local function loadConfig(module,path)
    if path == nil then
        path = module
        module = "base"
    end
    if not FS.Exists(path) then
        Logger:warn("Config file not found: " .. path:gsub(pluginPath, ""))
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
    if result.author and result.version and result.uploaded then
        Logger:info("Translator loaded: [" .. module .. "] | Author: " .. result.author .. " | Version: " .. result.version .. " | Uploaded: " .. result.uploaded)
    end
    if deepMerge(module,result) then
        local LangCount = 0
        local LineCount = 0
        for key, value in pairs(M.TranslatorLines[module]) do
            for field, value_str in pairs(value) do
                LineCount = LineCount + 1
            end
            LangCount = LangCount + 1
        end
        Logger:info("Translator loaded: [" .. module .. "] | Found Languages: " .. LangCount .. " | Translated Lines: " .. LineCount//LangCount)
    end

    return result
end

local function getTraslator(module,lang, field, ...)
    if field == nil then
        field = lang
        lang = config.lang
    elseif field == nil and lang == nil then
        field = module
        lang = config.lang
        module = "base"
    end
    if M.TranslatorLines[module] == nil or M.TranslatorLines[module][lang] == nil or M.TranslatorLines[module][lang][field] == nil then
        Logger:error("Translator not found: " .. (module or "<nil>") .. " " .. (lang or "<nil>") .. " " .. (field or "<nil>"))
        return "Translator not found: " .. (module or "<nil>") .. " " .. (lang or "<nil>") .. " " .. (field or "<nil>")
    end
    return string.format(M.TranslatorLines[module][lang][field], ...)
end

local function loadCustomTranslator(path)
    local directories = FS.ListFiles(path)
    if #directories > 0 then
        for _, directory in ipairs(directories) do
            loadConfig(directory,FS.ConcatPaths(path,directory))
        end
    end
end

local function RunSubscribes()
    if #M.subscribesToUpdate == 0 then
        return
    end
    for i, funcs in pairs(M.subscribesToUpdate) do
        funcs()
    end
end

local function ConvertTranslator()
    if M.TranslatorLines.edited == false then
        return
    end
    M.ConvertedTranslatorLines = {}
    for module, trasleted in pairs(M.TranslatorLines) do -- "module"  : {}
        if module == "edited" then
        else
            for lang, value in pairs(trasleted) do -- "ru"  : {}
                for key, value2 in pairs(value) do -- "desc": "Описание"
                    local editkey = key:gsub("_",".")
                    if M.ConvertedTranslatorLines[editkey] == nil then
                        M.ConvertedTranslatorLines[editkey] = {}
                    end
                    if M.ConvertedTranslatorLines[editkey][lang] == nil then
                        M.ConvertedTranslatorLines[editkey][lang] = value2
                    else
                        Logger:warn("Overwriting field: " .. editkey .. " with previous value: " .. M.ConvertedTranslatorLines[editkey][lang] .. " new value: " .. value2)
                    end
                end
            end
        end
    end
    M.TranslatorLines.edited = false
    Logger:debug("Translator converted")
    RunSubscribes()
end

local function findTranslation(field)
    field = field:gsub("_",".")
    if M.ConvertedTranslatorLines[field] == nil then
        ConvertTranslator(field)
    end
    if M.ConvertedTranslatorLines[field] == nil then
        return "Translator not found: " .. field
    end
    return M.ConvertedTranslatorLines[field]
end

local function getTextV2(field, lang, ...)
    local text = findTranslation(field)
    if type(text) == "string" then
        return text
    end
    if M.cachedTexts[field] == nil then
        M.cachedTexts[field] = {}
    end
    if M.cachedTexts[field][lang] ~= nil then
        print(M.cachedTexts[field][lang])
        return string.format(M.cachedTexts[field][lang], ...)
    end


    if text[lang] ~= nil then
        M.cachedTexts[field][lang] = text[lang]
        return string.format(text[lang], ...)
    elseif text[config.lang] ~= nil then
        M.cachedTexts[field][lang] = text[config.lang]
        Logger:warn("[User:'"..lang.."'] translator not found: " .. field.. " | This result has be cached")
        return string.format(text[config.lang], ...)
    elseif text[config.baseLang] then
        M.cachedTexts[field][lang] =text[config.baseLang]
        Logger:warn("[User:'"..lang.."'] [TargetServer:'"..config.lang.."'] translator not found: " .. field.. " | This result has be cached")
        return string.format(text[config.baseLang], ...)
    end
    Logger:warn("[User:'"..lang.."'] [TargetServer:'"..config.lang.."'] [Base:'"..config.baseLang.."'] translator not found: " .. field.. " | Find Any Translations")
    local findes_lang = ""
    for key, value in pairs(text) do
        findes_lang = key
        break
    end

    if findes_lang == "" then
        Logger:warn("Translator not found: " .. field)
        return "Translator not found: " .. field
    elseif text[findes_lang] ~= nil then
        M.cachedTexts[field][lang] = text[findes_lang]
        Logger:warn("Finded Translator: " .. "[Any:'"..findes_lang.."'] -> " .. field .. " | This result has be cached")
        return string.format(text[findes_lang], ...)
    end
end

local function getTextV3(user_id, filed, ...)
    local lang = config.lang or MP.GetLanguage(user_id)

    local end_filds = getTextV2(filed,lang,...)
    return end_filds
end

local function getText(field, ...)
    return getTraslator("base",config.lang, field, ...)
end

local Translator = {}
Translator.__index = Translator

function Translator:init(module,lconfig)
    local obj = setmetatable({}, self)
        obj.module = module
        obj.config = lconfig
        obj.obj = M
    return obj
end

local function export()
    local exportTable = {}
    -- первый проход для сбора по базовым перводам
    for module, trasleted in pairs(M.TranslatorLines) do
        if module == "edited" then
        else
            for lang, value in pairs(trasleted) do
                local base_lang = split(lang,"-")[1]
                if base_lang == lang then
                    if exportTable[base_lang] == nil then
                        exportTable[base_lang] = {}
                    end
                    for key, value2 in pairs(value) do
                        if exportTable[base_lang][key] == nil then
                            exportTable[base_lang][key] = value2
                        end
                    end
                end
            end
        end
    end
    -- второй проход для сбора по кастомным перводам
    for module, trasleted in pairs(M.TranslatorLines) do
        if module == "edited" then
        else
            for lang, value in pairs(trasleted) do
                local base_lang = split(lang,"-")[1]
                for key, value2 in pairs(value) do
                    if exportTable[base_lang][key] == nil then
                        exportTable[base_lang][key] = value2
                    end
                end
            end
        end
    end
    exportTable.author = "ModularLibMP-Server"
    exportTable.version = "1.0.0"
    exportTable.uploaded = os.date("%Y-%m-%d %H:%M:%S")

    local file = io.open(FS.ConcatPaths(pluginPath,"config","export_translator.json"), "w")
    file:write(Util.JsonPrettify(Util.JsonEncode(exportTable)))
    file:close()
end

local function subscribeUpdate(func)
    M.subscribesToUpdate[#M.subscribesToUpdate + 1] = func
end

function Translator:getText(field, ...)
    if M.TranslatorLines[self.module] == nil then
        Logger:error("Translator not found: " .. self.module)
        return "Translator not found: " .. self.module
    end
    return getTraslator(self.module, self.config.lang, field, ...)
end

-- API
M.getTextV3 = getTextV3 -- Выдаст перевод ТОЛЬКО из BASE файла перевода на язык указанный в конфиге (local config -> global config)
M.getTextV2 = getTextV2 -- Выдаст перевод на язык lang
M.getText = getText     -- Выдаст перевод на язык пользователя (Лучше использовать MP.TranslatedMessage)
M.export = export
M.subscribeUpdate = subscribeUpdate
-- Специфичная функция
M.addTranslator = deepMerge

-- Запускается само
M.loadCustomTranslator = loadCustomTranslator
M.loadConfig = loadConfig
M.ClassTranslator = Translator
M.convert = ConvertTranslator

return M