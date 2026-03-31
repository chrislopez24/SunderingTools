local addon = _G.SunderingTools
if not addon then return end

local Model = assert(
  _G.SunderingToolsCrowdControlTrackerModel,
  "SunderingToolsCrowdControlTrackerModel must load before CrowdControlTracker.lua"
)
local SpellDB = assert(
  _G.SunderingToolsCombatTrackSpellDB,
  "SunderingToolsCombatTrackSpellDB must load before CrowdControlTracker.lua"
)
local Sync = assert(
  _G.SunderingToolsCombatTrackSync,
  "SunderingToolsCombatTrackSync must load before CrowdControlTracker.lua"
)
local Engine = assert(
  _G.SunderingToolsCombatTrackEngine,
  "SunderingToolsCombatTrackEngine must load before CrowdControlTracker.lua"
)
local Resolver = assert(
  _G.SunderingToolsPartyCrowdControlResolver,
  "SunderingToolsPartyCrowdControlResolver must load before CrowdControlTracker.lua"
)
local FramePositioning = assert(
  _G.SunderingToolsFramePositioning,
  "SunderingToolsFramePositioning must load before CrowdControlTracker.lua"
)
local TrackerFrame = assert(
  _G.SunderingToolsTrackerFrame,
  "SunderingToolsTrackerFrame must load before CrowdControlTracker.lua"
)
local TrackerSettings = assert(
  _G.SunderingToolsTrackerSettings,
  "SunderingToolsTrackerSettings must load before CrowdControlTracker.lua"
)

local defaultPosX, defaultPosY = Model.GetDefaultPosition()
local filterModes = { "ESSENTIALS", "ALL" }
local HEADER_LABEL = "CC Spells"
local HEADER_TEXTURE = "Interface\\Icons\\Spell_Frost_ChainsOfIce"

local module = {
  key = "CrowdControlTracker",
  label = "Crowd Control Tracker",
  description = "Track crowd control, choose the filter, and adjust layout.",
  order = 15,
  defaults = TrackerSettings.CreateBarDefaults(defaultPosX, defaultPosY, {
    filterMode = Model.GetDefaultFilterMode(),
  }),
}

local db = addon.db and addon.db.CrowdControlTracker

local bars = {}
local activeBars = {}
local usedBarsList = {}
local container = nil
local trackerTicker = nil
local spellTextureCache = {}
local editModePreview = false
local CreateContainer
local EnsureBarPool
local ConfigureBarPool
local ReLayout
local UpdatePartyData
local UpdateBarVisuals
local StartCooldownTicker
local RegisterPartyWatchers

local runtime = {
  engine = Engine.New(),
  partyWatchFrames = {},
  partyPetWatchFrames = {},
  partyUsers = {},
  partyAddonUsers = {},
  partyManifests = {},
  recentPartyCasts = {},
  ccAuraPrevCount = {},
  lastHelloAt = 0,
  needsVisualRefresh = false,
  visualRefreshScheduled = false,
}

local function GetCachedSpellTexture(spellID)
  if not spellID then
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end

  if not spellTextureCache[spellID] then
    spellTextureCache[spellID] =
      (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
      or (GetSpellTexture and GetSpellTexture(spellID))
      or "Interface\\Icons\\INV_Misc_QuestionMark"
  end

  return spellTextureCache[spellID]
end

local function FlushDirtyTracker()
  if not runtime.needsVisualRefresh then
    return false
  end

  runtime.needsVisualRefresh = false
  runtime.visualRefreshScheduled = false
  UpdatePartyData()
  return true
end

local function MarkTrackerDirty()
  runtime.needsVisualRefresh = true
  if runtime.visualRefreshScheduled then
    return
  end

  runtime.visualRefreshScheduled = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, function()
      FlushDirtyTracker()
    end)
  else
    FlushDirtyTracker()
  end
end

local function ShouldShowPreview()
  if not db or not db.enabled then
    return false
  end

  if editModePreview then
    return true
  end

  return db.previewWhenSolo and not IsInGroup() and not IsInRaid() and not next(runtime.partyUsers)
end

local function IsCurrentInstanceAllowed()
  return TrackerSettings.IsBarContextAllowed(db)
end

local function ShouldHideForCombat()
  return db and db.hideOutOfCombat and not editModePreview and not InCombatLockdown()
end

local function HasVisibleBars()
  return next(activeBars) ~= nil
end

local function UpdateContainerVisibility()
  if not container or not db then return end

  if not db.enabled then
    container:Hide()
    return
  end

  if not editModePreview and not ShouldShowPreview() then
    if not IsCurrentInstanceAllowed() or ShouldHideForCombat() then
      container:Hide()
      return
    end
  end

  if editModePreview or ShouldShowPreview() or HasVisibleBars() then
    container:Show()
  else
    container:Hide()
  end
end

local function UpdateEditLabelVisibility(enabled)
  if not container or not container.editLabel then return end

  if enabled then
    container.editLabel:Show()
  else
    container.editLabel:Hide()
  end
end

local function UsesClassColor(moduleDB)
  return moduleDB.useClassColor ~= false
end

local function BlendColor(color, darkness, alpha)
  local r = (color[1] * (1 - darkness)) + (0.08 * darkness)
  local g = (color[2] * (1 - darkness)) + (0.08 * darkness)
  local b = (color[3] * (1 - darkness)) + (0.08 * darkness)
  return r, g, b, alpha or 1
end

local function GetIconOffset()
  return math.min(db.iconSize, db.barHeight) + 2
end

local function GetHeaderHeight()
  if not db or db.showHeader == false then
    return 0
  end

  return 18
end

local function RefreshHeaderLayout()
  if not container or not container.header or not db then
    return
  end

  local headerHeight = GetHeaderHeight()
  if headerHeight <= 0 then
    container.header:Hide()
    return
  end

  local headerWidth = math.max(96, math.min(db.barWidth, 132))
  container.header:ClearAllPoints()
  container.header:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 4)
  container.header:SetSize(headerWidth, headerHeight)

  container.header.bg:SetAllPoints()
  container.header.bg:SetColorTexture(0.14, 0.12, 0.24, 0.88)

  container.header.borderTop:SetPoint("TOPLEFT", container.header, "TOPLEFT", 0, 0)
  container.header.borderTop:SetPoint("TOPRIGHT", container.header, "TOPRIGHT", 0, 0)
  container.header.borderTop:SetHeight(1)
  container.header.borderTop:SetColorTexture(0.35, 0.31, 0.52, 0.9)

  container.header.borderBottom:SetPoint("BOTTOMLEFT", container.header, "BOTTOMLEFT", 0, 0)
  container.header.borderBottom:SetPoint("BOTTOMRIGHT", container.header, "BOTTOMRIGHT", 0, 0)
  container.header.borderBottom:SetHeight(1)
  container.header.borderBottom:SetColorTexture(0, 0, 0, 0.9)

  container.header.icon:SetSize(headerHeight - 4, headerHeight - 4)
  container.header.icon:SetPoint("LEFT", container.header, "LEFT", 2, 0)
  container.header.icon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(45524)) or HEADER_TEXTURE)

  container.header.title:ClearAllPoints()
  container.header.title:SetPoint("LEFT", container.header.icon, "RIGHT", 4, 0)
  container.header.title:SetPoint("RIGHT", container.header, "RIGHT", -6, 0)
  container.header.title:SetText(HEADER_LABEL)
  container.header.title:SetTextColor(1.0, 0.84, 0.22)
  container.header.title:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, db.fontSize), "OUTLINE")

  container.header:Show()
end

local function AfterDelay(delay, callback)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, callback)
  else
    callback()
  end
end

local function ShortName(name)
  if not name or name == "" then
    return nil
  end

  if Ambiguate then
    local short = Ambiguate(name, "short")
    if short and short ~= "" then
      return short
    end
  end

  return string.match(name, "^([^%-]+)") or name
end

local function GetLocalPlayerSpecID()
  if GetSpecialization and GetSpecializationInfo then
    local specIndex = GetSpecialization()
    if specIndex then
      local specID = GetSpecializationInfo(specIndex)
      if type(specID) == "number" and specID > 0 then
        return specID
      end
    end
  end

  return 0
end

local function BuildRuntimeKey(guid, spellID)
  if not guid or not spellID then
    return nil
  end

  return tostring(guid) .. ":" .. tostring(spellID)
end

local function BuildUserKey(playerName, spellID)
  if not playerName or not spellID then
    return nil
  end

  return tostring(playerName) .. "|" .. tostring(spellID)
end

local function GetEntryCooldown(entry)
  if type(entry) ~= "table" then
    return 0
  end

  return entry.baseCd or entry.cd or 0
end

local function GetRuntimeUnits()
  local units = { "player" }
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if not (UnitIsUnit and UnitIsUnit(unit, "player")) then
        units[#units + 1] = "raid" .. i
      end
    end
    return units
  end

  for i = 1, 4 do
    units[#units + 1] = "party" .. i
  end

  return units
end

local function BuildRuntimeUnitsForDisplay()
  local units = { "player" }
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if not (UnitIsUnit and UnitIsUnit(unit, "player")) then
        units[#units + 1] = "raid" .. i
      end
    end
    return units
  end

  if IsInGroup() then
    for i = 1, 4 do
      units[#units + 1] = "party" .. i
    end
  end

  return units
end

local function GetUnitBySender(sender)
  if not sender or sender == "" then
    return nil
  end

  local senderShort = ShortName(sender)
  for _, unit in ipairs(GetRuntimeUnits()) do
    if UnitExists(unit) then
      local unitName = UnitName(unit)
      if unitName == sender or ShortName(unitName) == senderShort then
        return unit
      end
    end
  end

  return nil
end

local function GetTrackedCrowdControlInfo(spellID)
  local tracked = spellID and SpellDB.GetTrackedSpell(spellID) or nil
  if tracked and tracked.kind == "CC" then
    return tracked
  end

  return nil
end

local crowdControlResolver = Resolver.New({
  getTime = GetTime,
  getCooldownForSpell = function(spellID)
    local tracked = GetTrackedCrowdControlInfo(spellID)
    return tracked and tracked.cd or 0
  end,
})

local function BuildSpellSet(spellIDs)
  local spellSet = {}
  for _, spellID in ipairs(spellIDs or {}) do
    spellSet[spellID] = true
  end
  return spellSet
end

local function GetManifestForUser(shortName)
  if not shortName or shortName == "" then
    return nil
  end

  local manifest = runtime.partyManifests[shortName]
  if not manifest then
    manifest = {
      spellList = {},
      spells = {},
      received = false,
    }
    runtime.partyManifests[shortName] = manifest
  end

  return manifest
end

local function HasAuthoritativeManifest(shortName)
  local manifest = shortName and runtime.partyManifests[shortName] or nil
  return manifest ~= nil and manifest.received == true
end

local function HasManifestSpell(shortName, spellID)
  local manifest = shortName and runtime.partyManifests[shortName] or nil
  return manifest ~= nil and manifest.spells ~= nil and manifest.spells[spellID] == true
end

local function GetLocalCrowdControlManifest()
  local _, classToken = UnitClass("player")
  if not classToken then
    return {}
  end

  local entries = Model.GetEligibleCrowdControlEntries(classToken, {
    includeAllKnown = true,
    isSpellKnown = function(spellID)
      return not IsSpellKnown or IsSpellKnown(spellID)
    end,
  })

  local spellIDs = {}
  for _, entry in ipairs(entries or {}) do
    spellIDs[#spellIDs + 1] = entry.spellID
  end

  return spellIDs
end

local function GetEntryRemaining(entry, now)
  if type(entry) ~= "table" then
    return 0
  end

  now = now or GetTime()
  local readyAt = entry.readyAt or 0
  if type(readyAt) ~= "number" or readyAt <= 0 then
    return 0
  end

  return math.max(0, readyAt - now)
end

local function RemovePartyUser(userKey)
  local existing = runtime.partyUsers[userKey]
  runtime.partyUsers[userKey] = nil

  if existing and existing.guid and existing.spellID then
    runtime.engine:RemoveEntry(BuildRuntimeKey(existing.guid, existing.spellID))
  end
end

local function RegisterExpectedCrowdControlEntry(unit, entry, cooldownOverride, options)
  options = options or {}

  if not unit or not UnitExists(unit) or type(entry) ~= "table" then
    return nil
  end

  local guid = UnitGUID(unit)
  local shortName = ShortName(UnitName(unit))
  local _, classToken = UnitClass(unit)
  if not guid or not shortName or not classToken then
    return nil
  end

  local cooldown = cooldownOverride
  if cooldown == nil then
    cooldown = entry.cd or 0
  end

  local userKey = BuildUserKey(shortName, entry.spellID)
  runtime.partyUsers[userKey] = {
    key = userKey,
    guid = guid,
    unitToken = unit,
    playerName = shortName,
    class = classToken,
    spellID = entry.spellID,
    spellName = entry.name,
    baseCd = cooldown,
    essential = entry.essential == true,
    _auto = options.auto == true,
  }

  return runtime.engine:RegisterExpectedEntry({
    key = BuildRuntimeKey(guid, entry.spellID),
    playerGUID = guid,
    playerName = shortName,
    classToken = classToken,
    unitToken = unit,
    spellID = entry.spellID,
    kind = "CC",
    baseCd = cooldown,
    cd = cooldown,
    essential = entry.essential == true,
  })
end

local function RegisterRuntimeCrowdControl(unit, spellID, cooldownOverride, options)
  options = options or {}

  if not unit or not UnitExists(unit) then
    return nil
  end

  local _, classToken = UnitClass(unit)
  if not classToken then
    return nil
  end

  local entries
  if spellID then
    local trackedSpell = GetTrackedCrowdControlInfo(spellID)
    if not trackedSpell then
      return nil
    end

    entries = { trackedSpell }
  else
    entries = Model.GetEligibleCrowdControlEntries(classToken, {
      includeAllKnown = options.includeAllKnown == true,
      isSpellKnown = options.isSpellKnown,
    })
  end

  local lastRegistered = nil
  for _, entry in ipairs(entries or {}) do
    lastRegistered = RegisterExpectedCrowdControlEntry(unit, entry, cooldownOverride, options) or lastRegistered
  end

  return lastRegistered
end

local function UpdateEngineEntryTiming(runtimeKey, source, startTime, readyAt)
  if not runtimeKey then
    return
  end

  runtime.engine:UpsertEntry({
    key = runtimeKey,
    source = source,
    startTime = startTime,
    readyAt = readyAt,
  })
end

local function ApplyRuntimeCooldownEntry(entry)
  if type(entry) ~= "table" or not entry.playerGUID or not entry.spellID then
    return
  end

  local userKey = BuildUserKey(ShortName(entry.playerName), entry.spellID)
  local user = userKey and runtime.partyUsers[userKey] or nil
  local cooldown = GetEntryCooldown(entry)
  local readyAt = entry.readyAt

  if readyAt == nil and entry.startTime ~= nil then
    readyAt = entry.startTime + cooldown
  end

  if user then
    user.guid = entry.playerGUID
    user.unitToken = entry.unitToken or user.unitToken
    user.playerName = ShortName(entry.playerName) or user.playerName
    user.class = entry.classToken or user.class
    user.spellName = entry.name or user.spellName
    user.baseCd = cooldown
    user.essential = entry.essential == true or user.essential == true
    user._auto = entry.source == "auto"
    user.cdEnd = readyAt or 0
  end

  UpdateEngineEntryTiming(entry.key, entry.source, entry.startTime or 0, readyAt or 0)
  MarkTrackerDirty()
end

local function BuildPreviewBars()
  local previewBars = {}
  local now = GetTime()

  for _, previewData in ipairs(Model.BuildPreviewBars()) do
    local startTime = 0
    if (previewData.previewRemaining or 0) > 0 and (previewData.cd or 0) > 0 then
      startTime = now - (previewData.cd - previewData.previewRemaining)
    end

    previewBars[#previewBars + 1] = {
      key = previewData.key,
      name = previewData.name,
      class = previewData.class,
      spellID = previewData.spellID,
      cd = previewData.cd or 0,
      startTime = startTime,
      previewText = previewData.previewText,
      previewValue = previewData.previewValue,
      kind = "CC",
      essential = previewData.essential == true,
    }
  end

  return Model.FilterTrackedEntries(previewBars, db.filterMode)
end

local function BuildRuntimeBarEntries()
  local entries = {}
  local unitsByToken = {}
  local now = GetTime()
  local includeAutoFallbackBars = db.showAutoFallbackBars ~= false

  for _, unit in ipairs(BuildRuntimeUnitsForDisplay()) do
    unitsByToken[unit] = true
  end

  for _, entry in ipairs(Model.FilterTrackedEntries(runtime.engine:GetEntriesByKind("CC"), db.filterMode)) do
    if unitsByToken[entry.unitToken] and UnitExists(entry.unitToken) then
      local shortName = ShortName(entry.playerName or UnitName(entry.unitToken))
      local userKey = BuildUserKey(shortName, entry.spellID)
      local user = userKey and runtime.partyUsers[userKey] or nil
      local cooldown = GetEntryCooldown(entry)
      local readyAt = entry.readyAt or 0
      local startTime = entry.startTime or 0

      if readyAt <= now then
        startTime = 0
      elseif startTime <= 0 and cooldown > 0 then
        startTime = readyAt - cooldown
      end

      local ready = startTime <= 0 or readyAt <= now
      local autoFallbackEntry = entry.source == "auto"
      local isLocalPlayerEntry = entry.unitToken == "player"
      if includeAutoFallbackBars or not autoFallbackEntry or isLocalPlayerEntry then
        if not (ready and db.showReady == false) then
          local labelName = shortName or "Unknown"
          local spellName = (user and user.spellName) or entry.name or (GetTrackedCrowdControlInfo(entry.spellID) or {}).name or "CC"

          entries[#entries + 1] = {
            key = entry.key,
            runtimeKey = entry.key,
            userKey = userKey,
            unit = entry.unitToken,
            partyName = shortName,
            name = labelName .. " - " .. spellName,
            class = entry.classToken or (user and user.class) or select(2, UnitClass(entry.unitToken)),
            spellID = entry.spellID,
            cd = cooldown,
            startTime = startTime,
            source = entry.source,
            kind = "CC",
            essential = entry.essential == true or (user and user.essential == true),
          }
        end
      end
    end
  end

  return Model.SortBars(entries, now)
end

local function ShouldDisplaySoloSelfBar()
  if IsInGroup() or IsInRaid() then
    return false
  end

  for _, entry in ipairs(BuildRuntimeBarEntries()) do
    if entry.unit == "player" then
      return true
    end
  end

  return false
end

local function CanRecordWatcherTimestamp(ownerUnit)
  if not ownerUnit or not UnitExists(ownerUnit) or not UnitIsPlayer(ownerUnit) then
    return false
  end

  local shortName = ShortName(UnitName(ownerUnit))
  local _, classToken = UnitClass(ownerUnit)
  local primary = SpellDB.GetPrimaryCrowdControlForClass(classToken)
  if not shortName or not primary then
    return false
  end

  local user = runtime.partyUsers[BuildUserKey(shortName, primary.spellID)]
  local ccOnCooldown = user and user.cdEnd and (user.cdEnd > GetTime() + 0.5)
  if ccOnCooldown then
    return false
  end

  return true
end

local function HandlePartyWatcher(ownerUnit)
  if not db or not db.enabled or not ownerUnit or not UnitExists(ownerUnit) then
    return
  end

  if not CanRecordWatcherTimestamp(ownerUnit) then
    return
  end

  local shortName = ShortName(UnitName(ownerUnit))
  if shortName and shortName ~= "" then
    runtime.recentPartyCasts[shortName] = GetTime()
    addon:DebugLog("cc", "party cast", shortName)
  end
end

local function ApplyResolvedCrowdControl(resolved)
  if type(resolved) ~= "table" then
    return
  end

  local unit = resolved.ownerUnit
  local spellID = resolved.spellID
  local trackedSpell = GetTrackedCrowdControlInfo(spellID)
  local observedAt = resolved.startTime
  if not unit or unit == "player" or not UnitExists(unit) or type(trackedSpell) ~= "table" then
    return
  end

  local guid = UnitGUID(unit)
  local playerName = ShortName(UnitName(unit))
  local _, classToken = UnitClass(unit)
  if not guid or not playerName or not classToken then
    return
  end

  local cooldown = resolved.baseCd or trackedSpell.cd or 0
  local readyAt = resolved.endTime or (cooldown > 0 and (observedAt + cooldown) or 0)
  local runtimeKey = BuildRuntimeKey(guid, spellID)
  local existing = runtime.engine:GetEntry(runtimeKey)
  if existing and (existing.readyAt or 0) >= readyAt then
    return
  end

  RegisterRuntimeCrowdControl(unit, spellID, cooldown, {
    auto = false,
  })

  local applied = runtime.engine:ApplyCorrelatedCast(guid, spellID, observedAt, readyAt)
  if applied then
    applied.playerName = playerName
    applied.classToken = classToken
    applied.unitToken = unit
    applied.name = trackedSpell.name
    applied.essential = trackedSpell.essential == true
    applied.baseCd = cooldown
    applied.cd = cooldown
    applied.source = resolved.source or applied.source
    applied.confidence = resolved.confidence
    ApplyRuntimeCooldownEntry(applied)
  end
end

local function DetectCrowdControlAuras(unit)
  if not db or not db.enabled or not unit or not UnitExists(unit) then
    return
  end

  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
    return
  end

  local now = GetTime()

  if C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions() then
    local count = 0
    local i = 1
    while i <= 40 do
      local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
      if not ok or not auraData then
        break
      end

      count = count + 1
      i = i + 1
    end

    local prevCount = runtime.ccAuraPrevCount[unit] or 0
    runtime.ccAuraPrevCount[unit] = count
    if count <= prevCount then
      return
    end

    local candidateName = nil
    for name, observedAt in pairs(runtime.recentPartyCasts) do
      if now - observedAt <= 1.5 then
        if candidateName then
          return
        end
        candidateName = name
      else
        runtime.recentPartyCasts[name] = nil
      end
    end

    if not candidateName then
      return
    end

    local candidateUnit = GetUnitBySender(candidateName)
    if not candidateUnit or candidateUnit == "player" then
      return
    end

    local _, classToken = UnitClass(candidateUnit)
    local trackedSpell = classToken and SpellDB.GetPrimaryCrowdControlForClass(classToken) or nil
    if not trackedSpell then
      addon:DebugLog("cc", "corr", "miss", "no-primary", candidateName)
      return
    end

    runtime.recentPartyCasts[candidateName] = nil
    local resolved = crowdControlResolver:ResolveAppliedCrowdControl({
      targetUnit = unit,
      ownerUnit = candidateUnit,
      spellID = trackedSpell.spellID,
      source = "correlated",
    })
    if resolved then
      addon:DebugLog("cc", "corr", candidateName, trackedSpell.spellID, "secret")
      ApplyResolvedCrowdControl(resolved)
    end
    return
  end

  local playerName = ShortName(UnitName("player"))
  local i = 1
  while i <= 40 do
    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
    if not ok or not auraData then
      break
    end

    local spellID = auraData.spellId
    local spellIsSecret = (issecretvalue ~= nil) and spellID and issecretvalue(spellID)
    if spellID and not spellIsSecret then
      local trackedSpell = GetTrackedCrowdControlInfo(spellID)
      if trackedSpell then
        local sourceUnit = auraData.sourceUnit
        local okName, sourceName = pcall(UnitName, sourceUnit)
        if okName and sourceName then
          local sourceShortName = ShortName(sourceName)
          if sourceShortName and sourceShortName ~= playerName then
            local sourcePartyUnit = GetUnitBySender(sourceShortName)
            if sourcePartyUnit and sourcePartyUnit ~= "player" then
              local resolved = crowdControlResolver:ResolveAppliedCrowdControl({
                targetUnit = unit,
                spellID = spellID,
                sourceUnit = sourcePartyUnit,
                source = "aura",
              })
              if resolved then
                addon:DebugLog("cc", "corr", sourceShortName, spellID, "aura")
                ApplyResolvedCrowdControl(resolved)
              end
            end
          end
        end
      end
    end

    i = i + 1
  end
end

local ccAuraUnits = { "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
for _, au in ipairs(ccAuraUnits) do
  local frame = CreateFrame("Frame")
  frame:RegisterUnitEvent("UNIT_AURA", au)
  frame:SetScript("OnEvent", function(_, _, unitToken)
    DetectCrowdControlAuras(unitToken or au)
  end)
end

local function AnnouncePresence()
  if not db or not db.enabled or not IsInGroup() then
    return
  end

  local _, classToken = UnitClass("player")
  runtime.lastHelloAt = GetTime()
  Sync.Send("HELLO", {
    classToken = classToken or "UNKNOWN",
    specID = GetLocalPlayerSpecID(),
  })
  Sync.Send("CC_MANIFEST", {
    spells = GetLocalCrowdControlManifest(),
  })
  local playerGUID = UnitGUID("player")
  if playerGUID then
    for _, entry in ipairs(runtime.engine:GetEntriesByKind("CC")) do
      if entry.playerGUID == playerGUID then
        local remaining = GetEntryRemaining(entry)
        if remaining > 0 then
          Sync.Send("CC", {
            spellID = entry.spellID,
            cd = entry.baseCd or entry.cd or 0,
            remaining = remaining,
          })
        end
      end
    end
  end
end

local function HandleSyncHelloMessage(payload, sender)
  if not db or not db.enabled then
    return
  end

  local unit = GetUnitBySender(sender)
  if not unit or unit == "player" then
    return
  end

  local senderShort = ShortName(sender)
  if senderShort and senderShort ~= "" then
    runtime.partyAddonUsers[senderShort] = true
    GetManifestForUser(senderShort)
  end

  RegisterRuntimeCrowdControl(unit, nil, nil, {
    auto = true,
  })

  if runtime.lastHelloAt <= 0 or (GetTime() - runtime.lastHelloAt) > 5 then
    AnnouncePresence()
    return
  end

  local playerGUID = UnitGUID("player")
  if playerGUID then
    for _, entry in ipairs(runtime.engine:GetEntriesByKind("CC")) do
      if entry.playerGUID == playerGUID then
        local remaining = GetEntryRemaining(entry)
        if remaining > 0 then
          Sync.Send("CC", {
            spellID = entry.spellID,
            cd = entry.baseCd or entry.cd or 0,
            remaining = remaining,
          })
        end
      end
    end
  end
end

local function PruneManifestCrowdControl(shortName, spellSet)
  for userKey, data in pairs(runtime.partyUsers) do
    if data.playerName == shortName and not spellSet[data.spellID] then
      RemovePartyUser(userKey)
    end
  end
end

local function HandleSyncCrowdControlManifestMessage(payload, sender)
  if not db or not db.enabled then
    return
  end

  local unit = GetUnitBySender(sender)
  if not unit or unit == "player" then
    return
  end

  local senderShort = ShortName(sender)
  if not senderShort or senderShort == "" then
    return
  end

  runtime.partyAddonUsers[senderShort] = true
  local manifest = GetManifestForUser(senderShort)
  manifest.spellList = {}
  for _, spellID in ipairs(payload and payload.spells or {}) do
    local trackedSpell = GetTrackedCrowdControlInfo(spellID)
    if trackedSpell then
      manifest.spellList[#manifest.spellList + 1] = spellID
      RegisterRuntimeCrowdControl(unit, spellID, trackedSpell.cd, {
        auto = false,
      })
    end
  end

  manifest.spells = BuildSpellSet(manifest.spellList)
  manifest.received = true
  PruneManifestCrowdControl(senderShort, manifest.spells)
end

local function HandleSyncCrowdControlMessage(message, sender)
  if not db or not db.enabled then
    return
  end

  local messageType, payload = Sync.Decode(message)
  if messageType == "HELLO" then
    HandleSyncHelloMessage(payload, sender)
    return
  end

  if messageType == "CC_MANIFEST" then
    HandleSyncCrowdControlManifestMessage(payload, sender)
    return
  end

  if messageType ~= "CC" then
    return
  end

  local unit = GetUnitBySender(sender)
  if not unit or unit == "player" then
    return
  end

  local senderShort = ShortName(sender)
  if senderShort and senderShort ~= "" then
    runtime.partyAddonUsers[senderShort] = true
  end

  local spellID = payload.spellID or 0
  local cooldown = payload.cd or 0
  if spellID <= 0 then
    return
  end

  if HasAuthoritativeManifest(senderShort) and not HasManifestSpell(senderShort, spellID) then
    return
  end

  local now = GetTime()
  local remaining = payload.remaining
  if type(remaining) ~= "number" or remaining < 0 then
    remaining = cooldown
  end

  local readyAt = remaining > 0 and (now + remaining) or 0
  local startTime = 0
  if readyAt > 0 and cooldown > 0 then
    startTime = readyAt - cooldown
  end

  RegisterRuntimeCrowdControl(unit, spellID, cooldown, {
    auto = false,
    startTime = startTime,
  })

  local applied = runtime.engine:ApplySyncState(UnitGUID(unit), spellID, {
    kind = "CC",
    cd = cooldown,
    remaining = remaining,
    observedAt = now,
  })
  if applied then
    applied.playerName = ShortName(UnitName(unit))
    applied.classToken = select(2, UnitClass(unit))
    applied.unitToken = unit
    local tracked = GetTrackedCrowdControlInfo(spellID)
    if tracked then
      applied.name = tracked.name
      applied.essential = tracked.essential == true
      applied.baseCd = tracked.cd
      applied.cd = tracked.cd
    end
    ApplyRuntimeCooldownEntry(applied)
  end
end

local function PrunePlayerKnownCrowdControl()
  local playerName = ShortName(UnitName("player"))
  local _, classToken = UnitClass("player")
  if not playerName or not classToken then
    return
  end

  local knownSpells = {}
  for _, entry in ipairs(Model.GetEligibleCrowdControlEntries(classToken, {
    includeAllKnown = true,
    isSpellKnown = function(spellID)
      return not IsSpellKnown or IsSpellKnown(spellID)
    end,
  })) do
    knownSpells[entry.spellID] = true
  end

  for userKey, data in pairs(runtime.partyUsers) do
    if data.playerName == playerName and data.unitToken == "player" and not knownSpells[data.spellID] then
      RemovePartyUser(userKey)
    end
  end
end

local function PruneRuntimeRoster()
  local currentNames = {}
  local currentGuids = {}
  local playerName = ShortName(UnitName("player"))
  local playerGUID = UnitGUID("player")

  if playerName and playerName ~= "" then
    currentNames[playerName] = true
  end
  if playerGUID then
    currentGuids[playerGUID] = true
  end

  if IsInGroup() then
    for _, unit in ipairs(GetRuntimeUnits()) do
      if UnitExists(unit) then
        local name = ShortName(UnitName(unit))
        local guid = UnitGUID(unit)
        if name and name ~= "" then
          currentNames[name] = true
        end
        if guid then
          currentGuids[guid] = true
        end
      end
    end
  end

  for userKey, data in pairs(runtime.partyUsers) do
    if not currentNames[data.playerName] then
      RemovePartyUser(userKey)
    end
  end

  for name in pairs(runtime.recentPartyCasts) do
    if not currentNames[name] then
      runtime.recentPartyCasts[name] = nil
    end
  end

  for name in pairs(runtime.partyAddonUsers) do
    if not currentNames[name] then
      runtime.partyAddonUsers[name] = nil
    end
  end

  for name in pairs(runtime.partyManifests) do
    if not currentNames[name] then
      runtime.partyManifests[name] = nil
    end
  end

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("CC")) do
    if not currentGuids[entry.playerGUID] then
      runtime.engine:RemoveEntry(entry.key)
    end
  end

  PrunePlayerKnownCrowdControl()
end

local function RefreshRuntimeCrowdControlRegistration()
  RegisterRuntimeCrowdControl("player", nil, nil, {
    auto = false,
    includeAllKnown = true,
    isSpellKnown = function(spellID)
      return not IsSpellKnown or IsSpellKnown(spellID)
    end,
  })

  if not IsInGroup() or IsInRaid() then
    return
  end

  for i = 1, 4 do
    local unit = "party" .. i
    if UnitExists(unit) then
      RegisterRuntimeCrowdControl(unit, nil, nil, {
        auto = true,
      })
    end
  end
end

local function UpdateAnchorVisuals(enabled)
  local anchor = module.anchor or container
  TrackerFrame.UpdateEditModeVisuals(anchor, enabled, UpdateEditLabelVisibility)
end

function module:SetEditMode(enabled)
  editModePreview = enabled and true or false
  if db and db.enabled then
    CreateContainer()
    UpdatePartyData()
  end
  UpdateAnchorVisuals(enabled)
end

function module:ResetPosition(moduleDB)
  moduleDB = moduleDB or db or (addon.db and addon.db.modules and addon.db.modules.CrowdControlTracker)
  if not moduleDB then return end

  FramePositioning.ResetToDefault(self.anchor or container, moduleDB, defaultPosX, defaultPosY)
end

function module:buildSettings(panel, helpers, addonRef, moduleDB)
  db = moduleDB

  local function GetEditButtonLabel()
    if addonRef.db.global.editMode and (
      addonRef.db.global.activeEditModule == "CrowdControlTracker"
      or addonRef.db.global.activeEditModule == "ALL"
    ) then
      return "Lock Tracker"
    end

    return "Open Edit Mode"
  end

  local filterOptions = {
    { label = "M+ Essentials", value = "ESSENTIALS" },
    { label = "All CC", value = "ALL" },
  }

  local stateLabel = helpers:CreateDividerLabel(panel, "State", nil, 0)
  local stateBody = helpers:CreateSectionHint(panel, "Enable the tracker and place it where you want it.", 520)
  stateBody:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)

  local enabledBox = helpers:CreateInlineCheckbox(panel, "Enable Crowd Control Tracker", moduleDB.enabled, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "enabled", value)
  end)
  enabledBox:SetPoint("TOPLEFT", stateBody, "BOTTOMLEFT", 0, -12)

  local editButton = helpers:CreateActionButton(panel, GetEditButtonLabel(), function(self)
    local isActive = addonRef.db.global.editMode and (
      addonRef.db.global.activeEditModule == "CrowdControlTracker"
      or addonRef.db.global.activeEditModule == "ALL"
    )
    addonRef:SetEditMode(not isActive, isActive and nil or "CrowdControlTracker")
    self:SetText(GetEditButtonLabel())
    addonRef:RefreshSettings()
  end)

  local resetButton = helpers:CreateActionButton(panel, "Reset Position", function()
    module:ResetPosition(moduleDB)
  end)
  helpers:PlaceRow(enabledBox, editButton, resetButton, -12, 12)

  local stateHint = helpers:CreateSectionHint(panel, "Edit mode lets you move this tracker.", 420)
  stateHint:SetPoint("TOPLEFT", editButton, "BOTTOMLEFT", 0, -12)

  local behaviorColumn, layoutColumn = helpers:CreateSectionColumns(panel, stateHint, -24)

  local behaviorLabel = helpers:CreateDividerLabel(behaviorColumn, "Behavior", nil, 0)
  local behaviorBody = helpers:CreateSectionHint(behaviorColumn, "Preview, visibility, and filter options.", 250)
  behaviorBody:SetPoint("TOPLEFT", behaviorLabel, "BOTTOMLEFT", 0, -8)

  local showReadyBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show Ready Bars", moduleDB.showReady ~= false, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "showReady", value)
  end)
  showReadyBox:SetPoint("TOPLEFT", behaviorBody, "BOTTOMLEFT", 0, -12)

  local hideOutOfCombatBox = helpers:CreateInlineCheckbox(behaviorColumn, "Hide Out of Combat", moduleDB.hideOutOfCombat, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "hideOutOfCombat", value)
  end)
  hideOutOfCombatBox:SetPoint("TOPLEFT", showReadyBox, "BOTTOMLEFT", 0, -8)

  local tooltipBox = helpers:CreateInlineCheckbox(behaviorColumn, "Tooltip on Hover", moduleDB.tooltipOnHover ~= false, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "tooltipOnHover", value)
  end)
  tooltipBox:SetPoint("TOPLEFT", hideOutOfCombatBox, "BOTTOMLEFT", 0, -8)

  local filterModeDropdown = helpers:CreateLabeledDropdown(
    behaviorColumn,
    "Filter Mode",
    filterOptions,
    moduleDB.filterMode,
    210,
    function(value)
      addonRef:SetModuleValue("CrowdControlTracker", "filterMode", value)
    end
  )
  filterModeDropdown:SetPoint("TOPLEFT", tooltipBox, "BOTTOMLEFT", 0, -10)

  local showInDungeonBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show in Dungeons", moduleDB.showInDungeon ~= false, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "showInDungeon", value)
  end)
  showInDungeonBox:SetPoint("TOPLEFT", filterModeDropdown, "BOTTOMLEFT", 0, -10)

  local showInWorldBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show in World", moduleDB.showInWorld ~= false, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "showInWorld", value)
  end)
  showInWorldBox:SetPoint("TOPLEFT", showInDungeonBox, "BOTTOMLEFT", 0, -8)

  local behaviorHint = helpers:CreateSectionHint(
    behaviorColumn,
    "Choose a dungeon-focused set or the full list. SunderingTools handles sync and fallback automatically.",
    250
  )
  behaviorHint:SetPoint("TOPLEFT", showInWorldBox, "BOTTOMLEFT", 0, -12)

  local layoutLabel = helpers:CreateDividerLabel(layoutColumn, "Layout", nil, 0)
  local layoutBody = helpers:CreateSectionHint(layoutColumn, "Adjust size, spacing, and growth.", 250)
  layoutBody:SetPoint("TOPLEFT", layoutLabel, "BOTTOMLEFT", 0, -8)

  local showHeaderBox = helpers:CreateInlineCheckbox(layoutColumn, "Show Header", moduleDB.showHeader ~= false, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "showHeader", value)
  end)
  showHeaderBox:SetPoint("TOPLEFT", layoutBody, "BOTTOMLEFT", 0, -12)

  local growDirectionDropdown = helpers:CreateLabeledDropdown(
    layoutColumn,
    "Grow Direction",
    { "DOWN", "UP" },
    moduleDB.growDirection,
    210,
    function(value)
      addonRef:SetModuleValue("CrowdControlTracker", "growDirection", value)
    end
  )
  growDirectionDropdown:SetPoint("TOPLEFT", showHeaderBox, "BOTTOMLEFT", 0, -10)

  local maxBarsSlider = helpers:CreateLabeledSlider(layoutColumn, "Maximum Bars", 1, 12, 1, moduleDB.maxBars, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "maxBars", value)
  end, 250)
  maxBarsSlider:SetPoint("TOPLEFT", growDirectionDropdown, "BOTTOMLEFT", 0, -10)

  local spacingSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Spacing", 0, 12, 1, moduleDB.spacing, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "spacing", value)
  end, 250)
  spacingSlider:SetPoint("TOPLEFT", maxBarsSlider, "BOTTOMLEFT", 0, -10)

  local barWidthSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Width", 100, 320, 5, moduleDB.barWidth, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "barWidth", value)
  end, 250)
  barWidthSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -10)

  local barHeightSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Height", 16, 40, 1, moduleDB.barHeight, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "barHeight", value)
  end, 250)
  barHeightSlider:SetPoint("TOPLEFT", barWidthSlider, "BOTTOMLEFT", 0, -10)

  local iconSizeSlider = helpers:CreateLabeledSlider(layoutColumn, "Icon Size", 14, 32, 1, moduleDB.iconSize, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "iconSize", value)
  end, 250)
  iconSizeSlider:SetPoint("TOPLEFT", barHeightSlider, "BOTTOMLEFT", 0, -10)

  local fontSizeSlider = helpers:CreateLabeledSlider(layoutColumn, "Font Size", 8, 18, 1, moduleDB.fontSize, function(value)
    addonRef:SetModuleValue("CrowdControlTracker", "fontSize", value)
  end, 250)
  fontSizeSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -10)
end

function module:onConfigChanged(addonRef, moduleDB, key)
  db = moduleDB

  if key == "enabled" then
    if moduleDB.enabled then
      CreateContainer()
      UpdateAnchorVisuals(addonRef.db.global.editMode)
      UpdatePartyData()
    elseif container then
      container:Hide()
    end
    return
  end

  if key == "posX" or key == "posY" then
    FramePositioning.ApplySavedPosition(self.anchor or container, moduleDB, defaultPosX, defaultPosY)
    return
  end

  if not moduleDB.enabled then
    return
  end

  if key == "maxBars" then
    CreateContainer()
    UpdatePartyData()
    return
  end

  if key == "growDirection"
    or key == "spacing"
    or key == "barWidth"
    or key == "barHeight"
    or key == "iconSize"
    or key == "fontSize"
    or key == "showHeader"
    or key == "previewWhenSolo"
    or key == "showInDungeon"
    or key == "showInWorld"
    or key == "hideOutOfCombat"
    or key == "showReady"
    or key == "tooltipOnHover"
    or key == "filterMode" then
    CreateContainer()
    UpdatePartyData()
  end
end

local function CreateBar(index)
  local bar = CreateFrame("Frame", nil, container)
  bar:SetSize(db.barWidth, db.barHeight)

  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

  bar.icon = bar:CreateTexture(nil, "ARTWORK")
  bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  bar.iconBorder = bar:CreateTexture(nil, "BORDER")
  bar.iconBorder:SetColorTexture(0, 0, 0, 1)

  bar.borderTop = bar:CreateTexture(nil, "BORDER")
  bar.borderBottom = bar:CreateTexture(nil, "BORDER")
  bar.borderRight = bar:CreateTexture(nil, "BORDER")
  bar.separator = bar:CreateTexture(nil, "BORDER")

  bar.cooldown = CreateFrame("StatusBar", nil, bar)
  bar.cooldown:SetMinMaxValues(0, 1)
  bar.cooldown:SetValue(0)
  bar.cooldown:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  bar.cooldown.bg = bar.cooldown:CreateTexture(nil, "BACKGROUND")
  bar.cooldown.bg:SetAllPoints()
  bar.cooldown.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

  bar.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bar.nameText:SetJustifyH("LEFT")
  bar.nameText:SetJustifyV("MIDDLE")

  bar.cooldownNameText = bar.cooldown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bar.cooldownNameText:SetJustifyH("LEFT")
  bar.cooldownNameText:SetJustifyV("MIDDLE")

  bar.cooldownText = bar.cooldown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  bar.cooldownText:SetJustifyH("RIGHT")
  bar.cooldownText:SetJustifyV("MIDDLE")
  bar.timerText = bar.cooldownText

  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self)
    if not db or db.tooltipOnHover == false then return end
    local data = self._trackerData
    if not data then return end

    local trackedSpell = GetTrackedCrowdControlInfo(data.spellID)
    local now = GetTime()
    local ready = data.startTime == 0 or (now - data.startTime) >= (data.cd or 0)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(data.partyName or data.name or "Unknown", 1, 1, 1)
    if trackedSpell and trackedSpell.name then
      GameTooltip:AddLine(trackedSpell.name, 1, 1, 1)
    end
    if ready then
      GameTooltip:AddLine("Status: Ready", 0.2, 0.95, 0.3)
    else
      local remaining = math.max(0, (data.cd or 0) - (now - data.startTime))
      GameTooltip:AddLine(string.format("Cooldown: %.0fs", remaining), 0.95, 0.6, 0.15)
    end
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

  bar:Hide()
  return bar
end

local function ConfigureBar(bar)
  if not bar or not db then return end

  local borderSize = 1
  local iconSize = math.min(db.iconSize, db.barHeight)
  local statusLeft = iconSize + 3

  bar:SetSize(db.barWidth, db.barHeight)
  bar.icon:SetSize(iconSize, iconSize)
  bar.icon:ClearAllPoints()
  bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

  bar.iconBorder:ClearAllPoints()
  bar.iconBorder:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 0, 0)
  bar.iconBorder:SetPoint("BOTTOMLEFT", bar.icon, "BOTTOMRIGHT", 0, 0)
  bar.iconBorder:SetWidth(borderSize)

  bar.bg:ClearAllPoints()
  bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", statusLeft, 0)
  bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

  bar.borderTop:ClearAllPoints()
  bar.borderTop:SetPoint("TOPLEFT", bar, "TOPLEFT", statusLeft, 0)
  bar.borderTop:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  bar.borderTop:SetHeight(borderSize)
  bar.borderTop:SetColorTexture(0, 0, 0, 1)

  bar.borderBottom:ClearAllPoints()
  bar.borderBottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", statusLeft, 0)
  bar.borderBottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  bar.borderBottom:SetHeight(borderSize)
  bar.borderBottom:SetColorTexture(0, 0, 0, 1)

  bar.borderRight:ClearAllPoints()
  bar.borderRight:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -borderSize)
  bar.borderRight:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, borderSize)
  bar.borderRight:SetWidth(borderSize)
  bar.borderRight:SetColorTexture(0, 0, 0, 1)

  bar.separator:ClearAllPoints()
  bar.separator:SetPoint("TOPLEFT", bar, "TOPLEFT", statusLeft, borderSize)
  bar.separator:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", statusLeft, -borderSize)
  bar.separator:SetWidth(borderSize)
  bar.separator:SetColorTexture(0, 0, 0, 1)

  bar.cooldown:ClearAllPoints()
  bar.cooldown:SetPoint("TOPLEFT", bar, "TOPLEFT", statusLeft, -borderSize)
  bar.cooldown:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -borderSize, borderSize)
  bar.cooldown.bg:SetColorTexture(0.14, 0.14, 0.16, 0.85)

  bar.nameText:ClearAllPoints()
  bar.nameText:SetPoint("LEFT", bar, "LEFT", statusLeft + 5, 0)
  bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
  bar.nameText:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
  bar.nameText:SetShadowOffset(1, -1)

  bar.cooldownNameText:ClearAllPoints()
  bar.cooldownNameText:SetPoint("LEFT", bar.cooldown, "LEFT", 5, 0)
  bar.cooldownNameText:SetPoint("RIGHT", bar.cooldownText, "LEFT", -5, 0)
  bar.cooldownNameText:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
  bar.cooldownNameText:SetShadowOffset(1, -1)

  bar.cooldownText:ClearAllPoints()
  bar.cooldownText:SetPoint("RIGHT", bar.cooldown, "RIGHT", -5, 0)
  bar.cooldownText:SetFont("Fonts\\FRIZQT__.TTF", db.fontSize, "OUTLINE")
  bar.cooldownText:SetShadowOffset(1, -1)
end

local function RefreshContainerGeometry()
  if not container or not db then return end

  local visibleCount = math.max(1, math.min(db.maxBars, #usedBarsList))
  local totalHeight = (visibleCount * db.barHeight) + (math.max(0, visibleCount - 1) * db.spacing)
  container:SetSize(db.barWidth, math.max(db.barHeight, totalHeight))
  RefreshHeaderLayout()
end

EnsureBarPool = function()
  if not container or not db then return end

  for index = 1, db.maxBars do
    if not bars[index] then
      bars[index] = CreateBar(index)
    end
  end

  for index = db.maxBars + 1, #bars do
    if bars[index] then
      bars[index]:Hide()
    end
  end
end

ConfigureBarPool = function()
  if not container or not db then return end

  EnsureBarPool()
  for index = 1, db.maxBars do
    if bars[index] then
      ConfigureBar(bars[index])
    end
  end

  RefreshContainerGeometry()
end

UpdateBarVisuals = function(bar, data)
  if not bar or not data then return end

  local now = GetTime()
  local isReady = data.startTime == 0 or (now - data.startTime) >= (data.cd or 0)
  local remaining = math.max(0, (data.cd or 0) - (now - data.startTime))
  local progress = 0
  local classColor
  local textOffset = GetIconOffset() + 5
  local readyTextColor = { 1.0, 0.84, 0.22 }
  local activeTextColor = { 1.0, 0.94, 0.74 }

  if UsesClassColor(db) and data.class then
    classColor = Model.GetClassColor and Model.GetClassColor(data.class) or nil
  end
  if not classColor then
    classColor = { 0.45, 0.45, 0.45 }
  end

  if not isReady and (data.cd or 0) > 0 then
    progress = math.max(0, math.min(1, 1 - (remaining / data.cd)))
  end

  bar.icon:SetTexture(GetCachedSpellTexture(data.spellID))
  bar.icon:Show()
  bar.nameText:SetText(data.name or "")
  bar.cooldownNameText:SetText(data.name or "")

  if isReady then
    bar.bg:Show()
    bar.cooldown:Hide()
    bar.bg:SetVertexColor(BlendColor(classColor, 0.18, 0.95))
    bar.nameText:SetTextColor(readyTextColor[1], readyTextColor[2], readyTextColor[3])
    bar.nameText:Show()
    bar.cooldownNameText:Hide()
    bar.nameText:ClearAllPoints()
    bar.nameText:SetPoint("LEFT", bar, "LEFT", textOffset, 0)
    bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bar.cooldownText:SetText("")
    bar.cooldownText:Hide()
  else
    bar.bg:Hide()
    bar.cooldown:Show()
    bar.cooldown:SetStatusBarColor(BlendColor(classColor, 0.14, 1))
    bar.cooldown:SetValue(data.previewValue or progress)
    bar.nameText:Hide()
    bar.cooldownNameText:SetTextColor(activeTextColor[1], activeTextColor[2], activeTextColor[3])
    bar.cooldownNameText:Show()
    bar.cooldownText:SetText(Model.FormatTimerText(remaining))
    bar.cooldownText:SetTextColor(activeTextColor[1], activeTextColor[2], activeTextColor[3])
    bar.cooldownText:Show()
  end
end

local function SortBars()
  local sortList = {}
  for _, data in pairs(activeBars) do
    table.insert(sortList, data)
  end

  Model.SortBars(sortList, GetTime())

  wipe(usedBarsList)
  for _, data in ipairs(sortList) do
    table.insert(usedBarsList, data)
  end
end

ReLayout = function()
  if not container then return end

  EnsureBarPool()
  SortBars()
  RefreshContainerGeometry()

  local spacing = db.spacing
  local growUp = (db.growDirection == "UP")
  local growKey = string.format("%s:%d:%d", db.growDirection or "DOWN", db.barHeight or 0, spacing or 0)
  local maxLimit = db.maxBars

  for i, data in ipairs(usedBarsList) do
    if i > maxLimit then
      data.bar:Hide()
    else
      local bar = data.bar
      local yOffset = (i - 1) * (db.barHeight + spacing)
      if growUp then
        yOffset = -yOffset
      end

      if bar._lastLayoutIndex ~= i or bar._lastGrowKey ~= growKey then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOffset)
        bar._lastLayoutIndex = i
        bar._lastGrowKey = growKey
      end
      bar:Show()
    end
  end

  for index = #usedBarsList + 1, #bars do
    if bars[index] then
      bars[index]:Hide()
    end
  end

  UpdateContainerVisibility()
  UpdateEditLabelVisibility(addon.db and addon.db.global and addon.db.global.editMode)
end

CreateContainer = function()
  if container then
    FramePositioning.ApplySavedPosition(container, db, defaultPosX, defaultPosY)
    ConfigureBarPool()
    return
  end

  container = TrackerFrame.CreateContainerShell(
    "SunderingToolsCrowdControlTracker",
    "Crowd Control Tracker",
    function()
      container:StartMoving()
    end,
    function()
      container:StopMovingOrSizing()
      FramePositioning.SaveAbsolutePosition(container, db)
    end
  )
  container.header = CreateFrame("Frame", nil, container)
  container.header.bg = container.header:CreateTexture(nil, "BACKGROUND")
  container.header.borderTop = container.header:CreateTexture(nil, "BORDER")
  container.header.borderBottom = container.header:CreateTexture(nil, "BORDER")
  container.header.icon = container.header:CreateTexture(nil, "ARTWORK")
  container.header.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  container.header.title = container.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  container.header.title:SetJustifyH("CENTER")
  container.header.title:SetJustifyV("MIDDLE")
  container:SetSize(db.barWidth, db.barHeight * db.maxBars)
  FramePositioning.ApplySavedPosition(container, db, defaultPosX, defaultPosY)

  ConfigureBarPool()
  RefreshHeaderLayout()

  module.anchor = container
  UpdateAnchorVisuals(addon.db and addon.db.global and addon.db.global.editMode)
end

local function ResetActiveBars()
  if trackerTicker then
    trackerTicker:Cancel()
    trackerTicker = nil
  end

  for _, data in pairs(activeBars) do
    if data.bar then
      data.bar._trackerData = nil
      data.bar._lastDisplayed = nil
      data.bar:Hide()
    end
  end

  wipe(activeBars)
  wipe(usedBarsList)
end

local HandleCooldownReady

local function RefreshActiveCooldownBars()
  if runtime.needsVisualRefresh then
    FlushDirtyTracker()
    return
  end

  local anyCooling = false
  local needsLayout = false
  local needsRefresh = false

  for _, data in pairs(activeBars) do
    local bar = data.bar
    if bar and (data.startTime or 0) > 0 and (data.cd or 0) > 0 then
      local liveElapsed = GetTime() - data.startTime
      local liveRemaining = data.cd - liveElapsed

      if liveRemaining > 0 then
        anyCooling = true
        bar.cooldown:SetValue(liveElapsed / data.cd)

        local displayText = Model.FormatTimerText(liveRemaining)
        if displayText ~= bar._lastDisplayed then
          bar._lastDisplayed = displayText
          bar.cooldownText:SetText(displayText)
        end
      else
        if HandleCooldownReady and HandleCooldownReady(data, bar) then
          needsLayout = true
        else
          needsRefresh = true
        end
      end
    end
  end

  if needsRefresh then
    UpdatePartyData()
    return
  end

  if needsLayout then
    ReLayout()
  end

  if not anyCooling and trackerTicker then
    trackerTicker:Cancel()
    trackerTicker = nil
  end
end

local function StartTrackerTicker()
  if trackerTicker or not (C_Timer and C_Timer.NewTicker) then
    return
  end

  trackerTicker = C_Timer.NewTicker(1, function()
    RefreshActiveCooldownBars()
  end)
end

StartCooldownTicker = function(bar, data)
  if not bar or not data then return end

  local startTime = data.startTime or 0
  local cdDuration = data.cd or 0
  local elapsed = GetTime() - startTime
  local remaining = cdDuration - elapsed

  bar._lastDisplayed = nil

  if startTime <= 0 or cdDuration <= 0 or remaining <= 0 then
    data.startTime = 0
    if data.userKey and runtime.partyUsers[data.userKey] then
      runtime.partyUsers[data.userKey].cdEnd = 0
    end
    UpdateEngineEntryTiming(data.runtimeKey, data.source, 0, 0)
    UpdateBarVisuals(bar, data)
    return
  end

  bar.cooldown:SetValue(math.max(0, math.min(1, elapsed / cdDuration)))
  bar._lastDisplayed = Model.FormatTimerText(remaining)
  UpdateBarVisuals(bar, data)
  StartTrackerTicker()
end

HandleCooldownReady = function(data, bar)
  if not data or not bar then
    return false
  end

  bar.cooldown:SetValue(1)
  data.startTime = 0
  if data.userKey and runtime.partyUsers[data.userKey] then
    runtime.partyUsers[data.userKey].cdEnd = 0
  end
  UpdateEngineEntryTiming(data.runtimeKey, data.source, 0, 0)
  if db.showReady == false then
    bar._lastDisplayed = nil
    return false
  end

  bar.cooldownText:SetText("")
  bar._lastDisplayed = nil
  UpdateBarVisuals(bar, data)
  return true
end

local function PopulateBars(entries)
  ResetActiveBars()

  local barIndex = 1
  for _, entry in ipairs(entries) do
    if barIndex > db.maxBars or barIndex > #bars then
      break
    end

    local bar = bars[barIndex]
    local barData = {
      key = entry.key,
      runtimeKey = entry.runtimeKey,
      userKey = entry.userKey,
      bar = bar,
      unit = entry.unit,
      partyName = entry.partyName,
      name = entry.name,
      class = entry.class,
      spellID = entry.spellID,
      cd = entry.cd,
      startTime = entry.startTime or 0,
      previewText = entry.previewText,
      previewValue = entry.previewValue,
      source = entry.source,
      kind = "CC",
      essential = entry.essential == true,
    }

    activeBars[barData.key] = barData
    bar._trackerData = barData
    bar._lastDisplayed = nil
    UpdateBarVisuals(bar, barData)
    if (barData.startTime or 0) > 0 then
      StartCooldownTicker(bar, barData)
    end
    barIndex = barIndex + 1
  end

  ReLayout()
end

UpdatePartyData = function()
  if not container then return end

  EnsureBarPool()

  if ShouldShowPreview() then
    PopulateBars(BuildPreviewBars())
    return
  end

  if not IsCurrentInstanceAllowed() or ShouldHideForCombat() then
    ResetActiveBars()
    ReLayout()
    return
  end

  if not IsInGroup() and not ShouldDisplaySoloSelfBar() then
    ResetActiveBars()
    ReLayout()
    return
  end

  PopulateBars(BuildRuntimeBarEntries())
end

for i = 1, 4 do
  runtime.partyWatchFrames[i] = CreateFrame("Frame")
  runtime.partyPetWatchFrames[i] = CreateFrame("Frame")
end

RegisterPartyWatchers = function()
  for i = 1, 4 do
    local unit = "party" .. i
    local petUnit = "partypet" .. i
    local ownerUnit = unit

    runtime.partyWatchFrames[i]:UnregisterAllEvents()
    runtime.partyPetWatchFrames[i]:UnregisterAllEvents()

    if UnitExists(unit) then
      runtime.partyWatchFrames[i]:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
      runtime.partyWatchFrames[i]:SetScript("OnEvent", function()
        HandlePartyWatcher(unit)
      end)
    end

    if UnitExists(petUnit) then
      runtime.partyPetWatchFrames[i]:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", petUnit)
      runtime.partyPetWatchFrames[i]:SetScript("OnEvent", function()
        HandlePartyWatcher(ownerUnit)
      end)
    end
  end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    db = addon.db and addon.db.CrowdControlTracker
    Sync.RegisterPrefix()

    if db and db.enabled then
      CreateContainer()
      UpdatePartyData()
    end

  elseif event == "PLAYER_ENTERING_WORLD" then
    wipe(runtime.partyUsers)
    wipe(runtime.partyAddonUsers)
    wipe(runtime.partyManifests)
    wipe(runtime.recentPartyCasts)
    wipe(runtime.ccAuraPrevCount)
    runtime.engine:Reset()
    runtime.lastHelloAt = 0
    runtime.needsVisualRefresh = false
    runtime.visualRefreshScheduled = false
    addon:DebugLog("cc", "reset runtime", "PLAYER_ENTERING_WORLD")

    AfterDelay(0.3, function()
      RefreshRuntimeCrowdControlRegistration()
      if db and db.enabled then
        UpdatePartyData()
      end
    end)
    AfterDelay(0.5, function()
      RegisterPartyWatchers()
      RefreshRuntimeCrowdControlRegistration()
    end)
    AfterDelay(1.5, function()
      if IsInGroup() then
        AnnouncePresence()
      end
    end)

  elseif event == "CHALLENGE_MODE_START" then
    wipe(runtime.partyAddonUsers)
    wipe(runtime.partyManifests)
    wipe(runtime.recentPartyCasts)
    wipe(runtime.ccAuraPrevCount)
    runtime.lastHelloAt = 0
    runtime.needsVisualRefresh = false
    runtime.visualRefreshScheduled = false
    addon:DebugLog("cc", "reset runtime", "CHALLENGE_MODE_START")
    AfterDelay(0.5, function()
      RegisterPartyWatchers()
      RefreshRuntimeCrowdControlRegistration()
    end)
    AfterDelay(1.0, function()
      if IsInGroup() then
        AnnouncePresence()
      end
    end)
    AfterDelay(4.0, function()
      if IsInGroup() then
        AnnouncePresence()
      end
    end)

  elseif event == "GROUP_ROSTER_UPDATE" then
    addon:DebugLog("cc", "group roster update")
    PruneRuntimeRoster()
    RegisterPartyWatchers()
    RefreshRuntimeCrowdControlRegistration()
    AfterDelay(1.5, function()
      if IsInGroup() then
        AnnouncePresence()
      end
    end)

    if db and db.enabled then
      UpdatePartyData()
    end

  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    if db and db.enabled then
      UpdatePartyData()
    end

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if not db or not db.enabled then return end

    local unit, _, spellID = ...
    if unit ~= "player" then return end
    if type(spellID) ~= "number" then return end

    local trackedSpell = GetTrackedCrowdControlInfo(spellID)
    if not trackedSpell then
      return
    end

    local now = GetTime()
    RegisterRuntimeCrowdControl("player", spellID, trackedSpell.cd, {
      auto = false,
      includeAllKnown = true,
      isSpellKnown = function(knownSpellID)
        return not IsSpellKnown or IsSpellKnown(knownSpellID)
      end,
    })

    local applied = runtime.engine:ApplySelfCast(UnitGUID("player"), spellID, now, now + trackedSpell.cd)
    if applied then
      applied.playerName = ShortName(UnitName("player"))
      applied.classToken = select(2, UnitClass("player"))
      applied.unitToken = "player"
      applied.name = trackedSpell.name
      applied.essential = trackedSpell.essential == true
      applied.baseCd = trackedSpell.cd
      applied.cd = trackedSpell.cd
      ApplyRuntimeCooldownEntry(applied)
      addon:DebugLog("cc", "self cast", spellID, "cd", trackedSpell.cd)
      if IsInGroup() then
        addon:DebugLog("cc", "send sync", spellID, "cd", trackedSpell.cd, "remaining", trackedSpell.cd)
        Sync.Send("CC", {
          spellID = spellID,
          cd = trackedSpell.cd,
          remaining = trackedSpell.cd,
        })
      end
    end

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, _, sender = ...
    if prefix ~= Sync.GetPrefix() then
      return
    end

    local messageType = Sync.Decode(message)
    if messageType == "HELLO" or messageType == "CC" or messageType == "CC_MANIFEST" then
      addon:DebugLog("cc", "recv sync", sender or "?", message or "")
    end

    HandleSyncCrowdControlMessage(message, sender)
  end
end)

addon.CrowdControlTracker = module
addon:RegisterModule(module)
