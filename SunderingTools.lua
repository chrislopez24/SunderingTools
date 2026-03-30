-- SunderingTools
-- Lightweight interrupt tracker and bloodlust sound

local addonName, addon = ...
local Config = assert(_G.SunderingToolsConfig, "SunderingToolsConfig must load before SunderingTools.lua")
local Registry = assert(_G.SunderingToolsRegistry, "SunderingToolsRegistry must load before SunderingTools.lua")
local SettingsModel = assert(_G.SunderingToolsSettingsModel, "SunderingToolsSettingsModel must load before SunderingTools.lua")

_G.SunderingTools = addon

addon.name = addonName
addon.registry = addon.registry or Registry.New()
addon.modules = addon.modules or {}

function addon:RegisterModule(moduleDef)
    self.registry:Register(moduleDef)
    self.modules[moduleDef.key] = moduleDef
end

local editModePriority = {
    "InterruptTracker",
    "CrowdControlTracker",
    "BloodlustSound",
}

local function GetEditableModules(self)
    local editable = {}

    for _, moduleKey in ipairs(editModePriority) do
        local moduleDef = self.modules and self.modules[moduleKey]
        if moduleDef and moduleDef.SetEditMode then
            editable[#editable + 1] = moduleDef
        elseif self[moduleKey] and self[moduleKey].SetEditMode then
            editable[#editable + 1] = self[moduleKey]
        end
    end

    return editable
end

local function GetEditHandler(self, moduleKey)
    if moduleKey then
        local moduleDef = self.modules and self.modules[moduleKey]
        if moduleDef and moduleDef.SetEditMode then
            return moduleDef
        end

        if self[moduleKey] and self[moduleKey].SetEditMode then
            return self[moduleKey]
        end

        return nil
    end

    local editable = GetEditableModules(self)
    return editable[1]
end

function addon:BuildDefaults()
    local defaults = {
        global = {
            minimap = {
                hide = false,
                angle = 135,
                unlocked = false,
            },
            debugMode = false,
            editMode = false,
            activeEditModule = nil,
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

function addon:IsDebugEnabled()
    return self.db and self.db.global and self.db.global.debugMode == true
end

function addon:SetDebugEnabled(enabled)
    if not (self.db and self.db.global) then
        return
    end

    self.db.global.debugMode = enabled and true or false
end

function addon:DebugLog(scope, ...)
    if not self:IsDebugEnabled() then
        return
    end

    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(index, ...))
    end

    print(string.format(
        "|cff5fd7ffSunderingTools[%s]|r %s",
        tostring(scope or "debug"),
        table.concat(parts, " ")
    ))
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

function addon:GetMinimapAngle()
    local minimap = self.db and self.db.global and self.db.global.minimap or {}
    return tonumber(minimap.angle) or 135
end

function addon:SetMinimapAngle(angle)
    self.db.global.minimap.angle = tonumber(angle) or 135

    if self.minimapButton and self.minimapButton.UpdatePosition then
        self.minimapButton:UpdatePosition(self.db.global.minimap.angle)
    end
end

function addon:IsMinimapUnlocked()
    return self.db.global.minimap.unlocked == true
end

function addon:SetMinimapUnlocked(unlocked)
    self.db.global.minimap.unlocked = unlocked and true or false
end

function addon:ResetMinimapPosition()
    self:SetMinimapAngle(135)
end

function addon:CanOpenEditMode(moduleKey)
    return GetEditHandler(self, moduleKey) ~= nil
end

function addon:SetEditMode(enabled, moduleKey)
    local editable = GetEditableModules(self)
    local activeHandler = enabled and moduleKey and GetEditHandler(self, moduleKey) or nil
    local activeKey = activeHandler and activeHandler.key or nil

    if enabled and not moduleKey then
        activeKey = moduleKey or "ALL"
    end

    self.db.global.editMode = enabled and ((moduleKey == nil and #editable > 0) or activeHandler ~= nil)
    self.db.global.activeEditModule = self.db.global.editMode and activeKey or nil

    for _, tracker in ipairs(editable) do
        local shouldEnable = false
        if self.db.global.editMode then
            shouldEnable = activeKey == "ALL" or tracker == activeHandler
        end
        tracker:SetEditMode(shouldEnable)
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
    addon:DebugLog("init", "player login complete")
    print("|cff00ff00SunderingTools|r loaded. Type /su for settings.")
end)
