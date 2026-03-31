local WatcherModule = {}

local function SanitizeValue(value)
  if value ~= nil and issecretvalue and issecretvalue(value) then
    return nil
  end

  return value
end

local function CoerceFlag(value)
  if value ~= nil and issecretvalue and issecretvalue(value) then
    return true
  end

  return value == true
end

local function NotifyCallbacks(watcher)
  for _, callback in ipairs(watcher.State.Callbacks) do
    callback(watcher)
  end
end

local function InterestedIn(watcher, updateInfo)
  if not updateInfo or updateInfo.isFullUpdate then
    return true
  end

  local unit = watcher.State.Unit
  local activeFilters = watcher.State.ActiveFilters or {}

  local function MatchesFilter(auraInstanceID)
    if not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID) then
      return true
    end

    for _, filter in ipairs(activeFilters) do
      if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter) then
        return true
      end
    end

    return false
  end

  for _, aura in ipairs(updateInfo.addedAuras or {}) do
    local auraInstanceID = aura and aura.auraInstanceID or nil
    if auraInstanceID and MatchesFilter(auraInstanceID) then
      return true
    end
  end

  for _, auraInstanceID in ipairs(updateInfo.updatedAuraInstanceIDs or {}) do
    if auraInstanceID and MatchesFilter(auraInstanceID) then
      return true
    end
  end

  if next(updateInfo.removedAuraInstanceIDs or {}) ~= nil then
    local trackedStates = {
      watcher.State.CcAuraState,
      watcher.State.DefensiveState,
      watcher.State.ImportantAuraState,
    }

    for _, auraInstanceID in ipairs(updateInfo.removedAuraInstanceIDs or {}) do
      for _, trackedState in ipairs(trackedStates) do
        for _, aura in ipairs(trackedState or {}) do
          if aura.AuraInstanceID == auraInstanceID then
            return true
          end
        end
      end
    end
  end

  return false
end

local function IterateAuras(unit, filter, sortRule, sortDirection, callback)
  if not (C_UnitAuras and C_UnitAuras.GetUnitAuras and C_UnitAuras.GetAuraDuration) then
    return
  end

  local auras = C_UnitAuras.GetUnitAuras(unit, filter, nil, sortRule, sortDirection)
  for _, auraData in ipairs(auras or {}) do
    local auraInstanceID = auraData and auraData.auraInstanceID or nil
    if auraInstanceID then
      local durationObject = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
      if durationObject then
        local dispelColor = nil
        if C_UnitAuras.GetAuraDispelTypeColor then
          dispelColor = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID)
        end
        callback(auraData, durationObject, dispelColor)
      end
    end
  end
end

local Watcher = {}
Watcher.__index = Watcher

function Watcher:GetUnit()
  return self.State.Unit
end

function Watcher:RegisterCallback(callback)
  if not callback then
    return
  end

  self.State.Callbacks[#self.State.Callbacks + 1] = callback
end

function Watcher:IsEnabled()
  return self.State.Enabled
end

function Watcher:Enable()
  if self.State.Enabled or not self.Frame then
    return
  end

  self.Frame:RegisterUnitEvent("UNIT_AURA", self.State.Unit)
  if self.State.Events then
    for _, event in ipairs(self.State.Events) do
      self.Frame:RegisterEvent(event)
    end
  end
  self.State.Enabled = true
end

function Watcher:Disable()
  if not self.State.Enabled then
    return
  end

  if self.Frame and self.Frame.UnregisterAllEvents then
    self.Frame:UnregisterAllEvents()
  end
  self.State.Enabled = false
end

function Watcher:ClearState(notify)
  self.State.CcAuraState = {}
  self.State.DefensiveState = {}
  self.State.ImportantAuraState = {}

  if notify then
    NotifyCallbacks(self)
  end
end

function Watcher:GetCcState()
  return self.State.CcAuraState
end

function Watcher:GetDefensiveState()
  return self.State.DefensiveState
end

function Watcher:GetImportantState()
  return self.State.ImportantAuraState
end

function Watcher:SetSort(sortRule, sortDirection)
  if self.State.SortRule == sortRule and self.State.SortDirection == sortDirection then
    return
  end

  self.State.SortRule = sortRule
  self.State.SortDirection = sortDirection
  self:ForceFullUpdate()
end

function Watcher:ForceFullUpdate()
  self:OnEvent("UNIT_AURA", self.State.Unit, { isFullUpdate = true })
end

function Watcher:Dispose()
  if self.Frame then
    if self.Frame.UnregisterAllEvents then
      self.Frame:UnregisterAllEvents()
    end
    if self.Frame.SetScript then
      self.Frame:SetScript("OnEvent", nil)
    end
    self.Frame.Watcher = nil
  end

  self.Frame = nil
  self.State.Callbacks = {}
  self:ClearState(false)
end

function Watcher:RebuildStates()
  local unit = self.State.Unit
  if not unit then
    return
  end

  if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
    local hadState = next(self.State.CcAuraState) ~= nil
      or next(self.State.DefensiveState) ~= nil
      or next(self.State.ImportantAuraState) ~= nil
    if hadState then
      self:ClearState(true)
    end
    return
  end

  local interestedIn = self.State.InterestedIn
  local wantCC = not interestedIn or interestedIn.CC
  local wantDefensives = not interestedIn or interestedIn.Defensives
  local wantImportant = not interestedIn or interestedIn.Important
  local sortRule = self.State.SortRule
  local sortDirection = self.State.SortDirection

  local ccState = {}
  local defensiveState = {}
  local importantState = {}
  local seen = {}

  if wantDefensives then
    IterateAuras(unit, "HELPFUL|BIG_DEFENSIVE", sortRule, sortDirection, function(auraData, durationObject, dispelColor)
      local isDefensive = C_UnitAuras.AuraIsBigDefensive and C_UnitAuras.AuraIsBigDefensive(auraData.spellId)
      if CoerceFlag(isDefensive) then
        defensiveState[#defensiveState + 1] = {
          IsDefensive = true,
          SpellId = SanitizeValue(auraData.spellId),
          SpellName = SanitizeValue(auraData.name),
          SpellIcon = SanitizeValue(auraData.icon or auraData.iconFileID),
          SourceUnit = SanitizeValue(auraData.sourceUnit),
          DurationObject = durationObject,
          DispelColor = dispelColor,
          AuraInstanceID = auraData.auraInstanceID,
          AuraTypes = {
            BIG_DEFENSIVE = true,
            IMPORTANT = not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID and C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraData.auraInstanceID, "HELPFUL|IMPORTANT")),
          },
        }
      end
      seen[auraData.auraInstanceID] = true
    end)

    IterateAuras(unit, "HELPFUL|EXTERNAL_DEFENSIVE", sortRule, sortDirection, function(auraData, durationObject, dispelColor)
      if not seen[auraData.auraInstanceID] then
        defensiveState[#defensiveState + 1] = {
          IsDefensive = true,
          SpellId = SanitizeValue(auraData.spellId),
          SpellName = SanitizeValue(auraData.name),
          SpellIcon = SanitizeValue(auraData.icon or auraData.iconFileID),
          SourceUnit = SanitizeValue(auraData.sourceUnit),
          DurationObject = durationObject,
          DispelColor = dispelColor,
          AuraInstanceID = auraData.auraInstanceID,
          AuraTypes = {
            EXTERNAL_DEFENSIVE = true,
            IMPORTANT = not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID and C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraData.auraInstanceID, "HELPFUL|IMPORTANT")),
          },
        }
        seen[auraData.auraInstanceID] = true
      end
    end)
  end

  if wantCC then
    IterateAuras(unit, "HARMFUL|CROWD_CONTROL", sortRule, sortDirection, function(auraData, durationObject, dispelColor)
      local isCC = C_Spell and C_Spell.IsSpellCrowdControl and C_Spell.IsSpellCrowdControl(auraData.spellId)
      if CoerceFlag(isCC) then
        ccState[#ccState + 1] = {
          IsCC = true,
          SpellId = SanitizeValue(auraData.spellId),
          SpellName = SanitizeValue(auraData.name),
          SpellIcon = SanitizeValue(auraData.icon or auraData.iconFileID),
          SourceUnit = SanitizeValue(auraData.sourceUnit),
          DurationObject = durationObject,
          DispelColor = dispelColor,
          AuraInstanceID = auraData.auraInstanceID,
          AuraTypes = {
            CROWD_CONTROL = true,
          },
        }
      end
      seen[auraData.auraInstanceID] = true
    end)
  end

  if wantImportant then
    local filter = (interestedIn and interestedIn.ImportantFilter) or "HELPFUL|IMPORTANT"
    IterateAuras(unit, filter, sortRule, sortDirection, function(auraData, durationObject, dispelColor)
      if not seen[auraData.auraInstanceID] then
        local isImportant = C_Spell and C_Spell.IsSpellImportant and C_Spell.IsSpellImportant(auraData.spellId)
        if CoerceFlag(isImportant) then
          importantState[#importantState + 1] = {
            IsImportant = true,
            SpellId = SanitizeValue(auraData.spellId),
            SpellName = SanitizeValue(auraData.name),
            SpellIcon = SanitizeValue(auraData.icon or auraData.iconFileID),
            SourceUnit = SanitizeValue(auraData.sourceUnit),
            DurationObject = durationObject,
            DispelColor = dispelColor,
            AuraInstanceID = auraData.auraInstanceID,
            AuraTypes = {
              IMPORTANT = true,
            },
          }
        end
        seen[auraData.auraInstanceID] = true
      end
    end)
  end

  self.State.CcAuraState = ccState
  self.State.DefensiveState = defensiveState
  self.State.ImportantAuraState = importantState
end

function Watcher:OnEvent(event, ...)
  if event == "UNIT_AURA" then
    local unit, updateInfo = ...
    if unit and unit ~= self.State.Unit then
      return
    end

    if not InterestedIn(self, updateInfo) then
      return
    end
  end

  self:RebuildStates()
  NotifyCallbacks(self)
end

function WatcherModule.New(unit, events, interestedIn, sortRule, sortDirection)
  local activeFilters = {}
  local all = not interestedIn
  if all or interestedIn.Defensives then
    activeFilters[#activeFilters + 1] = "HELPFUL|BIG_DEFENSIVE"
    activeFilters[#activeFilters + 1] = "HELPFUL|EXTERNAL_DEFENSIVE"
  end
  if all or interestedIn.CC then
    activeFilters[#activeFilters + 1] = "HARMFUL|CROWD_CONTROL"
  end
  if all or interestedIn.Important then
    activeFilters[#activeFilters + 1] = (interestedIn and interestedIn.ImportantFilter) or "HELPFUL|IMPORTANT"
  end

  local watcher = setmetatable({
    Frame = CreateFrame("Frame"),
    State = {
      Unit = unit,
      Events = events,
      Enabled = false,
      Callbacks = {},
      CcAuraState = {},
      DefensiveState = {},
      ImportantAuraState = {},
      InterestedIn = interestedIn,
      ActiveFilters = activeFilters,
      SortRule = sortRule or (Enum and Enum.UnitAuraSortRule and Enum.UnitAuraSortRule.Unsorted) or 0,
      SortDirection = sortDirection or (Enum and Enum.UnitAuraSortDirection and Enum.UnitAuraSortDirection.Normal) or 0,
    },
  }, Watcher)

  watcher.Frame.Watcher = watcher
  watcher.Frame:SetScript("OnEvent", function(frame, event, ...)
    local activeWatcher = frame.Watcher
    if activeWatcher then
      activeWatcher:OnEvent(event, ...)
    end
  end)

  watcher:Enable()
  watcher:ForceFullUpdate()
  return watcher
end

_G.SunderingToolsUnitAuraStateWatcher = WatcherModule

return WatcherModule
