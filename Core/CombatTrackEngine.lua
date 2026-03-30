local Engine = {}
Engine.__index = Engine

local priority = {
  auto = 1,
  correlated = 2,
  sync = 3,
  self = 4,
}
local correlationWindow = 0.5
local correlationTieThreshold = 0.05
local correlationSuppressionWindow = 0.2

local function copyTable(value)
  local copy = {}

  for key, field in pairs(value or {}) do
    copy[key] = field
  end

  return copy
end

local function getPriority(source)
  return priority[source] or 0
end

local function getCooldown(entry)
  if type(entry) ~= "table" then
    return nil
  end

  return entry.baseCd or entry.cd
end

local function resolveKey(playerGUID, spellID)
  if not playerGUID or not spellID then
    return nil
  end

  return tostring(playerGUID) .. ":" .. tostring(spellID)
end

local function mergeEntry(current, nextEntry)
  local merged = copyTable(current)
  local nextPriority = getPriority(nextEntry.source)
  local currentPriority = getPriority(current.source)

  for key, value in pairs(nextEntry) do
    if value ~= nil then
      merged[key] = value
    end
  end

  if nextPriority < currentPriority then
    merged.source = current.source
    merged.startTime = current.startTime
    merged.readyAt = current.readyAt
  end

  return merged
end

local function findInterruptEntryByUnit(entries, unitToken)
  local best = nil

  for _, entry in pairs(entries) do
    if entry.unitToken == unitToken and entry.kind == "INT" then
      if not best then
        best = entry
      else
        local entryPriority = getPriority(entry.source)
        local bestPriority = getPriority(best.source)

        if entryPriority > bestPriority then
          best = entry
        elseif entryPriority == bestPriority then
          local entryStart = entry.startTime or 0
          local bestStart = best.startTime or 0

          if entryStart > bestStart then
            best = entry
          elseif entryStart == bestStart and (entry.key or "") > (best.key or "") then
            best = entry
          end
        end
      end
    end
  end

  return best
end

local function removePendingCasts(pendingCasts, targets)
  local remaining = {}
  local targetSet = {}

  for _, target in ipairs(targets) do
    targetSet[target] = true
  end

  for _, cast in ipairs(pendingCasts) do
    if not targetSet[cast] then
      remaining[#remaining + 1] = cast
    end
  end

  return remaining
end

function Engine.New(config)
  return setmetatable({
    config = config or {},
    entries = {},
    pendingCasts = {},
    lastCorrelationKey = nil,
    lastCorrelationTime = 0,
  }, Engine)
end

function Engine:GetEntry(key)
  return self.entries[key]
end

function Engine:GetEntries()
  local list = {}

  for _, entry in pairs(self.entries) do
    list[#list + 1] = entry
  end

  table.sort(list, function(a, b)
    return (a.key or "") < (b.key or "")
  end)

  return list
end

function Engine:GetEntriesByKind(kind)
  local list = {}

  for _, entry in pairs(self.entries) do
    if entry.kind == kind then
      list[#list + 1] = entry
    end
  end

  table.sort(list, function(a, b)
    return (a.key or "") < (b.key or "")
  end)

  return list
end

function Engine:GetBestEntryForPlayer(playerGUID, kind)
  local best = nil

  for _, entry in pairs(self.entries) do
    if entry.playerGUID == playerGUID and (kind == nil or entry.kind == kind) then
      if not best then
        best = entry
      else
        local entryPriority = getPriority(entry.source)
        local bestPriority = getPriority(best.source)

        if entryPriority > bestPriority then
          best = entry
        elseif entryPriority == bestPriority then
          local entryStart = entry.startTime or 0
          local bestStart = best.startTime or 0

          if entryStart > bestStart then
            best = entry
          elseif entryStart == bestStart and (entry.key or "") > (best.key or "") then
            best = entry
          end
        end
      end
    end
  end

  return best
end

function Engine:RemoveEntry(key)
  if key then
    self.entries[key] = nil
  end
end

function Engine:UpsertEntry(entry)
  if type(entry) ~= "table" then
    return nil
  end

  local key = entry.key or resolveKey(entry.playerGUID, entry.spellID)
  if not key then
    return nil
  end

  local nextEntry = copyTable(entry)
  nextEntry.key = key

  local current = self.entries[key]
  if current then
    nextEntry = mergeEntry(current, nextEntry)
  end

  self.entries[key] = nextEntry
  return nextEntry
end

function Engine:RegisterExpectedEntry(entry)
  if type(entry) ~= "table" then
    return nil
  end

  local expected = copyTable(entry)
  expected.source = expected.source or "auto"
  return self:UpsertEntry(expected)
end

function Engine:ApplyCast(playerGUID, spellID, source, startTime, readyAt)
  local key = resolveKey(playerGUID, spellID)
  local current = key and self.entries[key] or nil
  local entry = {
    key = key,
    playerGUID = playerGUID,
    spellID = spellID,
    source = source,
    startTime = startTime,
    readyAt = readyAt,
  }

  local cooldown = getCooldown(current)
  if cooldown and entry.readyAt == nil and startTime ~= nil then
    entry.readyAt = startTime + cooldown
  end

  return self:UpsertEntry(entry)
end

function Engine:ApplyCorrelatedCast(playerGUID, spellID, startTime, readyAt)
  return self:ApplyCast(playerGUID, spellID, "correlated", startTime, readyAt)
end

function Engine:ApplySyncCast(playerGUID, spellID, startTime, readyAt)
  return self:ApplyCast(playerGUID, spellID, "sync", startTime, readyAt)
end

function Engine:ApplySyncState(playerGUID, spellID, fields)
  fields = fields or {}
  local cooldown = fields.cd
  if type(cooldown) ~= "number" or cooldown <= 0 then
    cooldown = nil
  end

  return self:UpsertEntry({
    key = resolveKey(playerGUID, spellID),
    playerGUID = playerGUID,
    spellID = spellID,
    source = "sync",
    kind = fields.kind,
    cd = cooldown,
    baseCd = cooldown,
    charges = fields.charges,
    startTime = fields.startTime,
    readyAt = fields.readyAt,
  })
end

function Engine:ApplySelfCast(playerGUID, spellID, startTime, readyAt)
  return self:ApplyCast(playerGUID, spellID, "self", startTime, readyAt)
end

function Engine:RecordPartyCast(unitToken, observedAt)
  self.pendingCasts[#self.pendingCasts + 1] = {
    unitToken = unitToken,
    observedAt = observedAt,
  }
end

function Engine:ResolveInterruptWindow(observedAt, windowSize)
  local maxWindow = correlationWindow
  local selfObservedAt = nil
  local selfWinsTies = false
  local consumeSuppressed = false

  if type(windowSize) == "table" then
    maxWindow = windowSize.windowSize or correlationWindow
    selfObservedAt = windowSize.selfObservedAt
    selfWinsTies = windowSize.selfWinsTies == true
    consumeSuppressed = windowSize.consumeSuppressed == true
  else
    maxWindow = windowSize or correlationWindow
  end

  local freshCasts = {}
  local matches = {}

  for _, cast in ipairs(self.pendingCasts) do
    local compareTime = observedAt
    if compareTime == nil then
      compareTime = cast.observedAt
    end

    local delta = nil
    if compareTime ~= nil and cast.observedAt ~= nil then
      delta = compareTime - cast.observedAt
    end

    if delta ~= nil and delta <= maxWindow then
      freshCasts[#freshCasts + 1] = cast
    end

    if delta ~= nil and delta >= 0 and delta <= maxWindow then
      local entry = findInterruptEntryByUnit(self.entries, cast.unitToken)

      if entry then
        matches[#matches + 1] = {
          cast = cast,
          entry = entry,
          delta = delta,
        }
      end
    end
  end

  self.pendingCasts = freshCasts

  if #matches == 0 then
    return nil
  end

  table.sort(matches, function(a, b)
    if a.delta == b.delta then
      return (a.entry.key or "") < (b.entry.key or "")
    end

    return a.delta < b.delta
  end)

  local best = matches[1]

  if selfWinsTies and selfObservedAt ~= nil then
    local selfDelta = observedAt
    if selfDelta == nil then
      selfDelta = selfObservedAt
    end

    if selfDelta ~= nil then
      selfDelta = selfDelta - selfObservedAt
    end

    if selfDelta ~= nil and selfDelta >= 0 and selfDelta <= maxWindow and selfDelta <= best.delta then
      if consumeSuppressed then
        local suppressedCasts = {}
        for _, candidate in ipairs(matches) do
          suppressedCasts[#suppressedCasts + 1] = candidate.cast
        end
        self.pendingCasts = removePendingCasts(self.pendingCasts, suppressedCasts)
      end

      return nil
    end
  end

  local contenderCount = 0
  local ambiguousCasts = {}

  for _, candidate in ipairs(matches) do
    if (candidate.delta - best.delta) <= correlationTieThreshold then
      contenderCount = contenderCount + 1
      ambiguousCasts[#ambiguousCasts + 1] = candidate.cast
    end
  end

  if contenderCount > 1 then
    self.pendingCasts = removePendingCasts(self.pendingCasts, ambiguousCasts)
    return nil
  end

  self.pendingCasts = removePendingCasts(self.pendingCasts, { best.cast })

  local resolvedAt = observedAt
  if resolvedAt == nil then
    resolvedAt = best.cast.observedAt
  end

  if self.lastCorrelationKey == best.entry.key and resolvedAt ~= nil and ((resolvedAt or 0) - (self.lastCorrelationTime or 0)) <= correlationSuppressionWindow then
    return nil
  end

  self.lastCorrelationKey = best.entry.key
  self.lastCorrelationTime = resolvedAt or 0

  local readyAt = nil
  local cooldown = getCooldown(best.entry)
  if cooldown and resolvedAt ~= nil then
    readyAt = resolvedAt + cooldown
  end

  return self:ApplyCorrelatedCast(
    best.entry.playerGUID,
    best.entry.spellID,
    resolvedAt,
    readyAt
  )
end

function Engine:Reset()
  self.entries = {}
  self.pendingCasts = {}
  self.lastCorrelationKey = nil
  self.lastCorrelationTime = 0
end

_G.SunderingToolsCombatTrackEngine = Engine

return Engine
