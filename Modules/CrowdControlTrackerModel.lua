local SpellDB = assert(
  _G.SunderingToolsCombatTrackSpellDB,
  "SunderingToolsCombatTrackSpellDB must load before CrowdControlTrackerModel.lua"
)

local Model = {}

local defaultPosition = {
  x = 220,
  y = -200,
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

function Model.GetDefaultPosition()
  return defaultPosition.x, defaultPosition.y
end

function Model.GetDefaultFilterMode()
  return "ESSENTIALS"
end

function Model.GetClassColor(classToken)
  return classColors[classToken] or { 0.5, 0.5, 0.5 }
end

function Model.FormatTimerText(remaining)
  return string.format("%.0fs", remaining)
end

function Model.NormalizeFilterMode(filterMode)
  if type(filterMode) ~= "string" then
    return Model.GetDefaultFilterMode()
  end

  local normalized = string.upper(filterMode)
  if normalized == "ALL" then
    return "ALL"
  end

  return Model.GetDefaultFilterMode()
end

function Model.BuildPreviewBars()
  return {
    {
      key = "cc-paladin-ready",
      name = "Hammer of Justice",
      class = "PALADIN",
      kind = "CC",
      spellID = 853,
      essential = true,
      previewText = "Ready",
      previewValue = 1,
      cd = 60,
      previewRemaining = 0,
    },
    {
      key = "cc-shaman-cooling",
      name = "Hex",
      class = "SHAMAN",
      kind = "CC",
      spellID = 51514,
      essential = true,
      previewText = "22",
      previewValue = 0.3,
      cd = 30,
      previewRemaining = 22,
    },
    {
      key = "cc-mage-optional",
      name = "Ring of Frost",
      class = "MAGE",
      kind = "CC",
      spellID = 113724,
      essential = false,
      previewText = "35",
      previewValue = 0.2,
      cd = 45,
      previewRemaining = 35,
    },
  }
end

function Model.FilterTrackedEntries(entries, filterMode)
  local filtered = {}
  local normalizedMode = Model.NormalizeFilterMode(filterMode)

  for _, entry in ipairs(entries or {}) do
    if entry.kind == "CC" and (normalizedMode == "ALL" or entry.essential == true) then
      filtered[#filtered + 1] = entry
    end
  end

  return filtered
end

function Model.GetEligibleCrowdControlEntries(classToken, options)
  options = options or {}

  if not classToken then
    return {}
  end

  if options.includeAllKnown then
    local entries = {}
    local isSpellKnown = options.isSpellKnown

    for _, entry in ipairs(SpellDB.GetCrowdControlForClass(classToken) or {}) do
      if type(isSpellKnown) ~= "function" or isSpellKnown(entry.spellID) then
        entries[#entries + 1] = entry
      end
    end

    return entries
  end

  local primary = SpellDB.GetPrimaryCrowdControlForClass(classToken)
  if not primary then
    return {}
  end

  return { primary }
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

function Model.GetAvailableSpells(filterMode)
  return SpellDB.FilterCrowdControl(Model.NormalizeFilterMode(filterMode))
end

_G.SunderingToolsCrowdControlTrackerModel = Model

return Model
