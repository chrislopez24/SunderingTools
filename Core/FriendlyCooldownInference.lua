local Inference = {}
Inference.__index = Inference

local function auraTypesSignature(auraTypes)
  local signature = ""
  if auraTypes and auraTypes.BIG_DEFENSIVE then
    signature = signature .. "B"
  end
  if auraTypes and auraTypes.EXTERNAL_DEFENSIVE then
    signature = signature .. "E"
  end
  if auraTypes and auraTypes.IMPORTANT then
    signature = signature .. "I"
  end
  if auraTypes and auraTypes.CROWD_CONTROL then
    signature = signature .. "C"
  end
  return signature
end

function Inference.New(deps)
  return setmetatable({
    deps = deps or {},
    trackedByUnit = {},
    callbacks = {},
  }, Inference)
end

function Inference:RegisterCallback(callback)
  self.callbacks[#self.callbacks + 1] = callback
end

function Inference:Emit(event, payload)
  for _, callback in ipairs(self.callbacks) do
    callback(event, payload)
  end
end

function Inference:Reset()
  self.trackedByUnit = {}
end

function Inference:RemoveUnit(unit)
  self.trackedByUnit[unit] = nil
end

function Inference:TrackNewAura(unit, aura, unitContext)
  local now = (self.deps.getTime and self.deps.getTime()) or 0
  local evidence = self.deps.buildEvidenceSet and self.deps.buildEvidenceSet(unit, now) or nil
  local castSnapshot = self.deps.buildCastSnapshot and self.deps.buildCastSnapshot() or {}

  self.trackedByUnit[unit] = self.trackedByUnit[unit] or {}
  self.trackedByUnit[unit][aura.AuraInstanceID] = {
    AuraInstanceID = aura.AuraInstanceID,
    StartTime = now,
    SpellId = aura.SpellId,
    SpellName = aura.SpellName,
    SpellIcon = aura.SpellIcon,
    AuraTypes = aura.AuraTypes,
    Evidence = evidence,
    CastSnapshot = castSnapshot,
    UnitContext = unitContext,
  }
end

function Inference:ResolveCooldownEntry(unit, tracked, unitContext, measuredDuration)
  local resolver = self.deps.resolveEntry
  if tracked.SpellId and resolver then
    local direct = resolver(tracked.SpellId, unitContext, tracked, measuredDuration)
    if direct and type(direct.cd) == "number" and direct.cd > 0 then
      return direct
    end
  end

  local matcher = self.deps.matchRule
  if matcher then
    local matched = matcher(unitContext, tracked, measuredDuration, tracked.Evidence)
    if matched and type(matched.cd) == "number" and matched.cd > 0 then
      return matched
    end
  end

  return nil
end

function Inference:ProcessSnapshot(unit, currentAuras, unitContext)
  local trackedById = self.trackedByUnit[unit] or {}
  local now = (self.deps.getTime and self.deps.getTime()) or 0
  local currentById = {}
  local newIdsBySignature = {}

  for _, aura in ipairs(currentAuras or {}) do
    if aura and aura.AuraInstanceID then
      currentById[aura.AuraInstanceID] = aura
      if not trackedById[aura.AuraInstanceID] then
        local signature = auraTypesSignature(aura.AuraTypes)
        newIdsBySignature[signature] = newIdsBySignature[signature] or {}
        newIdsBySignature[signature][#newIdsBySignature[signature] + 1] = aura.AuraInstanceID
      end
    end
  end

  for auraInstanceID, tracked in pairs(trackedById) do
    if not currentById[auraInstanceID] then
      local signature = auraTypesSignature(tracked.AuraTypes)
      local candidates = newIdsBySignature[signature]
      if candidates and #candidates > 0 then
        local reassignedId = table.remove(candidates, 1)
        tracked.AuraInstanceID = reassignedId
        trackedById[reassignedId] = tracked
      else
        local measuredDuration = now - tracked.StartTime
        local resolved = self:ResolveCooldownEntry(unit, tracked, unitContext or tracked.UnitContext, measuredDuration)
        if resolved then
          self:Emit("COOLDOWN_INFERRED", {
            unit = unit,
            auraInstanceID = tracked.AuraInstanceID,
            tracked = tracked,
            resolved = resolved,
            measuredDuration = measuredDuration,
            unitContext = unitContext or tracked.UnitContext,
            startedAt = tracked.StartTime,
            readyAt = tracked.StartTime + resolved.cd,
          })
        end
      end
      trackedById[auraInstanceID] = nil
    end
  end

  for auraInstanceID, aura in pairs(currentById) do
    if not trackedById[auraInstanceID] then
      self:TrackNewAura(unit, aura, unitContext)
      trackedById = self.trackedByUnit[unit] or trackedById
    else
      trackedById[auraInstanceID].SpellId = aura.SpellId or trackedById[auraInstanceID].SpellId
      trackedById[auraInstanceID].SpellName = aura.SpellName or trackedById[auraInstanceID].SpellName
      trackedById[auraInstanceID].SpellIcon = aura.SpellIcon or trackedById[auraInstanceID].SpellIcon
      trackedById[auraInstanceID].AuraTypes = aura.AuraTypes or trackedById[auraInstanceID].AuraTypes
      trackedById[auraInstanceID].UnitContext = unitContext or trackedById[auraInstanceID].UnitContext
    end
  end

  self.trackedByUnit[unit] = trackedById
end

_G.SunderingToolsFriendlyCooldownInference = Inference

return Inference
