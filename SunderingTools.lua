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

local function GetInterruptTrackerEditHandler(self)
    local moduleDef = self.modules and self.modules.InterruptTracker
    if moduleDef and moduleDef.SetEditMode then
        return moduleDef
    end

    if self.InterruptTracker and self.InterruptTracker.SetEditMode then
        return self.InterruptTracker
    end

    return nil
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
        moduleDef:onConfigChanged(self, self.db.modules[moduleKey], key)
    end
end

function addon:GetSettingsSections()
    return SettingsModel.BuildSections(self.registry:List())
end

function addon:IsMinimapVisible()
    return not self.db.global.minimap.hide
end

function addon:SetMinimapVisible(visible)
    self.db.global.minimap.hide = not visible

    if self.minimapButton then
        if visible then
            self.minimapButton:Show()
        else
            self.minimapButton:Hide()
        end
    end
end

function addon:CanOpenEditMode()
    return GetInterruptTrackerEditHandler(self) ~= nil
end

function addon:SetEditMode(enabled)
    self.db.global.editMode = enabled and true or false

    local tracker = GetInterruptTrackerEditHandler(self)
    if tracker then
        tracker:SetEditMode(self.db.global.editMode)
    end
end

function addon:ResetAllSettings()
    SunderingToolsDB = nil
    ReloadUI()
end

-- Initialize native minimap button
function addon:InitMinimapIcon()
    self:CreateMinimapButton()
    self:SetMinimapVisible(self:IsMinimapVisible())
end

-- Register slash commands
SLASH_SUNDERINGTOOLS1 = "/su"
SLASH_SUNDERINGTOOLS2 = "/sundering"
SlashCmdList["SUNDERINGTOOLS"] = function(msg)
    if msg == "reset" then
        addon:ResetAllSettings()
    elseif msg == "config" or msg == "settings" then
        addon:OpenSettings()
    else
        addon:OpenSettings()
    end
end

-- Initialize on login
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    addon:InitDB()
    addon:InitMinimapIcon()
    print("|cff00ff00SunderingTools|r loaded. Type /su for settings.")
end)
