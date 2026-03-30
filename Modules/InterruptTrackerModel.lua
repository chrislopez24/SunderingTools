local Model = {}
local SpellDB = assert(
  _G.SunderingToolsCombatTrackSpellDB,
  "SunderingToolsCombatTrackSpellDB must load before InterruptTrackerModel.lua"
)

local rolePriority = {
  TANK = 1,
  HEALER = 2,
  DAMAGER = 3,
}

local defaultPosition = {
  x = 0,
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

local function IsReady(bar, now)
  local startTime = bar.startTime or 0
  local cd = bar.cd or 0
  return startTime == 0 or (now - startTime) >= cd
end

local function Remaining(bar, now)
  local startTime = bar.startTime or 0
  local cd = bar.cd or 0
  return cd - (now - startTime)
end

function Model.SortBars(bars, now)
  table.sort(bars, function(a, b)
    local aReady = IsReady(a, now)
    local bReady = IsReady(b, now)

    if aReady ~= bReady then
      return aReady
    end

    if aReady and bReady then
      local aPriority = rolePriority[a.role] or 9
      local bPriority = rolePriority[b.role] or 9
      if aPriority ~= bPriority then
        return aPriority < bPriority
      end
    else
      local aRemaining = Remaining(a, now)
      local bRemaining = Remaining(b, now)
      if aRemaining ~= bRemaining then
        return aRemaining < bRemaining
      end
    end

    return (a.key or a.name or "") < (b.key or b.name or "")
  end)

  return bars
end

function Model.GetInterruptData(specID, classToken)
  return SpellDB.ResolveInterrupt(specID, classToken)
end

function Model.GetClassColor(classToken)
  return classColors[classToken] or { 0.5, 0.5, 0.5 }
end

function Model.GetDefaultPosition()
  return defaultPosition.x, defaultPosition.y
end

function Model.FormatTimerText(remaining)
  return string.format("%.0fs", remaining), math.floor(remaining + 0.5)
end

function Model.BuildPreviewBars()
  return {
    {
      key = "tank-ready",
      name = "TankKick",
      class = "PALADIN",
      role = "TANK",
      spellID = 96231,
      previewText = "Ready",
      previewValue = 1,
      cd = 15,
      previewRemaining = 0,
    },
    {
      key = "melee",
      name = "MeleeKick",
      class = "ROGUE",
      role = "DAMAGER",
      spellID = 1766,
      previewText = "7.4",
      previewValue = 0.45,
      cd = 15,
      previewRemaining = 7.4,
    },
    {
      key = "ranged",
      name = "RangedKick",
      class = "MAGE",
      role = "DAMAGER",
      spellID = 2139,
      previewText = "13",
      previewValue = 0.2,
      cd = 20,
      previewRemaining = 13,
    },
  }
end

_G.SunderingToolsInterruptTrackerModel = Model

return Model
