local Evidence = {}
Evidence.__index = Evidence

local function BuildEvidenceSet(instance, unit, detectionTime)
  local state = instance.State
  local evidence = nil

  local function Mark(kind)
    evidence = evidence or {}
    evidence[kind] = true
  end

  if state.lastDebuffTime[unit] and math.abs(state.lastDebuffTime[unit] - detectionTime) <= state.evidenceWindow then
    Mark("Debuff")
  end

  if state.lastShieldTime[unit] and math.abs(state.lastShieldTime[unit] - detectionTime) <= state.evidenceWindow then
    Mark("Shield")
  end

  if state.lastFeignDeathTime[unit] and math.abs(state.lastFeignDeathTime[unit] - detectionTime) <= state.castWindow then
    Mark("FeignDeath")
  elseif state.lastUnitFlagsTime[unit] and math.abs(state.lastUnitFlagsTime[unit] - detectionTime) <= state.castWindow then
    Mark("UnitFlags")
  end

  if state.lastCastTime[unit] and math.abs(state.lastCastTime[unit] - detectionTime) <= state.castWindow then
    Mark("Cast")
  end

  return evidence
end

function Evidence.New(deps)
  deps = deps or {}
  return setmetatable({
    deps = deps,
    State = {
      castWindow = deps.castWindow or 0.15,
      evidenceWindow = deps.evidenceWindow or 0.15,
      lastCastTime = {},
      lastDebuffTime = {},
      lastShieldTime = {},
      lastUnitFlagsTime = {},
      lastFeignDeathTime = {},
      lastFeignDeathState = {},
    },
  }, Evidence)
end

function Evidence:Reset()
  self.State.lastCastTime = {}
  self.State.lastDebuffTime = {}
  self.State.lastShieldTime = {}
  self.State.lastUnitFlagsTime = {}
  self.State.lastFeignDeathTime = {}
  self.State.lastFeignDeathState = {}
end

function Evidence:RecordSpellcastSucceeded(unit, now)
  self.State.lastCastTime[unit] = now or ((self.deps.getTime and self.deps.getTime()) or 0)
end

function Evidence:RecordUnitFlags(unit, isFeignDeath, now)
  now = now or ((self.deps.getTime and self.deps.getTime()) or 0)

  if isFeignDeath and not self.State.lastFeignDeathState[unit] then
    self.State.lastFeignDeathTime[unit] = now
  elseif not isFeignDeath then
    self.State.lastUnitFlagsTime[unit] = now
  end

  self.State.lastFeignDeathState[unit] = isFeignDeath and true or false
end

function Evidence:RecordAbsorbChanged(unit, now)
  self.State.lastShieldTime[unit] = now or ((self.deps.getTime and self.deps.getTime()) or 0)
end

function Evidence:RecordAuraUpdate(unit, updateInfo, now)
  if not updateInfo or updateInfo.isFullUpdate then
    return
  end

  now = now or ((self.deps.getTime and self.deps.getTime()) or 0)
  for _, aura in ipairs(updateInfo.addedAuras or {}) do
    local auraInstanceID = aura and aura.auraInstanceID or nil
    local isVisibleHarmful = auraInstanceID
      and C_UnitAuras
      and C_UnitAuras.IsAuraFilteredOutByInstanceID
      and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HARMFUL")
    if isVisibleHarmful then
      self.State.lastDebuffTime[unit] = now
      break
    end
  end
end

function Evidence:BuildEvidenceSet(unit, detectionTime)
  return BuildEvidenceSet(self, unit, detectionTime)
end

function Evidence:BuildCastSnapshot()
  local snapshot = {}
  for unit, castTime in pairs(self.State.lastCastTime) do
    snapshot[unit] = castTime
  end
  return snapshot
end

_G.SunderingToolsFriendlyEventEvidence = Evidence

return Evidence
