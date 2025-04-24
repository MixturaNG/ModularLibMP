-- ModularLibMP BeamMP Plugin

-- Фикс русского языка
os.setlocale( "C", "ctype" );
os.execute( "chcp 65001 > nul" )
IKnowWhatDoing = {}
currentVersion = "0.1"

print("ModularLibMP BeamMP Plugin v" .. currentVersion .. " loaded")

pluginPath = debug.getinfo(1).source:gsub("\\","/")
pluginPath = pluginPath:sub(1,(pluginPath:find("main.lua"))-2)

require("libs.globalFunction")

local config = require("libs.config_loader").loadConfig(FS.ConcatPaths(pluginPath,"config","main_config.json"))
local i18text = require("libs.i18text")
i18text.loadConfig(FS.ConcatPaths(pluginPath,"config","base_translation.json"))
i18text.loadCustomTranslator(FS.ConcatPaths(pluginPath,"config","custom_translation"))
local ReplaceBaseFunctions = require("modules.core.RepBaseFunc")
ReplaceBaseFunctions.config = config
ReplaceBaseFunctions.i18text = i18text

local EventHandler = require("modules.core.event_handler")
EventHandler:RegEvent()

--local Controller = require("modules.core.controller")
--Controller.Event = EventHandler
--Controller:RegEvent()
local MessageHandler = require("modules.core.message_handler")
local ModuleHandler = require("modules.core.module_loader")
ModuleHandler.i18text = i18text
ModuleHandler.messageHandler = MessageHandler
MessageHandler:RegEvent()

function onInit()
    ModuleHandler.loadAllModules()
    ModuleHandler.loaded_full()
end

