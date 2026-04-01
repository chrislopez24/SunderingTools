local WatcherModule = dofile("Core/UnitAuraStateWatcher.lua")

local secretSpellID = {}
local secretName = {}
local secretIcon = {}
local secretFlag = {}
local secretSourceUnit = {}

local auraByFilter = {}
local durationByAuraInstanceID = {}
local hiddenByFilter = {}
local dispelColorCalls = {}

local function newFrame()
  return {
    events = {},
    scripts = {},
    RegisterUnitEvent = function(self, event, unit)
      self.events[#self.events + 1] = { event, unit }
    end,
    RegisterEvent = function(self, event)
      self.events[#self.events + 1] = event
    end,
    UnregisterAllEvents = function(self)
      self.events = {}
    end,
    SetScript = function(self, name, fn)
      self.scripts[name] = fn
    end,
  }
end

_G.CreateFrame = function()
  return newFrame()
end

_G.UnitExists = function(unit)
  return unit == "party1"
end

_G.UnitIsDeadOrGhost = function()
  return false
end

_G.issecretvalue = function(value)
  return value == secretSpellID
    or value == secretName
    or value == secretIcon
    or value == secretFlag
    or value == secretSourceUnit
end

_G.Enum = {
  UnitAuraSortRule = { Unsorted = 0 },
  UnitAuraSortDirection = { Normal = 0 },
  LuaCurveType = { Step = 1 },
}

_G.DEBUFF_TYPE_NONE_COLOR = { r = 0.9, g = 0.9, b = 0.9 }
_G.DEBUFF_TYPE_MAGIC_COLOR = { r = 0.2, g = 0.6, b = 1.0 }
_G.DEBUFF_TYPE_CURSE_COLOR = { r = 0.6, g = 0.0, b = 1.0 }
_G.DEBUFF_TYPE_DISEASE_COLOR = { r = 0.6, g = 0.4, b = 0.0 }
_G.DEBUFF_TYPE_POISON_COLOR = { r = 0.0, g = 0.6, b = 0.0 }
_G.DEBUFF_TYPE_BLEED_COLOR = { r = 0.8, g = 0.1, b = 0.1 }
_G.C_CurveUtil = {
  CreateColorCurve = function()
    return {
      points = {},
      SetType = function(self, curveType)
        self.curveType = curveType
      end,
      AddPoint = function(self, value, color)
        self.points[value] = color
      end,
    }
  end,
}

_G.C_UnitAuras = {
  GetUnitAuras = function(unit, filter)
    assert(unit == "party1", "watcher should only query the watched unit")
    return auraByFilter[filter] or {}
  end,
  GetAuraDuration = function(unit, auraInstanceID)
    assert(unit == "party1", "watcher should resolve duration on the watched unit")
    return durationByAuraInstanceID[auraInstanceID]
  end,
  GetAuraDispelTypeColor = function(_, auraInstanceID, curve)
    assert(curve ~= nil, "watcher should pass a dispel color curve to Blizzard API")
    dispelColorCalls[#dispelColorCalls + 1] = curve
    return { r = auraInstanceID / 10, g = 0.2, b = 0.3 }
  end,
  AuraIsBigDefensive = function(spellID)
    if spellID == 47585 then
      return true
    end
    if spellID == secretSpellID then
      return secretFlag
    end
    return false
  end,
  IsAuraFilteredOutByInstanceID = function(_, auraInstanceID, filter)
    return hiddenByFilter[filter] and hiddenByFilter[filter][auraInstanceID] == true or false
  end,
}

_G.C_Spell = {
  IsSpellCrowdControl = function(spellID)
    if spellID == 118 then
      return true
    end
    if spellID == secretSpellID then
      return secretFlag
    end
    return false
  end,
  IsSpellImportant = function(spellID)
    return spellID == 2825
  end,
}

local watcher = WatcherModule.New("party1", nil, { CC = true, Defensives = true, Important = true })

do
  auraByFilter["HARMFUL|CROWD_CONTROL"] = {
    { auraInstanceID = 10, spellId = 118, name = "Polymorph", icon = "poly", sourceUnit = "party2" },
    { auraInstanceID = 11, spellId = secretSpellID, name = secretName, icon = secretIcon, sourceUnit = secretSourceUnit },
  }
  auraByFilter["HELPFUL|BIG_DEFENSIVE"] = {
    { auraInstanceID = 20, spellId = 47585, name = "Dispersion", icon = "dispersion" },
    { auraInstanceID = 21, spellId = secretSpellID, name = secretName, icon = secretIcon },
  }
  auraByFilter["HELPFUL|EXTERNAL_DEFENSIVE"] = {
    { auraInstanceID = 30, spellId = 33206, name = "Pain Suppression", icon = "pain-sup" },
  }
  auraByFilter["HELPFUL|IMPORTANT"] = {
    { auraInstanceID = 40, spellId = 2825, name = "Bloodlust", icon = "lust" },
  }
  durationByAuraInstanceID[10] = { key = "cc" }
  durationByAuraInstanceID[11] = { key = "cc-secret" }
  durationByAuraInstanceID[20] = { key = "def" }
  durationByAuraInstanceID[21] = { key = "def-secret" }
  durationByAuraInstanceID[30] = { key = "ext-def" }
  durationByAuraInstanceID[40] = { key = "important" }

  hiddenByFilter["HELPFUL|IMPORTANT"] = {
    [20] = true,
    [21] = true,
    [30] = true,
    [40] = false,
  }

  watcher:ForceFullUpdate()

  local ccState = watcher:GetCcState()
  assert(#ccState == 2, "watcher should keep visible crowd-control auras")
  assert(ccState[1].SpellId == 118, "watcher should preserve non-secret spell ids")
  assert(ccState[1].SpellName == "Polymorph", "watcher should preserve non-secret spell names")
  assert(ccState[1].SpellIcon == "poly", "watcher should preserve non-secret icons")
  assert(ccState[1].SourceUnit == "party2", "watcher should preserve visible source units")
  assert(ccState[1].DurationObject.key == "cc", "watcher should preserve duration objects")
  assert(ccState[1].DispelColor and ccState[1].DispelColor.r == 1, "watcher should preserve dispel colors returned by Blizzard API")
  assert(#dispelColorCalls > 0, "watcher should request dispel colors for visible auras")
  assert(ccState[2].SpellId == nil, "watcher should sanitize secret crowd-control spell ids")
  assert(ccState[2].SpellName == nil, "watcher should sanitize secret crowd-control names")
  assert(ccState[2].SpellIcon == nil, "watcher should sanitize secret crowd-control icons")
  assert(ccState[2].SourceUnit == nil, "watcher should sanitize secret source units")
  assert(ccState[2].IsCC == true, "watcher should still classify secret crowd-control as active")

  local defensiveState = watcher:GetDefensiveState()
  assert(#defensiveState == 3, "watcher should include big and external defensives")
  assert(defensiveState[1].AuraTypes.BIG_DEFENSIVE == true, "watcher should tag big defensives")
  assert(defensiveState[2].SpellId == nil, "watcher should sanitize secret defensive spell ids")
  assert(defensiveState[2].IsDefensive == true, "watcher should still classify secret defensives")
  assert(defensiveState[3].AuraTypes.EXTERNAL_DEFENSIVE == true, "watcher should tag external defensives")

  local importantState = watcher:GetImportantState()
  assert(#importantState == 1, "watcher should keep visible important auras")
  assert(importantState[1].SpellId == 2825, "watcher should preserve important spell ids")
end

do
  local callbackCount = 0
  watcher:RegisterCallback(function()
    callbackCount = callbackCount + 1
  end)

  watcher:OnEvent("UNIT_AURA", "party2", { isFullUpdate = true })
  assert(callbackCount == 0, "watcher should ignore updates from other units")

  watcher:OnEvent("UNIT_AURA", "party1", {
    isFullUpdate = false,
    addedAuras = {},
    updatedAuraInstanceIDs = {},
    removedAuraInstanceIDs = {},
  })
  assert(callbackCount == 0, "watcher should ignore updates that do not touch tracked filters")

  watcher:OnEvent("UNIT_AURA", "party1", {
    isFullUpdate = false,
    updatedAuraInstanceIDs = { 10 },
  })
  assert(callbackCount == 1, "watcher should notify when a tracked aura changes")
end

watcher:Dispose()
print("ok")
