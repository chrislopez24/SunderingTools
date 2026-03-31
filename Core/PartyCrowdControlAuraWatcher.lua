local Watcher = {}
Watcher.__index = Watcher

local function isSecretClassification(value, isSecretValue)
  return value ~= nil and isSecretValue ~= nil and isSecretValue(value)
end

local function sanitizeAuraNumber(value, isSecretValue)
  if type(value) ~= "number" then
    return nil
  end

  if isSecretValue and isSecretValue(value) then
    return nil
  end

  return value
end

local function copyAura(aura, now, isSecretValue)
  local spellID = aura.spellId
  local sourceUnit = aura.sourceUnit

  if isSecretValue and spellID ~= nil and isSecretValue(spellID) then
    spellID = nil
  end

  if isSecretValue and sourceUnit ~= nil and isSecretValue(sourceUnit) then
    sourceUnit = nil
  end

  local expirationTime = sanitizeAuraNumber(aura.expirationTime, isSecretValue) or 0
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

local function payloadChanged(previous, current)
  return previous == nil
    or previous.auraInstanceID ~= current.auraInstanceID
    or previous.unitToken ~= current.unitToken
    or previous.spellID ~= current.spellID
    or previous.sourceUnit ~= current.sourceUnit
    or previous.remaining ~= current.remaining
    or previous.isCrowdControl ~= current.isCrowdControl
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

function Watcher:RemoveUnit(unitToken)
  local previous = self.activeByUnit[unitToken]
  if not previous then
    return
  end

  for _, payload in pairs(previous) do
    self:Emit("CC_REMOVED", payload)
  end

  self.activeByUnit[unitToken] = nil
end

function Watcher:ProcessAuraSnapshot(unitToken, auras)
  local now = (self.deps.getTime and self.deps.getTime()) or 0
  local isSecretValue = self.deps.isSecretValue
  local isCrowdControl = self.deps.isCrowdControl or function() return false end
  local current = {}

  for _, aura in ipairs(auras or {}) do
    local classification = isCrowdControl(aura)
    local classified = classification == true
      or isSecretClassification(classification, isSecretValue)
      or aura.isCrowdControl == true
    if classified and aura.auraInstanceID then
      current[aura.auraInstanceID] = copyAura({
        auraInstanceID = aura.auraInstanceID,
        unitToken = unitToken,
        spellId = aura.spellId,
        sourceUnit = aura.sourceUnit,
        expirationTime = aura.expirationTime,
        isCrowdControl = true,
      }, now, isSecretValue)
    end
  end

  self.activeByUnit[unitToken] = self.activeByUnit[unitToken] or {}
  local previous = self.activeByUnit[unitToken]

  for auraInstanceID, payload in pairs(current) do
    if not previous[auraInstanceID] then
      self:Emit("CC_APPLIED", payload)
    elseif payloadChanged(previous[auraInstanceID], payload) then
      self:Emit("CC_UPDATED", payload)
    else
      current[auraInstanceID] = previous[auraInstanceID]
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
