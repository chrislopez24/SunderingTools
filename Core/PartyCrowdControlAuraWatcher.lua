local Watcher = {}
Watcher.__index = Watcher

local function copyAura(aura, now, isSecretValue)
  local spellID = aura.spellId
  local sourceUnit = aura.sourceUnit

  if isSecretValue and spellID ~= nil and isSecretValue(spellID) then
    spellID = nil
  end

  if isSecretValue and sourceUnit ~= nil and isSecretValue(sourceUnit) then
    sourceUnit = nil
  end

  local expirationTime = aura.expirationTime or 0
  local remaining = expirationTime > 0 and math.max(0, expirationTime - now) or 0

  return {
    auraInstanceID = aura.auraInstanceID,
    unitToken = aura.unitToken,
    spellID = spellID,
    sourceUnit = sourceUnit,
    remaining = remaining,
    isCrowdControl = aura.isCrowdControl == true,
  }
end

function Watcher.New(deps)
  return setmetatable({
    deps = deps or {},
    callbacks = {},
    activeByUnit = {},
  }, Watcher)
end

function Watcher:RegisterCallback(callback)
  self.callbacks[#self.callbacks + 1] = callback
end

function Watcher:Emit(event, payload)
  for _, callback in ipairs(self.callbacks) do
    callback(event, payload)
  end
end

function Watcher:ProcessAuraSnapshot(unitToken, auras)
  local now = (self.deps.getTime and self.deps.getTime()) or 0
  local isSecretValue = self.deps.isSecretValue
  local isCrowdControl = self.deps.isCrowdControl or function() return false end
  local current = {}

  for _, aura in ipairs(auras or {}) do
    local usableSpellID = aura.spellId
    local classified = usableSpellID ~= nil and isCrowdControl(usableSpellID) or aura.isCrowdControl == true
    if classified and aura.auraInstanceID then
      aura.unitToken = unitToken
      aura.isCrowdControl = true
      current[aura.auraInstanceID] = copyAura(aura, now, isSecretValue)
    end
  end

  self.activeByUnit[unitToken] = self.activeByUnit[unitToken] or {}
  local previous = self.activeByUnit[unitToken]

  for auraInstanceID, payload in pairs(current) do
    if not previous[auraInstanceID] then
      self:Emit("CC_APPLIED", payload)
    else
      self:Emit("CC_UPDATED", payload)
    end
  end

  for auraInstanceID, payload in pairs(previous) do
    if not current[auraInstanceID] then
      self:Emit("CC_REMOVED", payload)
    end
  end

  self.activeByUnit[unitToken] = current
end

_G.SunderingToolsPartyCrowdControlAuraWatcher = Watcher

return Watcher
