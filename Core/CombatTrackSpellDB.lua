local SpellDB = {}

local trackedSpells = {}
local trackedSpellAliases = {}
local interruptBySpecID = {}
local primaryCrowdControlByClass = {}
local classCrowdControl = {}
local allCrowdControl = {}
local healerKeepsKick = {
  SHAMAN = true,
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
  ROGUE = 259,
  SHAMAN = 262,
  WARLOCK = 265,
  WARRIOR = 71,
}

local crowdControlClassOrder = {
  "WARRIOR",
  "PALADIN",
  "HUNTER",
  "ROGUE",
  "PRIEST",
  "SHAMAN",
  "MAGE",
  "WARLOCK",
  "MONK",
  "DRUID",
  "DEMONHUNTER",
  "EVOKER",
  "DEATHKNIGHT",
}

local function RegisterTrackedSpell(spellID, name, kind, data)
  local entry = trackedSpells[spellID]
  if not entry then
    entry = {
      spellID = spellID,
      name = name,
      kind = kind,
    }
    trackedSpells[spellID] = entry
  end

  if data then
    for key, value in pairs(data) do
      entry[key] = value
    end
  end

  return entry
end

local function RegisterInterruptSpec(specID, classToken, role, spellID, cd, name)
  local entry = {
    specID = specID,
    classToken = classToken,
    role = role,
    spellID = spellID,
    name = name,
    cd = cd,
    kind = "INT",
  }

  local trackedEntry = RegisterTrackedSpell(spellID, name, "INT", {
    classToken = classToken,
  })

  trackedEntry.variants = trackedEntry.variants or {}
  trackedEntry.variants[specID] = entry

  local sharedCD
  for _, variant in pairs(trackedEntry.variants) do
    if sharedCD == nil then
      sharedCD = variant.cd
    elseif sharedCD ~= variant.cd then
      sharedCD = nil
      break
    end
  end

  trackedEntry.cd = sharedCD
  interruptBySpecID[specID] = entry
end

local function RegisterTrackedSpellAlias(aliasSpellID, canonicalSpellID)
  trackedSpellAliases[aliasSpellID] = canonicalSpellID
end

local function GetFallbackInterruptSpecID(classToken, role)
  if not classToken then
    return nil
  end

  local normalizedRole = type(role) == "string" and string.upper(role) or ""
  if classToken == "SHAMAN" and normalizedRole == "HEALER" then
    return 264
  end

  return fallbackSpecByClass[classToken]
end

local function RegisterCrowdControl(classToken, spellID, name, cd, essential)
  if type(cd) ~= "number" or cd <= 0 then
    return nil
  end

  local entry = RegisterTrackedSpell(spellID, name, "CC", {
    cd = cd,
    essential = essential == true,
    classToken = classToken,
  })

  if essential then
    entry.essential = true
  end

  classCrowdControl[classToken] = classCrowdControl[classToken] or {}
  classCrowdControl[classToken][#classCrowdControl[classToken] + 1] = entry
  allCrowdControl[#allCrowdControl + 1] = entry

  if not primaryCrowdControlByClass[classToken] then
    primaryCrowdControlByClass[classToken] = entry
  elseif essential and not primaryCrowdControlByClass[classToken].essential then
    primaryCrowdControlByClass[classToken] = entry
  end

  return entry
end

RegisterInterruptSpec(250, "DEATHKNIGHT", "TANK", 47528, 15, "Mind Freeze")
RegisterInterruptSpec(251, "DEATHKNIGHT", "DAMAGER", 47528, 15, "Mind Freeze")
RegisterInterruptSpec(252, "DEATHKNIGHT", "DAMAGER", 47528, 15, "Mind Freeze")
RegisterTrackedSpellAlias(97493, 47528)
RegisterInterruptSpec(577, "DEMONHUNTER", "DAMAGER", 183752, 15, "Disrupt")
RegisterInterruptSpec(581, "DEMONHUNTER", "TANK", 183752, 15, "Disrupt")
RegisterInterruptSpec(1480, "DEMONHUNTER", "DAMAGER", 183752, 15, "Disrupt")
RegisterInterruptSpec(103, "DRUID", "DAMAGER", 106839, 15, "Skull Bash")
RegisterInterruptSpec(104, "DRUID", "TANK", 106839, 15, "Skull Bash")
RegisterInterruptSpec(1467, "EVOKER", "DAMAGER", 351338, 20, "Quell")
RegisterInterruptSpec(1473, "EVOKER", "DAMAGER", 351338, 18, "Quell")
RegisterInterruptSpec(253, "HUNTER", "DAMAGER", 147362, 24, "Counter Shot")
RegisterInterruptSpec(254, "HUNTER", "DAMAGER", 147362, 24, "Counter Shot")
RegisterInterruptSpec(255, "HUNTER", "DAMAGER", 187707, 15, "Muzzle")
RegisterInterruptSpec(62, "MAGE", "DAMAGER", 2139, 24, "Counterspell")
RegisterInterruptSpec(63, "MAGE", "DAMAGER", 2139, 24, "Counterspell")
RegisterInterruptSpec(64, "MAGE", "DAMAGER", 2139, 24, "Counterspell")
RegisterInterruptSpec(268, "MONK", "TANK", 116705, 15, "Spear Hand Strike")
RegisterInterruptSpec(269, "MONK", "DAMAGER", 116705, 15, "Spear Hand Strike")
RegisterInterruptSpec(66, "PALADIN", "TANK", 96231, 15, "Rebuke")
RegisterInterruptSpec(70, "PALADIN", "DAMAGER", 96231, 15, "Rebuke")
RegisterInterruptSpec(258, "PRIEST", "DAMAGER", 15487, 30, "Silence")
RegisterInterruptSpec(259, "ROGUE", "DAMAGER", 1766, 15, "Kick")
RegisterInterruptSpec(260, "ROGUE", "DAMAGER", 1766, 15, "Kick")
RegisterInterruptSpec(261, "ROGUE", "DAMAGER", 1766, 15, "Kick")
RegisterInterruptSpec(262, "SHAMAN", "DAMAGER", 57994, 12, "Wind Shear")
RegisterInterruptSpec(263, "SHAMAN", "DAMAGER", 57994, 12, "Wind Shear")
RegisterInterruptSpec(264, "SHAMAN", "HEALER", 57994, 30, "Wind Shear")
RegisterInterruptSpec(265, "WARLOCK", "DAMAGER", 19647, 24, "Spell Lock")
RegisterInterruptSpec(266, "WARLOCK", "DAMAGER", 19647, 24, "Spell Lock")
RegisterInterruptSpec(267, "WARLOCK", "DAMAGER", 19647, 24, "Spell Lock")
RegisterInterruptSpec(71, "WARRIOR", "DAMAGER", 6552, 15, "Pummel")
RegisterInterruptSpec(72, "WARRIOR", "DAMAGER", 6552, 15, "Pummel")
RegisterInterruptSpec(73, "WARRIOR", "TANK", 6552, 15, "Pummel")

local crowdControlSource = {
  WARRIOR = {
    { spellID = 5246, cd = 75, name = "Intimidating Shout", essential = true },
    { spellID = 12323, cd = 30, name = "Piercing Howl" },
    { spellID = 107570, cd = 30, name = "Storm Bolt" },
    { spellID = 46968, cd = 40, name = "Shockwave" },
  },
  PALADIN = {
    { spellID = 853, cd = 60, name = "Hammer of Justice", essential = true },
    { spellID = 20066, cd = 15, name = "Repentance" },
    { spellID = 115750, cd = 90, name = "Blinding Light" },
    { spellID = 255937, cd = 45, name = "Wake of Ashes" },
  },
  HUNTER = {
    { spellID = 187650, cd = 30, name = "Freezing Trap", essential = true },
    { spellID = 213691, cd = 30, name = "Scatter Shot" },
    { spellID = 24394, cd = 72, name = "Intimidation" },
    { spellID = 109248, cd = 45, name = "Binding Shot" },
    { spellID = 162480, cd = 30, name = "Steel Trap" },
  },
  ROGUE = {
    { spellID = 408, cd = 20, name = "Kidney Shot" },
    { spellID = 1776, cd = 15, name = "Gouge" },
    { spellID = 2094, cd = 120, name = "Blind", essential = true },
  },
  PRIEST = {
    { spellID = 8122, cd = 45, name = "Psychic Scream", essential = true },
    { spellID = 64044, cd = 45, name = "Psychic Horror" },
    { spellID = 88625, cd = 60, name = "Holy Word: Chastise" },
    { spellID = 108920, cd = 30, name = "Void Tendrils" },
  },
  SHAMAN = {
    { spellID = 51514, cd = 30, name = "Hex", essential = true },
    { spellID = 210873, cd = 30, name = "Hex (Compy)" },
    { spellID = 211004, cd = 30, name = "Hex (Snake)" },
    { spellID = 192058, cd = 60, name = "Capacitor Totem" },
    { spellID = 197214, cd = 20, name = "Sundering" },
    { spellID = 51485, cd = 30, name = "Earthgrab Totem" },
  },
  MAGE = {
    { spellID = 113724, cd = 45, name = "Ring of Frost", essential = true },
    { spellID = 31661, cd = 20, name = "Dragon's Breath" },
    { spellID = 122, cd = 30, name = "Frost Nova" },
    { spellID = 157997, cd = 25, name = "Ice Nova" },
  },
  WARLOCK = {
    { spellID = 30283, cd = 30, name = "Shadowfury", essential = true },
    { spellID = 5484, cd = 40, name = "Howl of Terror" },
    { spellID = 6789, cd = 45, name = "Mortal Coil" },
    { spellID = 89766, cd = 30, name = "Axe Toss" },
  },
  MONK = {
    { spellID = 115078, cd = 15, name = "Paralysis", essential = true },
    { spellID = 119381, cd = 60, name = "Leg Sweep" },
    { spellID = 198909, cd = 30, name = "Song of Chi-Ji" },
    { spellID = 116844, cd = 45, name = "Ring of Peace" },
  },
  DRUID = {
    { spellID = 5211, cd = 60, name = "Mighty Bash" },
    { spellID = 99, cd = 30, name = "Incapacitating Roar", essential = true },
    { spellID = 102359, cd = 30, name = "Mass Entanglement" },
  },
  DEMONHUNTER = {
    { spellID = 217832, cd = 15, name = "Imprison", essential = true },
    { spellID = 179057, cd = 60, name = "Chaos Nova" },
    { spellID = 207684, cd = 90, name = "Sigil of Misery" },
    { spellID = 202137, cd = 60, name = "Sigil of Silence" },
    { spellID = 370965, cd = 90, name = "The Hunt" },
  },
  EVOKER = {
    { spellID = 370665, cd = 30, name = "Oppressing Roar" },
    { spellID = 358385, cd = 30, name = "Landslide" },
  },
  DEATHKNIGHT = {
    { spellID = 108194, cd = 45, name = "Asphyxiate", essential = true },
    { spellID = 221562, cd = 45, name = "Asphyxiate" },
    { spellID = 207167, cd = 60, name = "Blinding Sleet" }
  },
}

for _, classToken in ipairs(crowdControlClassOrder) do
  local entries = crowdControlSource[classToken] or {}
  for _, entry in ipairs(entries) do
    RegisterCrowdControl(classToken, entry.spellID, entry.name, entry.cd, entry.essential)
  end
end

function SpellDB.GetTrackedSpell(spellID)
  return trackedSpells[trackedSpellAliases[spellID] or spellID]
end

function SpellDB.ResolveTrackedSpellID(spellID)
  return trackedSpellAliases[spellID] or spellID
end

function SpellDB.GetInterruptForSpec(specID)
  return interruptBySpecID[specID]
end

function SpellDB.GetInterruptForClass(classToken)
  local fallbackSpecID = classToken and fallbackSpecByClass[classToken]
  return fallbackSpecID and interruptBySpecID[fallbackSpecID] or nil
end

function SpellDB.ResolveInterrupt(specID, classToken)
  local interruptEntry = specID and interruptBySpecID[specID]
  if interruptEntry then
    return interruptEntry, specID
  end

  local fallbackSpecID = classToken and fallbackSpecByClass[classToken]
  if fallbackSpecID then
    return interruptBySpecID[fallbackSpecID], fallbackSpecID
  end

  return nil, 0
end

function SpellDB.ResolveInterruptByContext(specID, classToken, role, powerType)
  local interruptEntry = specID and interruptBySpecID[specID]
  if interruptEntry then
    return interruptEntry, specID, nil
  end

  local normalizedRole = type(role) == "string" and string.upper(role) or ""
  if classToken == "MONK" and powerType == 0 then
    return nil, 0, "HEALER_SUPPRESSED"
  end

  if normalizedRole == "HEALER" and not healerKeepsKick[classToken] then
    return nil, 0, "HEALER_SUPPRESSED"
  end

  local fallbackSpecID = GetFallbackInterruptSpecID(classToken, normalizedRole)
  if fallbackSpecID then
    return interruptBySpecID[fallbackSpecID], fallbackSpecID, nil
  end

  return nil, 0, "CLASS_OMITTED"
end

function SpellDB.ResolveAutoInterruptByContext(_specID, classToken, role, powerType)
  local normalizedRole = type(role) == "string" and string.upper(role) or ""
  if classToken == "MONK" and powerType == 0 then
    return nil, 0, "HEALER_SUPPRESSED"
  end

  if normalizedRole == "HEALER" and not healerKeepsKick[classToken] then
    return nil, 0, "HEALER_SUPPRESSED"
  end

  local fallbackSpecID = GetFallbackInterruptSpecID(classToken, normalizedRole)
  if fallbackSpecID then
    return interruptBySpecID[fallbackSpecID], fallbackSpecID, nil
  end

  return nil, 0, "CLASS_OMITTED"
end

function SpellDB.GetPrimaryCrowdControlForClass(classToken)
  return primaryCrowdControlByClass[classToken]
end

function SpellDB.GetCrowdControlForClass(classToken, _role)
  local entries = classCrowdControl[classToken] or {}
  local copy = {}

  for index, entry in ipairs(entries) do
    copy[index] = entry
  end

  return copy
end

function SpellDB.FilterCrowdControl(mode)
  local normalizedMode = type(mode) == "string" and string.upper(mode) or "ESSENTIALS"
  local filtered = {}

  for _, entry in ipairs(allCrowdControl) do
    if normalizedMode == "ALL" or entry.essential then
      filtered[#filtered + 1] = entry
    end
  end

  return filtered
end

_G.SunderingToolsCombatTrackSpellDB = SpellDB

return SpellDB
