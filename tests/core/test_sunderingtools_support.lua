local function stubFrame()
  return {
    RegisterEvent = function() end,
    SetScript = function() end,
  }
end

local function loadAddon()
  _G.SunderingTools = nil
  _G.SunderingToolsConfig = nil
  _G.SunderingToolsRegistry = nil
  _G.SunderingToolsSettingsModel = nil
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
  global = { minimap = { hide = false }, editMode = false },
  modules = { InterruptTracker = {} },
}

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

local iconShown = 0
addon.minimapIcon = {
  Show = function(_, name)
    assert(name == "SunderingTools", "libdbicon should show the addon entry")
    iconShown = iconShown + 1
  end,
  Hide = function() end,
}

addon:SetMinimapVisible(true)
assert(addon.db.global.minimap.hide == false, "showing the minimap button should update saved state")
assert(shown == 1, "native minimap button should show when enabled")
assert(iconShown == 1, "libdbicon should show when enabled")

assert(addon:CanOpenEditMode() == false, "edit mode should be unavailable without module support")
addon.InterruptTracker = {
  SetEditMode = function() end,
}
assert(addon:CanOpenEditMode() == true, "edit mode should be available when the module exposes support")
