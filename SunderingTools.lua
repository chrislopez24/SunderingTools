-- SunderingTools
-- Lightweight interrupt tracker and bloodlust sound

local addonName, addon = ...
local Config = _G.SunderingToolsConfig or dofile("Core/Config.lua")
local Registry = _G.SunderingToolsRegistry or dofile("Core/Registry.lua")
local SettingsModel = _G.SunderingToolsSettingsModel or dofile("Core/SettingsModel.lua")

_G.SunderingTools = addon

addon.name = addonName
addon.registry = addon.registry or Registry.New()
addon.modules = addon.modules or {}

function addon:RegisterModule(moduleDef)
    self.registry:Register(moduleDef)
    self.modules[moduleDef.key] = moduleDef
end

function addon:BuildDefaults()
    local defaults = {
        global = {
            minimap = { hide = false },
            editMode = false,
        },
        modules = {},
    }

    for key, moduleDef in pairs(self.modules) do
        defaults.modules[key] = moduleDef.defaults or {}
    end

    return defaults
end

function addon:InitDB()
    local db = SunderingToolsDB or {}
    db.modules = db.modules or {}

    -- Preserve pre-registry module settings until modules are migrated.
    for key in pairs(self.modules) do
        if type(db.modules[key]) ~= "table" then
            db.modules[key] = type(db[key]) == "table" and db[key] or {}
        end
    end

    SunderingToolsDB = Config.MergeDefaults(db, self:BuildDefaults())
    self.db = SunderingToolsDB

    for key in pairs(self.modules) do
        self.db[key] = self.db.modules[key]
    end
end

function addon:SetModuleValue(moduleKey, key, value)
    self.db.modules = self.db.modules or {}
    self.db.modules[moduleKey] = self.db.modules[moduleKey] or {}
    self.db.modules[moduleKey][key] = value
    self.db[moduleKey] = self.db.modules[moduleKey]

    local moduleDef = self.modules[moduleKey]
    if moduleDef and moduleDef.onConfigChanged then
        moduleDef.onConfigChanged(self, self.db.modules[moduleKey], key)
    end
end

function addon:GetSettingsSections()
    return SettingsModel.BuildSections(self.registry:List())
end

function addon:SetEditMode(enabled)
    self.db.global.editMode = enabled

    if self.InterruptTracker and self.InterruptTracker.SetEditMode then
        self.InterruptTracker.SetEditMode(self.db.modules.InterruptTracker, enabled)
    end
end

addon:RegisterModule({
    key = "InterruptTracker",
    order = 10,
    label = "Interrupt Tracker",
    defaults = {
        enabled = true,
        showIcon = true,
        showName = true,
        showTimer = true,
        iconSize = 24,
        barWidth = 150,
        barHeight = 24,
        spacing = 2,
        maxBars = 5,
        growDirection = "DOWN",
        posX = 0,
        posY = -200,
        fontSize = 14,
        useClassColor = true,
    },
})

addon:RegisterModule({
    key = "BloodlustSound",
    order = 20,
    label = "Bloodlust Sound",
    defaults = {
        enabled = true,
        hideIcon = false,
        iconSize = 64,
        posX = 0,
        posY = 100,
        soundFile = "Interface\\AddOns\\SunderingTools\\sounds\\bloodlust.ogg",
        soundChannel = "Master",
        duration = 40,
    },
})

-- Initialize minimap icon
function addon:InitMinimapIcon()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LDB and LibStub("LibDBIcon-1.0", true)

    if not LDB or not LDBIcon then
        self:CreateMinimapButton()
        return
    end

    -- Create LDB data object
    local dataObject = LDB:NewDataObject("SunderingTools", {
        type = "launcher",
        text = "SunderingTools",
        icon = "Interface\\Icons\\Ability_Warrior_PunishingBlow",
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("|cff00ff00SunderingTools|r")
            tooltip:AddLine("Click to open settings")
            tooltip:AddLine(" ")
            tooltip:AddLine("Interrupt Tracker: Track party interrupts")
            tooltip:AddLine("Bloodlust Sound: Alert on bloodlust/heroism")
        end,
        OnClick = function(_, button)
            if button == "LeftButton" then
                addon:OpenSettings()
            elseif button == "RightButton" then
                -- Quick toggle menu
                addon:ShowQuickMenu()
            end
        end,
    })

    -- Register with LibDBIcon
    LDBIcon:Register("SunderingTools", dataObject, self.db.global.minimap)
    self.minimapIcon = LDBIcon
end

-- Show quick toggle menu
function addon:ShowQuickMenu()
    local menu = {
        { text = "|cff00ff00SunderingTools|r", isTitle = true, notCheckable = true },
        { text = "Settings", func = function() addon:OpenSettings() end, notCheckable = true },
        { text = " ", notCheckable = true, disabled = true },
        {
            text = "Interrupt Tracker",
            checked = function() return addon.db.InterruptTracker.enabled end,
            func = function()
                addon.db.InterruptTracker.enabled = not addon.db.InterruptTracker.enabled
                -- Reload module
                ReloadUI()
            end,
            keepShownOnClick = true,
        },
        {
            text = "Bloodlust Sound",
            checked = function() return addon.db.BloodlustSound.enabled end,
            func = function()
                addon.db.BloodlustSound.enabled = not addon.db.BloodlustSound.enabled
            end,
            keepShownOnClick = true,
        },
        { text = " ", notCheckable = true, disabled = true },
        { text = "Test Bloodlust", func = function()
            if addon.BloodlustSound and addon.BloodlustSound.Play then
                addon.BloodlustSound.Play()
            end
        end, notCheckable = true },
        { text = "Interrupt Stats", func = function()
            if addon.InterruptTracker and addon.InterruptTracker.PrintStats then
                addon.InterruptTracker.PrintStats()
            end
        end, notCheckable = true },
        { text = " ", notCheckable = true, disabled = true },
        { text = "Close", notCheckable = true },
    }

    EasyMenu(menu, CreateFrame("Frame", "SunderingToolsQuickMenu", UIParent, "UIDropDownMenuTemplate"), "cursor", 0, 0, "MENU")
end

-- Register slash commands
SLASH_SUNDERINGTOOLS1 = "/su"
SLASH_SUNDERINGTOOLS2 = "/sundering"
SlashCmdList["SUNDERINGTOOLS"] = function(msg)
    if msg == "reset" then
        SunderingToolsDB = nil
        ReloadUI()
    elseif msg == "config" or msg == "settings" then
        addon:OpenSettings()
    else
        addon:ShowQuickMenu()
    end
end

-- Initialize on login
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    addon:InitDB()
    addon:InitMinimapIcon()
    print("|cff00ff00SunderingTools|r loaded. Type /su for options.")
end)
