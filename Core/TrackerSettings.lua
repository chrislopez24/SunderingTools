local TrackerSettings = {}

local sharedBarConfigKeys = {
  enabled = true,
  posX = true,
  posY = true,
  positionMode = true,
  previewWhenSolo = true,
  maxBars = true,
  growDirection = true,
  spacing = true,
  iconSize = true,
  barWidth = true,
  barHeight = true,
  fontSize = true,
  showHeader = true,
  showInDungeon = true,
  showInWorld = true,
  hideOutOfCombat = true,
  showReady = true,
  tooltipOnHover = true,
}

local obsoleteBarConfigKeys = {
  showInRaid = true,
  showInArena = true,
  syncEnabled = true,
  strictSyncMode = true,
}

function TrackerSettings.CreateBarDefaults(defaultPosX, defaultPosY, overrides)
  local defaults = {
    enabled = true,
    posX = defaultPosX,
    posY = defaultPosY,
    positionMode = "CENTER_OFFSET",
    previewWhenSolo = true,
    maxBars = 5,
    growDirection = "DOWN",
    spacing = 0,
    iconSize = 18,
    barWidth = 175,
    barHeight = 18,
    fontSize = 11,
    showHeader = true,
    showInDungeon = true,
    showInWorld = true,
    hideOutOfCombat = false,
    showReady = true,
    tooltipOnHover = true,
  }

  for key, value in pairs(overrides or {}) do
    defaults[key] = value
  end

  return defaults
end

function TrackerSettings.IsBarContextAllowed(moduleDB)
  if not moduleDB or not moduleDB.enabled then
    return false
  end

  local _, instanceType = GetInstanceInfo()
  if instanceType == "party" then
    return moduleDB.showInDungeon ~= false
  end
  if instanceType == "raid" or instanceType == "arena" then
    return false
  end

  return moduleDB.showInWorld ~= false
end

function TrackerSettings.IsSharedBarConfigKey(key)
  return sharedBarConfigKeys[key] == true
end

function TrackerSettings.SanitizeBarConfig(moduleDB)
  if type(moduleDB) ~= "table" then
    return moduleDB
  end

  for key in pairs(obsoleteBarConfigKeys) do
    moduleDB[key] = nil
  end

  return moduleDB
end

_G.SunderingToolsTrackerSettings = TrackerSettings

return TrackerSettings
