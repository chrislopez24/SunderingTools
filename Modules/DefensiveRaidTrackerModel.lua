local SpellDB = assert(
  _G.SunderingToolsCombatTrackSpellDB,
  "SunderingToolsCombatTrackSpellDB must load before DefensiveRaidTrackerModel.lua"
)

local Model = {}

local defaultPosition = {
  x = 0,
  y = -260,
}

local classColors = {
  WARRIOR = { 0.78, 0.61, 0.43 },
  PALADIN = { 0.96, 0.55, 0.73 },
  HUNTER = { 0.67, 0.83, 0.45 },
  ROGUE = { 1, 0.96, 0.41 },
  PRIEST = { 1, 1, 1 },
  DEATHKNIGHT = { 0.77, 0.12, 0.23 },
  SHAMAN = { 0, 0.44, 0.87 },
  MAGE = { 0.25, 0.78, 0.92 },
  WARLOCK = { 0.53, 0.53, 0.93 },
  MONK = { 0, 1, 0.6 },
  DRUID = { 1, 0.49, 0.04 },
  DEMONHUNTER = { 0.64, 0.19, 0.79 },
  EVOKER = { 0.2, 0.58, 0.5 },
}

local function cloneEntry(entry)
  local copy = {}
  for key, value in pairs(entry or {}) do
    copy[key] = value
  end
  return copy
end

function Model.GetDefaultPosition()
  return defaultPosition.x, defaultPosition.y
end

function Model.GetClassColor(classToken)
  return classColors[classToken] or { 0.5, 0.5, 0.5 }
end

function Model.FormatTimerText(remaining)
  return string.format("%.0fs", remaining), math.floor(remaining + 0.5)
end

function Model.GetAvailableSpells(classToken)
  if not classToken then
    return {}
  end

  return SpellDB.GetRaidDefensiveSpellsForClass(classToken)
end

function Model.BuildPreviewBars()
  local available = Model.GetAvailableSpells("DEATHKNIGHT")
  local sample = cloneEntry(available[1])

  if not sample.spellID then
    sample = {
      spellID = 51052,
      name = "Anti-Magic Zone",
      classToken = "DEATHKNIGHT",
      kind = "RAID_DEF",
      cd = 120,
    }
  end

  local preview = {
    {
      key = "raid-def-preview-ready",
      name = "Kryos",
      spellName = sample.name,
      class = sample.classToken,
      kind = "RAID_DEF",
      spellID = sample.spellID,
      cd = sample.cd,
      previewText = "Ready",
      previewValue = 1,
      previewRemaining = 0,
    },
    {
      key = "raid-def-preview-mid",
      name = "Vex",
      spellName = sample.name,
      class = sample.classToken,
      kind = "RAID_DEF",
      spellID = sample.spellID,
      cd = sample.cd,
      previewText = "32s",
      previewValue = 0.74,
      previewRemaining = 32,
    },
    {
      key = "raid-def-preview-late",
      name = "Aeryn",
      spellName = sample.name,
      class = sample.classToken,
      kind = "RAID_DEF",
      spellID = sample.spellID,
      cd = sample.cd,
      previewText = "76s",
      previewValue = 0.37,
      previewRemaining = 76,
    },
  }

  return preview
end

function Model.SortBars(entries, now)
  table.sort(entries, function(a, b)
    local aRemaining = math.max(0, (a.cd or 0) - ((now or 0) - (a.startTime or 0)))
    local bRemaining = math.max(0, (b.cd or 0) - ((now or 0) - (b.startTime or 0)))
    local aReady = (a.startTime or 0) <= 0 or aRemaining <= 0
    local bReady = (b.startTime or 0) <= 0 or bRemaining <= 0

    if aReady ~= bReady then
      return not aReady
    end

    if not aReady and aRemaining ~= bRemaining then
      return aRemaining > bRemaining
    end

    if (a.name or "") ~= (b.name or "") then
      return (a.name or "") < (b.name or "")
    end

    return (a.key or "") < (b.key or "")
  end)

  return entries
end

_G.SunderingToolsDefensiveRaidTrackerModel = Model

return Model
