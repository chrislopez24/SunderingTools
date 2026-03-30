local SpellDB = {}

local trackedSpells = {}
local trackedSpellAliases = {}
local interruptBySpecID = {}
local primaryCrowdControlByClass = {}
local classCrowdControl = {}
local allCrowdControl = {}
local defensiveSpells = {}
local defensiveSpellAliases = {}
local defensiveByClass = {}
local raidDefensiveByClass = {}
local healerKeepsKick = {
  SHAMAN = true,
}
local untrackableDefensiveSpells = {
  [114556] = true, -- Purgatory
  [209258] = true, -- Last Resort
  [377847] = true, -- Well-Honed Instincts
  [404381] = true, -- Defy Fate
  [86949] = true, -- Cauterize
  [215982] = true, -- Spirit of the Redeemer
  [391124] = true, -- Restitution
  [31230] = true, -- Cheat Death
  [30884] = true, -- Nature's Guardian
  [386394] = true, -- Battle-Scarred Veteran
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

local localCooldownTalentMods = {
  [48707] = {
    { talentID = 205727, delta = -20 }, -- Anti-Magic Barrier
  },
  [51052] = {
    { talentID = 374383, delta = -60 }, -- Assimilation
  },
  [102342] = {
    { talentID = 382552, delta = -20 }, -- Stonebark / Improved Ironbark
  },
  [31821] = {
    { talentID = 392911, delta = -30 }, -- Unwavering Spirit
  },
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

local function CopyTable(value)
  local copy = {}

  for key, field in pairs(value or {}) do
    copy[key] = field
  end

  return copy
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

local function RegisterDefensiveSpell(spellID, name, kind, data)
  local entry = RegisterTrackedSpell(spellID, name, kind, data)
  defensiveSpells[spellID] = entry

  if data and type(data.auraSpellID) == "number" and data.auraSpellID > 0 and data.auraSpellID ~= spellID then
    defensiveSpellAliases[data.auraSpellID] = spellID
  end

  local classToken = data and data.classToken
  if classToken then
    local target = defensiveByClass
    if kind == "RAID_DEF" then
      target = raidDefensiveByClass
    end

    if data.trackable ~= false then
      target[classToken] = target[classToken] or {}
      target[classToken][#target[classToken] + 1] = entry
    end
  end

  return entry
end

local function ResolveNumericVariant(value)
  if type(value) == "number" then
    return value, nil
  end

  if type(value) ~= "table" then
    return nil, nil
  end

  local defaultValue = rawget(value, "default")
  if type(defaultValue) == "number" then
    return defaultValue, value
  end

  local numericKeys = {}
  local fallbackValue

  for key, candidate in pairs(value) do
    if type(candidate) == "number" then
      fallbackValue = fallbackValue or candidate
      if type(key) == "number" then
        numericKeys[#numericKeys + 1] = key
      end
    end
  end

  if #numericKeys > 0 then
    table.sort(numericKeys)
    return value[numericKeys[1]], value
  end

  return fallbackValue, value
end

local function ResolveNumericForSpec(baseValue, bySpec, specID)
  if type(specID) == "number" and type(bySpec) == "table" then
    local variant = bySpec[specID]
    if type(variant) == "number" and variant > 0 then
      return variant
    end
  end

  return baseValue
end

local function BuildSpellSet(spellIDs)
  if type(spellIDs) ~= "table" then
    return nil
  end

  local spellSet = {}
  for _, spellID in ipairs(spellIDs) do
    spellSet[spellID] = true
  end

  return spellSet
end

local function ResolveDefensiveEntry(entry, specID, isKnownSpell)
  local resolved = CopyTable(entry)
  resolved.cd = ResolveNumericForSpec(entry.cd, entry.cdBySpec, specID)

  if entry.charges ~= nil or entry.chargesBySpec ~= nil then
    resolved.charges = ResolveNumericForSpec(entry.charges, entry.chargesBySpec, specID)
  end

  if type(isKnownSpell) == "function" and type(resolved.cd) == "number" and resolved.cd > 0 then
    for _, modifier in ipairs(entry.cooldownTalentMods or {}) do
      if type(modifier) == "table"
        and type(modifier.talentID) == "number"
        and type(modifier.delta) == "number"
        and isKnownSpell(modifier.talentID)
      then
        resolved.cd = math.max(0, resolved.cd + modifier.delta)
      end
    end
  end

  return resolved
end

local function CloneResolvedEntries(entries, specID, spellSet, isKnownSpell)
  local copy = {}

  for _, entry in ipairs(entries or {}) do
    if spellSet == nil or spellSet[entry.spellID] then
      copy[#copy + 1] = ResolveDefensiveEntry(entry, specID, isKnownSpell)
    end
  end

  return copy
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

local defensiveSource = {
  DEATHKNIGHT = {
    { spellID = 51052, name = "Anti-Magic Zone", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 240, auraSpellID = 145629, spec = true },
    { spellID = 48707, name = "Anti-Magic Shell", kind = "DEF", sourceType = "defensive", cd = 60, auraSpellID = 48707 },
    { spellID = 327574, name = "Sacrificial Pact", kind = "DEF", sourceType = "tankDefensive", cd = 120, auraSpellID = 327574, spec = true },
    { spellID = 48743, name = "Death Pact", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 48743, spec = true },
    { spellID = 48792, name = "Icebound Fortitude", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 48792, spec = true },
    { spellID = 114556, name = "Purgatory", kind = "DEF", sourceType = "tankDefensive", cd = 240, auraSpellID = 114556, spec = true },
    { spellID = 49028, name = "Dancing Rune Weapon", kind = "DEF", sourceType = "tankDefensive", cd = 120, auraSpellID = 81256, spec = true },
    { spellID = 219809, name = "Tombstone", kind = "DEF", sourceType = "tankDefensive", cd = 60, auraSpellID = 219809, spec = true },
    { spellID = 274156, name = "Consumption", kind = "DEF", sourceType = "tankDefensive", cd = 30, auraSpellID = 274156, spec = true },
    { spellID = 194679, name = "Rune Tap", kind = "DEF", sourceType = "tankDefensive", cd = 25, auraSpellID = 194679, charges = 2, spec = true },
    { spellID = 55233, name = "Vampiric Blood", kind = "DEF", sourceType = "tankDefensive", cd = 90, auraSpellID = 55233, spec = true },
  },
  DEMONHUNTER = {
    { spellID = 198589, name = "Blur", kind = "DEF", sourceType = "defensive", cd = 60, auraSpellID = 212800, spec = 577 },
    { spellID = 203720, name = "Demon Spikes", kind = "DEF", sourceType = "tankDefensive", cd = 20, auraSpellID = 203720, charges = 2, spec = 581 },
    { spellID = 187827, name = "Metamorphosis", kind = "DEF", sourceType = "tankDefensive", cd = 180, auraSpellID = 187827, spec = 581 },
    { spellID = 206803, name = "Rain from Above", kind = "DEF", sourceType = "defensive", cd = 90, auraSpellID = 206803, spec = true },
    { spellID = 204021, name = "Fiery Brand", kind = "DEF", sourceType = "tankDefensive", cd = 60, auraSpellID = 204021, charges = 1, spec = true },
    { spellID = 263648, name = "Soul Barrier", kind = "DEF", sourceType = "tankDefensive", cd = 30, auraSpellID = 263648, spec = true },
    { spellID = 209258, name = "Last Resort", kind = "DEF", sourceType = "tankDefensive", cd = 480, auraSpellID = 209258, spec = true },
    { spellID = 196718, name = "Darkness", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 300, auraSpellID = 209426, spec = true },
  },
  DRUID = {
    { spellID = 354654, name = "Grove Protection", kind = "DEF", sourceType = "tankDefensive", cd = 60, auraSpellID = 354654, spec = true },
    { spellID = 201664, name = "Demoralizing Roar", kind = "DEF", sourceType = "tankDefensive", cd = 30, auraSpellID = 201664, spec = true },
    { spellID = 22812, name = "Barkskin", kind = "DEF", sourceType = "defensive", cd = { [104] = 45, ["default"] = 60 }, auraSpellID = 22812 },
    { spellID = 740, name = "Tranquility", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 157982, spec = true },
    { spellID = 102342, name = "Ironbark", kind = "DEF", sourceType = "externalDefensive", cd = 90, auraSpellID = 102342, spec = true },
    { spellID = 61336, name = "Survival Instincts", kind = "DEF", sourceType = "defensive", cd = 180, auraSpellID = 61336, charges = 1, spec = true },
    { spellID = 200851, name = "Rage of the Sleeper", kind = "DEF", sourceType = "tankDefensive", cd = 60, auraSpellID = 200851, spec = true },
    { spellID = 80313, name = "Pulverize", kind = "DEF", sourceType = "tankDefensive", cd = 45, auraSpellID = 80313, spec = true },
    { spellID = 124974, name = "Nature's Vigil", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 90, auraSpellID = 124974, spec = true },
    { spellID = 377847, name = "Well-Honed Instincts", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 377847, spec = true },
  },
  EVOKER = {
    { spellID = 368412, name = "Time of Need", kind = "DEF", sourceType = "externalDefensive", cd = 60, auraSpellID = 368412, spec = true },
    { spellID = 363534, name = "Rewind", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 240, auraSpellID = 363534, charges = 1, spec = true },
    { spellID = 357170, name = "Time Dilation", kind = "DEF", sourceType = "externalDefensive", cd = 60, auraSpellID = 357170, spec = true },
    { spellID = 374348, name = "Renewing Blaze", kind = "DEF", sourceType = "defensive", cd = 90, auraSpellID = 374348, spec = true },
    { spellID = 374227, name = "Zephyr", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 120, auraSpellID = 374227, spec = true },
    { spellID = 363916, name = "Obsidian Scales", kind = "DEF", sourceType = "defensive", cd = 90, auraSpellID = 363916, charges = 1, spec = true },
    { spellID = 360827, name = "Blistering Scales", kind = "DEF", sourceType = "externalDefensive", cd = 30, auraSpellID = 360827, spec = true },
    { spellID = 404381, name = "Defy Fate", kind = "DEF", sourceType = "defensive", cd = 360, auraSpellID = 404381, spec = 404195 },
  },
  HUNTER = {
    { spellID = 53480, name = "Roar of Sacrifice", kind = "DEF", sourceType = "externalDefensive", cd = 60, auraSpellID = 53480, spec = true },
    { spellID = 264735, name = "Survival of the Fittest", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 264735, spec = true },
    { spellID = 472707, name = "Shell Cover", kind = "DEF", sourceType = "defensive", cd = 90, auraSpellID = 472708, spec = true },
  },
  MAGE = {
    { spellID = 110959, name = "Greater Invisibility", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 113862, spec = true },
    { spellID = 342245, name = "Alter Time", kind = "DEF", sourceType = "defensive", cd = 60, auraSpellID = 342246, spec = true },
    { spellID = 11426, name = "Ice Barrier", kind = "DEF", sourceType = "defensive", cd = 25, auraSpellID = 11426, spec = true },
    { spellID = 235313, name = "Blazing Barrier", kind = "DEF", sourceType = "defensive", cd = 25, auraSpellID = 235313, spec = true },
    { spellID = 235450, name = "Prismatic Barrier", kind = "DEF", sourceType = "defensive", cd = 25, auraSpellID = 235450, spec = true },
    { spellID = 55342, name = "Mirror Image", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 55342, spec = true },
    { spellID = 414660, name = "Mass Barrier", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 414660, spec = true },
    { spellID = 86949, name = "Cauterize", kind = "DEF", sourceType = "defensive", cd = 300, auraSpellID = 86949, spec = 63 },
    { spellID = 235219, name = "Cold Snap", kind = "DEF", sourceType = "defensive", cd = 300, auraSpellID = 235219, spec = 64 },
    { spellID = 414658, name = "Ice Cold", kind = "DEF", sourceType = "defensive", cd = 240, auraSpellID = 414658, spec = 414659 },
  },
  MONK = {
    { spellID = 202162, name = "Avert Harm", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 45, auraSpellID = 202162, spec = true },
    { spellID = 388615, name = "Restoral", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 388615, charges = 1, spec = true },
    { spellID = 115310, name = "Revival", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 115310, charges = 1, spec = true },
    { spellID = 116849, name = "Life Cocoon", kind = "DEF", sourceType = "externalDefensive", cd = 120, auraSpellID = 116849, spec = true },
    { spellID = 122470, name = "Touch of Karma", kind = "DEF", sourceType = "defensive", cd = 90, auraSpellID = 125174, spec = 269 },
    { spellID = 322507, name = "Celestial Brew", kind = "DEF", sourceType = "tankDefensive", cd = 45, auraSpellID = 322507, spec = true },
    { spellID = 1241059, name = "Celestial Infusion", kind = "DEF", sourceType = "tankDefensive", cd = 45, auraSpellID = 1241059, spec = true },
    { spellID = 115203, name = "Fortifying Brew", kind = "DEF", sourceType = "defensive", cd = { [268] = 360, ["default"] = 120 }, auraSpellID = 120954, spec = true },
    { spellID = 122783, name = "Diffuse Magic", kind = "DEF", sourceType = "defensive", cd = 90, auraSpellID = 122783, spec = true },
    { spellID = 122278, name = "Dampen Harm", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 122278, spec = true },
    { spellID = 132578, name = "Invoke Niuzao, the Black Ox", kind = "DEF", sourceType = "tankDefensive", cd = 180, auraSpellID = 132578, spec = true },
    { spellID = 115176, name = "Zen Meditation", kind = "DEF", sourceType = "defensive", cd = 300, auraSpellID = 115176, spec = true },
    { spellID = 119582, name = "Purifying Brew", kind = "DEF", sourceType = "tankDefensive", cd = 20, auraSpellID = 119582, charges = 2, spec = true },
  },
  PALADIN = {
    { spellID = 199448, name = "Ultimate Sacrifice", kind = "DEF", sourceType = "externalDefensive", cd = 120, auraSpellID = 199448, spec = 199452 },
    { spellID = 403876, name = "Divine Protection", kind = "DEF", sourceType = "defensive", cd = 90, auraSpellID = 403876, spec = 70 },
    { spellID = 498, name = "Divine Protection", kind = "DEF", sourceType = "defensive", cd = 60, auraSpellID = 498, spec = 65 },
    { spellID = 31850, name = "Ardent Defender", kind = "DEF", sourceType = "tankDefensive", cd = 120, auraSpellID = 31850, spec = true },
    { spellID = 378279, name = "Gift of the Golden Val'kyr", kind = "DEF", sourceType = "tankDefensive", cd = 45, auraSpellID = 378279, spec = true },
    { spellID = 86659, name = "Guardian of Ancient Kings", kind = "DEF", sourceType = "tankDefensive", cd = 300, auraSpellID = 86659, spec = true, talent = 228049 },
    { spellID = 387174, name = "Eye of Tyr", kind = "DEF", sourceType = "tankDefensive", cd = 60, auraSpellID = 387174, spec = true },
    { spellID = 327193, name = "Moment of Glory", kind = "DEF", sourceType = "tankDefensive", cd = 90, auraSpellID = 327193, spec = true },
    { spellID = 184662, name = "Shield of Vengeance", kind = "DEF", sourceType = "defensive", cd = 90, auraSpellID = 184662, spec = true },
    { spellID = 148039, name = "Barrier of Faith", kind = "DEF", sourceType = "externalDefensive", cd = 30, auraSpellID = 148039, spec = true },
    { spellID = 31821, name = "Aura Mastery", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 31821, spec = true },
    { spellID = 6940, name = "Blessing of Sacrifice", kind = "DEF", sourceType = "externalDefensive", cd = 120, auraSpellID = 6940, charges = 1, spec = true, talent = 199452 },
    { spellID = 1022, name = "Blessing of Protection", kind = "DEF", sourceType = "externalDefensive", cd = 300, auraSpellID = 1022, charges = 1, spec = true },
    { spellID = 204018, name = "Blessing of Spellwarding", kind = "DEF", sourceType = "externalDefensive", cd = 300, auraSpellID = 204018, charges = 1, spec = true },
    { spellID = 432472, name = "Holy Bulwark", kind = "DEF", sourceType = "externalDefensive", cd = 60, auraSpellID = 432496, charges = 2, spec = 432459 },
  },
  PRIEST = {
    { spellID = 215982, name = "Spirit of the Redeemer", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 215769, spec = 215982 },
    { spellID = 328530, name = "Divine Ascension", kind = "DEF", sourceType = "defensive", cd = 60, auraSpellID = 328530, spec = true },
    { spellID = 197268, name = "Ray of Hope", kind = "DEF", sourceType = "externalDefensive", cd = 90, auraSpellID = 197268, spec = true },
    { spellID = 62618, name = "Power Word: Barrier", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 81782, spec = true },
    { spellID = 33206, name = "Pain Suppression", kind = "DEF", sourceType = "externalDefensive", cd = 180, auraSpellID = 33206, spec = true },
    { spellID = 391124, name = "Restitution", kind = "DEF", sourceType = "defensive", cd = 600, auraSpellID = 391124, spec = true },
    { spellID = 64843, name = "Divine Hymn", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 64843, spec = true },
    { spellID = 47788, name = "Guardian Spirit", kind = "DEF", sourceType = "externalDefensive", cd = 180, auraSpellID = 47788, spec = true },
    { spellID = 47585, name = "Dispersion", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 47585, spec = true },
    { spellID = 108968, name = "Void Shift", kind = "DEF", sourceType = "externalDefensive", cd = 300, auraSpellID = 108968, spec = true },
    { spellID = 15286, name = "Vampiric Embrace", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 120, auraSpellID = 15286, spec = true },
    { spellID = 271466, name = "Luminous Barrier", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 271466, spec = true },
  },
  ROGUE = {
    { spellID = 1856, name = "Vanish", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 11327 },
    { spellID = 1966, name = "Feint", kind = "DEF", sourceType = "defensive", cd = 15, auraSpellID = 1966 },
    { spellID = 31224, name = "Cloak of Shadows", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 31224, spec = true },
    { spellID = 31230, name = "Cheat Death", kind = "DEF", sourceType = "defensive", cd = 360, auraSpellID = 31230, spec = true },
    { spellID = 5277, name = "Evasion", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 5277, spec = true },
  },
  SHAMAN = {
    { spellID = 204331, name = "Counterstrike Totem", kind = "DEF", sourceType = "defensive", cd = 45, auraSpellID = 204331, spec = true },
    { spellID = 108280, name = "Healing Tide Totem", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 108280, spec = true },
    { spellID = 98008, name = "Spirit Link Totem", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 98008, charges = 1, spec = true },
    { spellID = 198838, name = "Earthen Wall Totem", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 60, auraSpellID = 198838, spec = true },
    { spellID = 207399, name = "Ancestral Protection Totem", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 300, auraSpellID = 207399, spec = true },
    { spellID = 108271, name = "Astral Shift", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 108271, spec = true },
    { spellID = 198103, name = "Earth Elemental", kind = "DEF", sourceType = "defensive", cd = 300, auraSpellID = 198103, spec = true },
    { spellID = 30884, name = "Nature's Guardian", kind = "DEF", sourceType = "defensive", cd = 45, auraSpellID = 30884, spec = true },
    { spellID = 108270, name = "Stone Bulwark Totem", kind = "DEF", sourceType = "defensive", cd = 180, auraSpellID = 108270, spec = true },
  },
  WARLOCK = {
    { spellID = 104773, name = "Unending Resolve", kind = "DEF", sourceType = "defensive", cd = 180, auraSpellID = 104773 },
    { spellID = 108416, name = "Dark Pact", kind = "DEF", sourceType = "defensive", cd = 60, auraSpellID = 108416, spec = true },
  },
  WARRIOR = {
    { spellID = 2565, name = "Shield Block", kind = "DEF", sourceType = "tankDefensive", cd = 16, auraSpellID = 132404, charges = { [73] = 2, ["default"] = 1 } },
    { spellID = 236273, name = "Duel", kind = "DEF", sourceType = "externalDefensive", cd = 60, auraSpellID = 236273, spec = true },
    { spellID = 213871, name = "Bodyguard", kind = "DEF", sourceType = "externalDefensive", cd = 15, auraSpellID = 213871, spec = true },
    { spellID = 118038, name = "Die by the Sword", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 118038, spec = true },
    { spellID = 12975, name = "Last Stand", kind = "DEF", sourceType = "tankDefensive", cd = 180, auraSpellID = 12975, spec = true },
    { spellID = 1160, name = "Demoralizing Shout", kind = "DEF", sourceType = "tankDefensive", cd = 45, auraSpellID = 1160, spec = true },
    { spellID = 871, name = "Shield Wall", kind = "DEF", sourceType = "tankDefensive", cd = 180, auraSpellID = 871, charges = 1, spec = true },
    { spellID = 97462, name = "Rallying Cry", kind = "RAID_DEF", sourceType = "raidDefensive", cd = 180, auraSpellID = 97463, spec = true },
    { spellID = 184364, name = "Enraged Regeneration", kind = "DEF", sourceType = "defensive", cd = 120, auraSpellID = 184364, spec = true },
    { spellID = 386394, name = "Battle-Scarred Veteran", kind = "DEF", sourceType = "tankDefensive", cd = 180, auraSpellID = 386394, spec = true },
  },
}

for classToken, entries in pairs(defensiveSource) do
  for _, sourceEntry in ipairs(entries) do
    local cooldown, cooldownBySpec = ResolveNumericVariant(sourceEntry.cd)
    if type(cooldown) == "number" and cooldown > 0 then
      local charges, chargesBySpec = ResolveNumericVariant(sourceEntry.charges)
      local data = {
        classToken = classToken,
        cd = cooldown,
        auraSpellID = sourceEntry.auraSpellID,
        cooldownTalentMods = localCooldownTalentMods[sourceEntry.spellID],
        sourceType = sourceEntry.sourceType,
        trackable = not untrackableDefensiveSpells[sourceEntry.spellID],
        spec = sourceEntry.spec,
        talent = sourceEntry.talent,
        disabledSpec = sourceEntry.disabledSpec,
      }

      if cooldownBySpec then
        data.cdBySpec = cooldownBySpec
      end

      if type(charges) == "number" and charges > 0 then
        data.charges = charges
      end

      if chargesBySpec then
        data.chargesBySpec = chargesBySpec
      end

      RegisterDefensiveSpell(sourceEntry.spellID, sourceEntry.name, sourceEntry.kind, data)
    end
  end
end

function SpellDB.GetTrackedSpell(spellID)
  return trackedSpells[trackedSpellAliases[spellID] or spellID]
end

function SpellDB.GetDefensiveSpell(spellID)
  local canonicalSpellID = trackedSpellAliases[spellID] or defensiveSpellAliases[spellID] or spellID
  return defensiveSpells[canonicalSpellID]
end

function SpellDB.GetDefensiveSpellsForClass(classToken)
  local entries = defensiveByClass[classToken] or {}
  return CloneResolvedEntries(entries)
end

function SpellDB.GetResolvedDefensiveSpellsForClass(classToken, specID)
  local entries = defensiveByClass[classToken] or {}
  return CloneResolvedEntries(entries, specID)
end

function SpellDB.GetKnownDefensiveSpellsForClass(classToken, specID, spellIDs)
  local entries = defensiveByClass[classToken] or {}
  return CloneResolvedEntries(entries, specID, BuildSpellSet(spellIDs))
end

function SpellDB.GetLocallyKnownDefensiveSpellsForClass(classToken, specID, isKnownSpell)
  local entries = defensiveByClass[classToken] or {}
  local copy = {}

  if type(isKnownSpell) ~= "function" then
    return copy
  end

  for _, entry in ipairs(entries) do
    if isKnownSpell(entry.spellID) then
      copy[#copy + 1] = ResolveDefensiveEntry(entry, specID, isKnownSpell)
    end
  end

  return copy
end

function SpellDB.GetRaidDefensiveSpellsForClass(classToken)
  local entries = raidDefensiveByClass[classToken] or {}
  return CloneResolvedEntries(entries)
end

function SpellDB.GetResolvedRaidDefensiveSpellsForClass(classToken, specID)
  local entries = raidDefensiveByClass[classToken] or {}
  return CloneResolvedEntries(entries, specID)
end

function SpellDB.GetKnownRaidDefensiveSpellsForClass(classToken, specID, spellIDs)
  local entries = raidDefensiveByClass[classToken] or {}
  return CloneResolvedEntries(entries, specID, BuildSpellSet(spellIDs))
end

function SpellDB.GetLocallyKnownRaidDefensiveSpellsForClass(classToken, specID, isKnownSpell)
  local entries = raidDefensiveByClass[classToken] or {}
  local copy = {}

  if type(isKnownSpell) ~= "function" then
    return copy
  end

  for _, entry in ipairs(entries) do
    if isKnownSpell(entry.spellID) then
      copy[#copy + 1] = ResolveDefensiveEntry(entry, specID, isKnownSpell)
    end
  end

  return copy
end

function SpellDB.ResolveDefensiveSpell(spellID, specID)
  local entry = SpellDB.GetDefensiveSpell(spellID)
  if not entry then
    return nil
  end

  return ResolveDefensiveEntry(entry, specID)
end

function SpellDB.ResolveLocalDefensiveSpell(spellID, specID, isKnownSpell)
  local entry = SpellDB.GetDefensiveSpell(spellID)
  if not entry then
    return nil
  end

  return ResolveDefensiveEntry(entry, specID, isKnownSpell)
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
