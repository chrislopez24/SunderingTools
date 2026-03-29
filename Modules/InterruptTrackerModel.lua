local Model = {}

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

local interruptData = {
  [250] = { spellID = 47528, cd = 12, role = "TANK" },
  [251] = { spellID = 47528, cd = 12, role = "DAMAGER" },
  [252] = { spellID = 47528, cd = 12, role = "DAMAGER" },
  [577] = { spellID = 183752, cd = 15, role = "DAMAGER" },
  [581] = { spellID = 183752, cd = 15, role = "TANK" },
  [1480] = { spellID = 183752, cd = 15, role = "DAMAGER" },
  [103] = { spellID = 106839, cd = 15, role = "DAMAGER" },
  [104] = { spellID = 106839, cd = 15, role = "TANK" },
  [1467] = { spellID = 351338, cd = 20, role = "DAMAGER" },
  [1473] = { spellID = 351338, cd = 18, role = "DAMAGER" },
  [253] = { spellID = 147362, cd = 24, role = "DAMAGER" },
  [254] = { spellID = 147362, cd = 24, role = "DAMAGER" },
  [255] = { spellID = 187707, cd = 15, role = "DAMAGER" },
  [62] = { spellID = 2139, cd = 20, role = "DAMAGER" },
  [63] = { spellID = 2139, cd = 20, role = "DAMAGER" },
  [64] = { spellID = 2139, cd = 20, role = "DAMAGER" },
  [268] = { spellID = 116705, cd = 15, role = "TANK" },
  [269] = { spellID = 116705, cd = 15, role = "DAMAGER" },
  [66] = { spellID = 96231, cd = 15, role = "TANK" },
  [70] = { spellID = 96231, cd = 15, role = "DAMAGER" },
  [258] = { spellID = 15487, cd = 30, role = "DAMAGER" },
  [259] = { spellID = 1766, cd = 15, role = "DAMAGER" },
  [260] = { spellID = 1766, cd = 15, role = "DAMAGER" },
  [261] = { spellID = 1766, cd = 15, role = "DAMAGER" },
  [262] = { spellID = 57994, cd = 12, role = "DAMAGER" },
  [263] = { spellID = 57994, cd = 12, role = "DAMAGER" },
  [264] = { spellID = 57994, cd = 30, role = "HEALER" },
  [265] = { spellID = 19647, cd = 24, role = "DAMAGER" },
  [266] = { spellID = 19647, cd = 30, role = "DAMAGER" },
  [267] = { spellID = 19647, cd = 24, role = "DAMAGER" },
  [71] = { spellID = 6552, cd = 15, role = "DAMAGER" },
  [72] = { spellID = 6552, cd = 15, role = "DAMAGER" },
  [73] = { spellID = 6552, cd = 15, role = "TANK" },
}

local fallbackSpecByClass = {
  DEATHKNIGHT = 250,
  DEMONHUNTER = 577,
  DRUID = 103,
  EVOKER = 1467,
  HUNTER = 253,
  MAGE = 62,
  MONK = 268,
  PALADIN = 66,
  PRIEST = 258,
  ROGUE = 259,
  SHAMAN = 262,
  WARLOCK = 265,
  WARRIOR = 71,
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
  if specID and interruptData[specID] then
    return interruptData[specID], specID
  end

  local fallbackSpecID = classToken and fallbackSpecByClass[classToken]
  if fallbackSpecID then
    return interruptData[fallbackSpecID], fallbackSpecID
  end

  return nil, 0
end

function Model.GetClassColor(classToken)
  return classColors[classToken] or { 0.5, 0.5, 0.5 }
end

function Model.GetDefaultPosition()
  return defaultPosition.x, defaultPosition.y
end

function Model.FormatTimerText(remaining)
  if remaining > 6 then
    local displayValue = math.floor(remaining)
    return string.format("%d", displayValue), displayValue
  end

  local displayValue = math.floor(remaining * 10)
  return string.format("%.1f", remaining), displayValue
end

function Model.BuildPreviewBars()
  return {
    { key = "tank-ready", name = "TankKick", role = "TANK", text = "Ready", value = 1 },
    { key = "melee", name = "MeleeKick", role = "DAMAGER", text = "7.4", value = 0.45 },
    { key = "ranged", name = "RangedKick", role = "DAMAGER", text = "13", value = 0.2 },
  }
end

_G.SunderingToolsInterruptTrackerModel = Model

return Model
