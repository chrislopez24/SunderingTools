local function stubFrame()
  return {
    RegisterEvent = function() end,
    SetScript = function() end,
  }
end

local function loadAddon()
  _G.SunderingTools = nil
  _G.SunderingToolsConfig = {
    MergeDefaults = function(db, defaults)
      db = db or {}
      defaults = defaults or {}
      for key, value in pairs(defaults) do
        if type(value) == "table" then
          db[key] = _G.SunderingToolsConfig.MergeDefaults(db[key] or {}, value)
        elseif db[key] == nil then
          db[key] = value
        end
      end
      return db
    end,
  }
  _G.SunderingToolsRegistry = {
    New = function()
      return {
        Register = function() end,
        List = function()
          return {}
        end,
      }
    end,
  }
  _G.SunderingToolsSettingsModel = {
    BuildSections = function()
      return {}
    end,
  }
  _G.CreateFrame = function()
    return stubFrame()
  end
  _G.ReloadUI = function() end
  _G.SlashCmdList = {}

  local addon = {}
  local chunk = assert(loadfile("SunderingTools.lua"))
  chunk("SunderingTools", addon)
  return addon
end

local addon = loadAddon()
addon.db = {
  global = { minimap = { hide = false }, debugMode = false, editMode = false, activeEditModule = nil },
  modules = { InterruptTracker = {}, CrowdControlTracker = {}, BloodlustSound = {} },
}

local defaults = addon:BuildDefaults()
assert(defaults.global.debugMode == false, "debug mode should default to false")

local hidden = 0
local shown = 0
addon.minimapButton = {
  Hide = function()
    hidden = hidden + 1
  end,
  Show = function()
    shown = shown + 1
  end,
}

addon:SetMinimapVisible(false)
assert(addon.db.global.minimap.hide == true, "hiding the minimap button should update saved state")
assert(hidden == 1, "native minimap button should hide when disabled")

addon:SetMinimapVisible(true)
assert(addon.db.global.minimap.hide == false, "showing the minimap button should update saved state")
assert(shown == 1, "native minimap button should show when enabled")

assert(addon:IsDebugEnabled() == false, "debug mode should default to disabled")
addon:SetDebugEnabled(true)
assert(addon:IsDebugEnabled() == true, "debug mode should become enabled when toggled on")
addon:SetDebugEnabled(false)
assert(addon:IsDebugEnabled() == false, "debug mode should become disabled when toggled off")

assert(addon:CanOpenEditMode() == false, "edit mode should be unavailable without module support")
local editModeStates = {}
addon.InterruptTracker = {
  SetEditMode = function(_, enabled)
    table.insert(editModeStates, enabled)
  end,
}
assert(addon:CanOpenEditMode() == true, "edit mode should be available when the module exposes support")

addon:SetEditMode(true)
addon:SetEditMode(false)
assert(addon.db.global.editMode == false, "edit mode should be writable back to the locked state")
assert(editModeStates[1] == true and editModeStates[2] == false, "edit mode should notify the module on both transitions")

local ccEditModeStates = {}
addon.CrowdControlTracker = {
  SetEditMode = function(_, enabled)
    table.insert(ccEditModeStates, enabled)
  end,
}
local bloodlustEditModeStates = {}
addon.BloodlustSound = {
  SetEditMode = function(_, enabled)
    table.insert(bloodlustEditModeStates, enabled)
  end,
}

assert(addon:CanOpenEditMode("CrowdControlTracker") == true, "edit mode should be available for the requested crowd control tracker module")
addon:SetEditMode(true, "CrowdControlTracker")
addon:SetEditMode(false, "CrowdControlTracker")
assert(ccEditModeStates[1] == true and ccEditModeStates[2] == false, "requested edit mode should notify the crowd control tracker")

addon:SetEditMode(true)
assert(addon.db.global.activeEditModule == "ALL", "global edit mode should use the ALL state")
assert(editModeStates[#editModeStates] == true, "global edit mode should unlock the interrupt tracker")
assert(ccEditModeStates[#ccEditModeStates] == true, "global edit mode should unlock the crowd control tracker")
assert(bloodlustEditModeStates[#bloodlustEditModeStates] == true, "global edit mode should unlock the bloodlust display")
addon:SetEditMode(false)

local opened = 0
addon.OpenSettings = function()
  opened = opened + 1
end

SlashCmdList["SUNDERINGTOOLS"]("")
SlashCmdList["SUNDERINGTOOLS"]("config")
assert(opened == 2, "default and explicit slash commands should open settings")
