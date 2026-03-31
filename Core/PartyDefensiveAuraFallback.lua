local Fallback = {}
Fallback.__index = Fallback

function Fallback.New(deps)
  return setmetatable({
    deps = deps or {},
    callbacks = {},
    activeByUnit = {},
  }, Fallback)
end

function Fallback:RegisterCallback(callback)
  self.callbacks[#self.callbacks + 1] = callback
end

function Fallback:Emit(payload)
  for _, callback in ipairs(self.callbacks) do
    callback(payload)
  end
end

function Fallback:Reset()
  self.activeByUnit = {}
end

function Fallback:RemoveUnit(unitToken)
  self.activeByUnit[unitToken] = nil
end

function Fallback:ProcessAuraRemoved(ownerUnit, aura)
  local spellID = aura and (aura.spellID or aura.spellId) or nil
  local tracked = self.deps.resolveSpell and self.deps.resolveSpell(spellID)
  if not tracked or tracked.kind ~= "DEF" or type(tracked.cd) ~= "number" or tracked.cd <= 0 then
    return
  end

  local now = (self.deps.getTime and self.deps.getTime()) or 0
  self:Emit({
    ownerUnit = ownerUnit,
    spellID = tracked.spellID,
    source = "aura",
    startTime = now,
    readyAt = now + tracked.cd,
    baseCd = tracked.cd,
  })
end

function Fallback:ProcessAuraSnapshot(unitToken, auras)
  local current = {}

  for _, aura in ipairs(auras or {}) do
    local spellID = aura and aura.spellId or nil
    local auraInstanceID = aura and aura.auraInstanceID or nil
    local tracked = self.deps.resolveSpell and self.deps.resolveSpell(spellID)
    if auraInstanceID and tracked and tracked.kind == "DEF" then
      current[auraInstanceID] = {
        auraInstanceID = auraInstanceID,
        spellID = tracked.spellID,
      }
    end
  end

  local previous = self.activeByUnit[unitToken] or {}
  for auraInstanceID, payload in pairs(previous) do
    if not current[auraInstanceID] then
      self:ProcessAuraRemoved(unitToken, payload)
    end
  end

  self.activeByUnit[unitToken] = current
end

_G.SunderingToolsPartyDefensiveAuraFallback = Fallback

return Fallback
