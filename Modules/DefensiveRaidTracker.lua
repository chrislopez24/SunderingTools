local addon = _G.SunderingTools
if not addon then return end

local Model = assert(
  _G.SunderingToolsDefensiveRaidTrackerModel,
  "SunderingToolsDefensiveRaidTrackerModel must load before DefensiveRaidTracker.lua"
)
local SpellDB = assert(
  _G.SunderingToolsCombatTrackSpellDB,
  "SunderingToolsCombatTrackSpellDB must load before DefensiveRaidTracker.lua"
)
local Sync = assert(
  _G.SunderingToolsCombatTrackSync,
  "SunderingToolsCombatTrackSync must load before DefensiveRaidTracker.lua"
)
local Engine = assert(
  _G.SunderingToolsCombatTrackEngine,
  "SunderingToolsCombatTrackEngine must load before DefensiveRaidTracker.lua"
)
local FramePositioning = assert(
  _G.SunderingToolsFramePositioning,
  "SunderingToolsFramePositioning must load before DefensiveRaidTracker.lua"
)
local TrackerFrame = assert(
  _G.SunderingToolsTrackerFrame,
  "SunderingToolsTrackerFrame must load before DefensiveRaidTracker.lua"
)

local defaultPosX, defaultPosY = Model.GetDefaultPosition()
local HEADER_LABEL = "Raid Defensives"
local HEADER_TEXTURE = "Interface\\Icons\\Spell_DeathKnight_AntiMagicZone"

local module = {
  key = "DefensiveRaidTracker",
  label = "Raid Defensive Tracker",
  description = "Track raid defensives, sync party data, and adjust layout.",
  order = 30,
  defaults = {
    enabled = true,
    posX = defaultPosX,
    posY = defaultPosY,
    positionMode = "CENTER_OFFSET",
    previewWhenSolo = true,
    maxBars = 3,
    growDirection = "DOWN",
    spacing = 0,
    iconSize = 18,
    barWidth = 190,
    barHeight = 18,
    fontSize = 11,
    syncEnabled = true,
    showHeader = true,
    showInDungeon = true,
    showInRaid = true,
    showInWorld = true,
    showInArena = true,
    hideOutOfCombat = false,
    showReady = true,
    tooltipOnHover = true,
  },
}

local db = addon.db and addon.db.DefensiveRaidTracker
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

local runtime = {
  engine = Engine.New(),
  partyUsers = {},
}
local localTalentRanks = {}
local localTalentConfigID = nil

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

local function NormalizeName(name)
  return ShortName(name)
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

  return nil
end

local function InvalidateLocalTalentCache()
  localTalentConfigID = nil
  wipe(localTalentRanks)
end

local function RefreshLocalTalentCache()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then
    InvalidateLocalTalentCache()
    return
  end

  if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then
    InvalidateLocalTalentCache()
    return
  end

  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then
    InvalidateLocalTalentCache()
    return
  end

  if localTalentConfigID == configID and next(localTalentRanks) ~= nil then
    return
  end

  InvalidateLocalTalentCache()
  localTalentConfigID = configID

  local configInfo = C_Traits.GetConfigInfo(configID)
  if type(configInfo) ~= "table" then
    return
  end

  for _, treeID in ipairs(configInfo.treeIDs or {}) do
    for _, treeNodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local treeNode = (C_Traits.GetNodeInfo and C_Traits.GetNodeInfo(configID, treeNodeID))
        or (_G.C_Traits_GetNodeInfo and _G.C_Traits_GetNodeInfo(configID, treeNodeID))
      local activeEntry = treeNode and treeNode.activeEntry
      local activeRank = treeNode and treeNode.activeRank or 0

      if activeEntry and activeRank > 0 and (not treeNode.subTreeID or treeNode.subTreeActive) then
        local entryInfo = C_Traits.GetEntryInfo(configID, activeEntry.entryID)
        local definitionID = entryInfo and entryInfo.definitionID
        if definitionID then
          local definitionInfo = C_Traits.GetDefinitionInfo(definitionID)
          local spellID = definitionInfo and definitionInfo.spellID
          if type(spellID) == "number" and spellID > 0 then
            localTalentRanks[spellID] = activeRank
          end
        end
      end
    end
  end
end

local function IsLocalSpellKnown(spellID)
  if type(spellID) ~= "number" then
    return false
  end

  if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then
    return true
  end

  if IsPlayerSpell and IsPlayerSpell(spellID) then
    return true
  end

  RefreshLocalTalentCache()
  return localTalentRanks[spellID] ~= nil
end

local function ExtractSpellIDs(entries)
  local spellIDs = {}

  for _, entry in ipairs(entries or {}) do
    spellIDs[#spellIDs + 1] = entry.spellID
  end

  return spellIDs
end

local function GetTrackedRaidDefensiveInfo(spellID)
  local trackedSpell = SpellDB.ResolveLocalDefensiveSpell(spellID, GetLocalPlayerSpecID(), IsLocalSpellKnown)
  if trackedSpell and trackedSpell.kind == "RAID_DEF" then
    return trackedSpell
  end

  return nil
end

local function GetLocalOwnedRaidDefensives(classToken)
  local specID = GetLocalPlayerSpecID()
  return SpellDB.GetLocallyKnownRaidDefensiveSpellsForClass(classToken, specID, IsLocalSpellKnown), specID
end

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

local function ShouldShowPreview()
  if not db or not db.enabled then
    return false
  end

  if editModePreview then
    return true
  end

  return db.previewWhenSolo and not IsInGroup() and not IsInRaid()
end

local function IsCurrentInstanceAllowed()
  if not db or not db.enabled then
    return false
  end

  local _, instanceType = GetInstanceInfo()
  if instanceType == "party" then
    return db.showInDungeon ~= false
  elseif instanceType == "raid" then
    return db.showInRaid ~= false
  elseif instanceType == "arena" then
    return db.showInArena ~= false
  end

  return db.showInWorld ~= false
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
  if not container or not container.editLabel then
    return
  end

  if enabled then
    container.editLabel:Show()
  else
    container.editLabel:Hide()
  end
end

local function UpdateAnchorVisuals(enabled)
  local anchor = module.anchor or container
  TrackerFrame.UpdateEditModeVisuals(anchor, enabled, UpdateEditLabelVisibility)
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

  local headerWidth = math.max(96, math.min(db.barWidth, 144))
  container.header:ClearAllPoints()
  container.header:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 4)
  container.header:SetSize(headerWidth, headerHeight)

  container.header.bg:SetAllPoints()
  container.header.bg:SetColorTexture(0.16, 0.12, 0.20, 0.88)

  container.header.borderTop:SetPoint("TOPLEFT", container.header, "TOPLEFT", 0, 0)
  container.header.borderTop:SetPoint("TOPRIGHT", container.header, "TOPRIGHT", 0, 0)
  container.header.borderTop:SetHeight(1)
  container.header.borderTop:SetColorTexture(0.40, 0.32, 0.44, 0.9)

  container.header.borderBottom:SetPoint("BOTTOMLEFT", container.header, "BOTTOMLEFT", 0, 0)
  container.header.borderBottom:SetPoint("BOTTOMRIGHT", container.header, "BOTTOMRIGHT", 0, 0)
  container.header.borderBottom:SetHeight(1)
  container.header.borderBottom:SetColorTexture(0, 0, 0, 0.9)

  container.header.icon:SetSize(headerHeight - 4, headerHeight - 4)
  container.header.icon:SetPoint("LEFT", container.header, "LEFT", 2, 0)
  container.header.icon:SetTexture(HEADER_TEXTURE)

  container.header.title:ClearAllPoints()
  container.header.title:SetPoint("LEFT", container.header.icon, "RIGHT", 4, 0)
  container.header.title:SetPoint("RIGHT", container.header, "RIGHT", -6, 0)
  container.header.title:SetText(HEADER_LABEL)
  container.header.title:SetTextColor(1.0, 0.84, 0.22)
  container.header.title:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, db.fontSize), "OUTLINE")

  container.header:Show()
end

local function BuildRuntimeUnits()
  local units = {}

  if not IsInGroup() then
    units[#units + 1] = "player"
    return units
  end

  units[#units + 1] = "player"

  if IsInRaid() then
    for i = 1, 40 do
      units[#units + 1] = "raid" .. i
    end
  else
    for i = 1, 4 do
      units[#units + 1] = "party" .. i
    end
  end

  return units
end

local function RegisterExpectedRaidEntries(playerGUID, playerName, classToken, spellIDs, unitToken, specID)
  if not playerGUID or not classToken then
    return
  end

  for _, spellID in ipairs(spellIDs or {}) do
    local trackedSpell
    if unitToken == "player" then
      trackedSpell = SpellDB.ResolveLocalDefensiveSpell(spellID, specID, IsLocalSpellKnown)
    else
      trackedSpell = SpellDB.ResolveDefensiveSpell(spellID, specID)
    end
    if trackedSpell then
      runtime.engine:RegisterExpectedEntry({
        key = tostring(playerGUID) .. ":" .. tostring(spellID),
        playerGUID = playerGUID,
        playerName = playerName,
        classToken = classToken,
        unitToken = unitToken,
        spellID = spellID,
        kind = "RAID_DEF",
        baseCd = trackedSpell.cd,
        cd = trackedSpell.cd,
        charges = trackedSpell.charges or 1,
        startTime = 0,
        readyAt = 0,
      })
    end
  end
end

local PruneRuntimeEntriesForUser
local PruneRuntimeState
local ReconcilePartyUser

local function RefreshRuntimeRoster()
  local previousUsers = {}
  for userKey, user in pairs(runtime.partyUsers) do
    previousUsers[userKey] = user
  end

  wipe(runtime.partyUsers)

  for _, unit in ipairs(BuildRuntimeUnits()) do
    if UnitExists(unit) then
      local playerGUID = UnitGUID(unit)
      local playerName = ShortName(UnitName(unit))
      local _, classToken = UnitClass(unit)
      if playerGUID and playerName and classToken then
        local previousUser = previousUsers[playerName]
        local specID = previousUser and previousUser.specID or nil
        local spellEntries = {}

        if unit == "player" then
          spellEntries, specID = GetLocalOwnedRaidDefensives(classToken)
        elseif previousUser and type(previousUser.spellIDs) == "table" and #previousUser.spellIDs > 0 then
          spellEntries = SpellDB.GetKnownRaidDefensiveSpellsForClass(classToken, specID, previousUser.spellIDs)
        end

        local spellIDs = ExtractSpellIDs(spellEntries)

        local user = {
          key = playerName,
          playerGUID = playerGUID,
          playerName = playerName,
          classToken = classToken,
          specID = specID,
          unitToken = unit,
          spellIDs = spellIDs,
        }
        runtime.partyUsers[playerName] = user

        ReconcilePartyUser(user, previousUser)

        RegisterExpectedRaidEntries(playerGUID, playerName, classToken, spellIDs, unit, specID)
        PruneRuntimeEntriesForUser(playerGUID, spellIDs)
      end
    end
  end

  PruneRuntimeState()
end

local function SendCurrentSelfState()
  if not db or db.syncEnabled == false then
    return
  end

  if not IsInGroup() then
    return
  end

  local playerGUID = UnitGUID("player")
  if not playerGUID then
    return
  end

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("RAID_DEF")) do
    if entry.playerGUID == playerGUID then
      Sync.Send("DEF_STATE", {
        spellID = entry.spellID,
        kind = "RAID_DEF",
        cd = entry.baseCd or entry.cd or 0,
        charges = entry.charges or 1,
        readyAt = entry.readyAt or 0,
      })
    end
  end
end

local function AnnouncePresence()
  if not db or db.syncEnabled == false or not IsInGroup() then
    return
  end

  local _, classToken = UnitClass("player")
  local ownedSpells, specID = GetLocalOwnedRaidDefensives(classToken)
  Sync.Send("HELLO", {
    classToken = classToken,
    specID = specID,
  })

  Sync.Send("DEF_MANIFEST", {
    kind = "RAID_DEF",
    spells = ExtractSpellIDs(ownedSpells),
  })
  SendCurrentSelfState()
end

local function BuildRemoteGuid(userKey)
  return "sync:" .. tostring(userKey or "unknown")
end

local function BuildRuntimeKey(playerGUID, spellID)
  if not playerGUID or not spellID then
    return nil
  end

  return tostring(playerGUID) .. ":" .. tostring(spellID)
end

local function BuildSpellSet(spellIDs)
  local spellSet = {}
  for _, spellID in ipairs(spellIDs or {}) do
    spellSet[spellID] = true
  end
  return spellSet
end

PruneRuntimeEntriesForUser = function(playerGUID, spellIDs)
  if not playerGUID then
    return
  end

  local allowedSpells = BuildSpellSet(spellIDs)
  for _, entry in ipairs(runtime.engine:GetEntriesByKind("RAID_DEF")) do
    if entry.playerGUID == playerGUID and not allowedSpells[entry.spellID] then
      runtime.engine:RemoveEntry(entry.key)
    end
  end
end

PruneRuntimeState = function()
  local usersByGuid = {}
  for _, user in pairs(runtime.partyUsers) do
    if user.playerGUID then
      usersByGuid[user.playerGUID] = user
    end
  end

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("RAID_DEF")) do
    local user = usersByGuid[entry.playerGUID]
    if not user then
      runtime.engine:RemoveEntry(entry.key)
    else
      local spellSet = BuildSpellSet(user.spellIDs)
      if not spellSet[entry.spellID] then
        runtime.engine:RemoveEntry(entry.key)
      end
    end
  end
end

ReconcilePartyUser = function(user, previousUser)
  if not previousUser then
    return
  end

  if not user.classToken then
    user.classToken = previousUser.classToken
  end

  if not user.specID then
    user.specID = previousUser.specID
  end

  if previousUser.playerGUID == user.playerGUID then
    return
  end

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("RAID_DEF")) do
    if entry.playerGUID == previousUser.playerGUID then
      local migrated = {}
      for key, value in pairs(entry) do
        migrated[key] = value
      end

      migrated.key = BuildRuntimeKey(user.playerGUID, entry.spellID)
      migrated.playerGUID = user.playerGUID
      migrated.playerName = user.playerName
      migrated.classToken = user.classToken or entry.classToken
      migrated.unitToken = user.unitToken

      runtime.engine:UpsertEntry(migrated)
      runtime.engine:RemoveEntry(entry.key)
    end
  end
end

local function GetOrCreatePartyUser(userKey, fallbackSpellID)
  local user = runtime.partyUsers[userKey]
  if user then
    return user
  end

  local trackedSpell = fallbackSpellID and GetTrackedRaidDefensiveInfo(fallbackSpellID) or nil
  user = {
    key = userKey,
    playerGUID = BuildRemoteGuid(userKey),
    playerName = userKey,
    classToken = trackedSpell and trackedSpell.classToken or nil,
    specID = nil,
    unitToken = nil,
    spellIDs = {},
  }
  runtime.partyUsers[userKey] = user
  return user
end

local function RegisterUserManifest(user, spellIDs)
  user.spellIDs = {}

  for _, spellID in ipairs(spellIDs or {}) do
    user.spellIDs[#user.spellIDs + 1] = spellID
  end

  if not user.classToken and user.spellIDs[1] then
    local trackedSpell = SpellDB.ResolveDefensiveSpell(user.spellIDs[1], user.specID)
    if trackedSpell then
      user.classToken = trackedSpell.classToken
    end
  end

  PruneRuntimeEntriesForUser(user.playerGUID, user.spellIDs)

  RegisterExpectedRaidEntries(
    user.playerGUID,
    user.playerName,
    user.classToken,
    user.spellIDs,
    user.unitToken,
    user.specID
  )
end

local function HandleSyncHelloMessage(payload, sender)
  local userKey = NormalizeName(sender)
  if not userKey then
    return
  end

  local user = GetOrCreatePartyUser(userKey)
  if payload and payload.classToken and payload.classToken ~= "" then
    user.classToken = payload.classToken
  end

  if payload and type(payload.specID) == "number" and payload.specID > 0 then
    user.specID = payload.specID
  end

  UpdatePartyData()
end

local function HandleSyncManifestMessage(payload, sender)
  local userKey = NormalizeName(sender)
  if not userKey then
    return
  end

  if payload and payload.kind ~= nil and payload.kind ~= "RAID_DEF" then
    return
  end

  local user = GetOrCreatePartyUser(userKey)
  RegisterUserManifest(user, payload and payload.spells or {})
  PruneRuntimeState()
  UpdatePartyData()
end

local function HandleSyncDefensiveStateMessage(payload, sender)
  local userKey = NormalizeName(sender)
  if not userKey or type(payload) ~= "table" then
    return
  end

  if payload.kind ~= nil and payload.kind ~= "RAID_DEF" then
    return
  end

  local user = GetOrCreatePartyUser(userKey, payload.spellID)
  local trackedSpell = SpellDB.ResolveDefensiveSpell(payload.spellID, user.specID)
  if not trackedSpell or trackedSpell.kind ~= "RAID_DEF" then
    return
  end

  if not user.classToken then
    user.classToken = trackedSpell.classToken
  end
  if not next(user.spellIDs) then
    RegisterUserManifest(user, { payload.spellID })
  end

  local cooldown = payload.cd
  if type(cooldown) ~= "number" or cooldown <= 0 then
    cooldown = trackedSpell.cd
  end

  local readyAt = payload.readyAt
  if type(readyAt) ~= "number" or readyAt <= 0 then
    readyAt = 0
  end

  local startTime = 0
  if readyAt > 0 and cooldown > 0 then
    startTime = readyAt - cooldown
  end

  local applied = runtime.engine:ApplySyncState(user.playerGUID, payload.spellID, {
    kind = payload.kind or "RAID_DEF",
    cd = cooldown,
    charges = payload.charges or 1,
    readyAt = readyAt,
    startTime = startTime,
  })

  if applied then
    applied.playerName = user.playerName
    applied.classToken = user.classToken
    applied.unitToken = user.unitToken
    applied.kind = "RAID_DEF"
    applied.baseCd = applied.baseCd or cooldown
    applied.cd = cooldown
  end

  UpdatePartyData()
end

local function HandleSyncMessage(message, sender)
  if not db or not db.enabled or db.syncEnabled == false then
    return
  end

  local messageType, payload = Sync.Decode(message)
  if messageType == "HELLO"
    or (messageType == "DEF_MANIFEST" and (payload == nil or payload.kind == nil or payload.kind == "RAID_DEF"))
    or (messageType == "DEF_STATE" and (payload == nil or payload.kind == nil or payload.kind == "RAID_DEF"))
  then
    addon:DebugLog("rdef", "recv sync", sender or "?", message or "")
  end

  if messageType == "HELLO" then
    HandleSyncHelloMessage(payload, sender)
    return
  end

  if messageType == "DEF_MANIFEST" then
    HandleSyncManifestMessage(payload, sender)
    return
  end

  if messageType == "DEF_STATE" then
    HandleSyncDefensiveStateMessage(payload, sender)
  end
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
  moduleDB = moduleDB or db or (addon.db and addon.db.modules and addon.db.modules.DefensiveRaidTracker)
  if not moduleDB then return end

  FramePositioning.ResetToDefault(self.anchor or container, moduleDB, defaultPosX, defaultPosY)
end

function module:buildSettings(panel, helpers, addonRef, moduleDB)
  db = moduleDB

  local function GetEditButtonLabel()
    if addonRef.db.global.editMode and (
      addonRef.db.global.activeEditModule == "DefensiveRaidTracker"
      or addonRef.db.global.activeEditModule == "ALL"
    ) then
      return "Lock Tracker"
    end

    return "Open Edit Mode"
  end

  local stateLabel = helpers:CreateDividerLabel(panel, "State", nil, 0)
  local stateBody = helpers:CreateSectionHint(panel, "Enable the tracker and place it where you want it.", 520)
  stateBody:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)

  local enabledBox = helpers:CreateInlineCheckbox(panel, "Enable Raid Defensive Tracker", moduleDB.enabled, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "enabled", value)
  end)
  enabledBox:SetPoint("TOPLEFT", stateBody, "BOTTOMLEFT", 0, -12)

  local editButton = helpers:CreateActionButton(panel, GetEditButtonLabel(), function(self)
    local isActive = addonRef.db.global.editMode and (
      addonRef.db.global.activeEditModule == "DefensiveRaidTracker"
      or addonRef.db.global.activeEditModule == "ALL"
    )
    addonRef:SetEditMode(not isActive, isActive and nil or "DefensiveRaidTracker")
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
  local behaviorBody = helpers:CreateSectionHint(behaviorColumn, "Preview, visibility, and sync options.", 250)
  behaviorBody:SetPoint("TOPLEFT", behaviorLabel, "BOTTOMLEFT", 0, -8)

  local previewWhenSoloBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show Preview When Solo", moduleDB.previewWhenSolo, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "previewWhenSolo", value)
  end)
  previewWhenSoloBox:SetPoint("TOPLEFT", behaviorBody, "BOTTOMLEFT", 0, -12)

  local syncEnabledBox = helpers:CreateInlineCheckbox(behaviorColumn, "Enable Party Sync", moduleDB.syncEnabled, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "syncEnabled", value)
  end)
  syncEnabledBox:SetPoint("TOPLEFT", previewWhenSoloBox, "BOTTOMLEFT", 0, -8)

  local showReadyBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show Ready Bars", moduleDB.showReady ~= false, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "showReady", value)
  end)
  showReadyBox:SetPoint("TOPLEFT", syncEnabledBox, "BOTTOMLEFT", 0, -8)

  local hideOutOfCombatBox = helpers:CreateInlineCheckbox(behaviorColumn, "Hide Out of Combat", moduleDB.hideOutOfCombat, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "hideOutOfCombat", value)
  end)
  hideOutOfCombatBox:SetPoint("TOPLEFT", showReadyBox, "BOTTOMLEFT", 0, -8)

  local tooltipBox = helpers:CreateInlineCheckbox(behaviorColumn, "Tooltip on Hover", moduleDB.tooltipOnHover ~= false, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "tooltipOnHover", value)
  end)
  tooltipBox:SetPoint("TOPLEFT", hideOutOfCombatBox, "BOTTOMLEFT", 0, -8)

  local showInDungeonBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show in Dungeons", moduleDB.showInDungeon ~= false, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "showInDungeon", value)
  end)
  showInDungeonBox:SetPoint("TOPLEFT", tooltipBox, "BOTTOMLEFT", 0, -8)

  local showInRaidBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show in Raids", moduleDB.showInRaid ~= false, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "showInRaid", value)
  end)
  showInRaidBox:SetPoint("TOPLEFT", showInDungeonBox, "BOTTOMLEFT", 0, -8)

  local showInWorldBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show in World", moduleDB.showInWorld ~= false, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "showInWorld", value)
  end)
  showInWorldBox:SetPoint("TOPLEFT", showInRaidBox, "BOTTOMLEFT", 0, -8)

  local showInArenaBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show in Arena", moduleDB.showInArena ~= false, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "showInArena", value)
  end)
  showInArenaBox:SetPoint("TOPLEFT", showInWorldBox, "BOTTOMLEFT", 0, -8)

  local behaviorHint = helpers:CreateSectionHint(
    behaviorColumn,
    "Shares raid-defensive state over addon sync and shows the shared cooldown bars.",
    250
  )
  behaviorHint:SetPoint("TOPLEFT", showInArenaBox, "BOTTOMLEFT", 0, -12)

  local layoutLabel = helpers:CreateDividerLabel(layoutColumn, "Layout", nil, 0)
  local layoutBody = helpers:CreateSectionHint(layoutColumn, "Adjust size, spacing, and growth.", 250)
  layoutBody:SetPoint("TOPLEFT", layoutLabel, "BOTTOMLEFT", 0, -8)

  local showHeaderBox = helpers:CreateInlineCheckbox(layoutColumn, "Show Header", moduleDB.showHeader ~= false, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "showHeader", value)
  end)
  showHeaderBox:SetPoint("TOPLEFT", layoutBody, "BOTTOMLEFT", 0, -12)

  local growDirectionDropdown = helpers:CreateLabeledDropdown(
    layoutColumn,
    "Grow Direction",
    { "DOWN", "UP" },
    moduleDB.growDirection,
    210,
    function(value)
      addonRef:SetModuleValue("DefensiveRaidTracker", "growDirection", value)
    end
  )
  growDirectionDropdown:SetPoint("TOPLEFT", showHeaderBox, "BOTTOMLEFT", 0, -10)

  local maxBarsSlider = helpers:CreateLabeledSlider(layoutColumn, "Maximum Bars", 1, 8, 1, moduleDB.maxBars, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "maxBars", value)
  end, 250)
  maxBarsSlider:SetPoint("TOPLEFT", growDirectionDropdown, "BOTTOMLEFT", 0, -10)

  local spacingSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Spacing", 0, 12, 1, moduleDB.spacing, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "spacing", value)
  end, 250)
  spacingSlider:SetPoint("TOPLEFT", maxBarsSlider, "BOTTOMLEFT", 0, -10)

  local barWidthSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Width", 100, 320, 5, moduleDB.barWidth, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "barWidth", value)
  end, 250)
  barWidthSlider:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -10)

  local barHeightSlider = helpers:CreateLabeledSlider(layoutColumn, "Bar Height", 16, 40, 1, moduleDB.barHeight, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "barHeight", value)
  end, 250)
  barHeightSlider:SetPoint("TOPLEFT", barWidthSlider, "BOTTOMLEFT", 0, -10)

  local iconSizeSlider = helpers:CreateLabeledSlider(layoutColumn, "Icon Size", 14, 32, 1, moduleDB.iconSize, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "iconSize", value)
  end, 250)
  iconSizeSlider:SetPoint("TOPLEFT", barHeightSlider, "BOTTOMLEFT", 0, -10)

  local fontSizeSlider = helpers:CreateLabeledSlider(layoutColumn, "Font Size", 8, 18, 1, moduleDB.fontSize, function(value)
    addonRef:SetModuleValue("DefensiveRaidTracker", "fontSize", value)
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
    or key == "showInRaid"
    or key == "showInWorld"
    or key == "showInArena"
    or key == "hideOutOfCombat"
    or key == "showReady"
    or key == "tooltipOnHover"
    or key == "syncEnabled" then
    CreateContainer()
    UpdatePartyData()
  end
end

local function CreateBar()
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

  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self)
    if not db or db.tooltipOnHover == false then return end
    local data = self._trackerData
    if not data then return end

    local trackedSpell = GetTrackedRaidDefensiveInfo(data.spellID)
    local now = GetTime()
    local ready = data.startTime == 0 or (now - data.startTime) >= (data.cd or 0)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(data.name or "Unknown", 1, 1, 1)
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
      bars[index] = CreateBar()
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
  local classColor = Model.GetClassColor(data.class)
  local textOffset = GetIconOffset() + 5
  local readyTextColor = { 1.0, 0.84, 0.22 }
  local activeTextColor = { 1.0, 0.94, 0.74 }

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

    local timerText = data.previewText
    if not timerText then
      timerText = Model.FormatTimerText(remaining)
    end
    bar.cooldownText:SetText(timerText or "")
    bar.cooldownText:SetTextColor(activeTextColor[1], activeTextColor[2], activeTextColor[3])
    bar.cooldownText:Show()
  end
end

local function SortBars()
  local sortList = {}
  for _, data in pairs(activeBars) do
    sortList[#sortList + 1] = data
  end

  Model.SortBars(sortList, GetTime())

  wipe(usedBarsList)
  for _, data in ipairs(sortList) do
    usedBarsList[#usedBarsList + 1] = data
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
    "SunderingToolsDefensiveRaidTracker",
    "Raid Defensive Tracker",
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

local function UpdateEngineTiming(key, startTime, readyAt)
  local entry = runtime.engine:GetEntry(key)
  if entry then
    entry.startTime = startTime or 0
    entry.readyAt = readyAt or 0
  end
end

local HandleCooldownReady

local function RefreshActiveCooldownBars()
  local anyCooling = false
  local needsLayout = false

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
        end
      end
    end
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
    data.readyAt = 0
    UpdateEngineTiming(data.runtimeKey, 0, 0)
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
  data.readyAt = 0
  UpdateEngineTiming(data.runtimeKey, 0, 0)

  if db.showReady == false then
    bar._lastDisplayed = nil
    return false
  end

  bar.cooldownText:SetText("")
  bar._lastDisplayed = nil
  UpdateBarVisuals(bar, data)
  return true
end

local function BuildPreviewBars()
  return Model.BuildPreviewBars()
end

local function BuildRuntimeBarEntries()
  local entries = {}

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("RAID_DEF")) do
    local playerName = entry.playerName or "Unknown"
    local startTime = entry.startTime or 0
    local readyAt = entry.readyAt or 0
    local cooldown = entry.baseCd or entry.cd or 0
    local now = GetTime()

    if readyAt > 0 and startTime == 0 and cooldown > 0 then
      startTime = readyAt - cooldown
    end

    local ready = startTime <= 0 or cooldown <= 0 or (now - startTime) >= cooldown
    if not ready or db.showReady ~= false then
      entries[#entries + 1] = {
        key = entry.key,
        runtimeKey = entry.key,
        name = playerName,
        spellName = GetTrackedRaidDefensiveInfo(entry.spellID) and GetTrackedRaidDefensiveInfo(entry.spellID).name or nil,
        class = entry.classToken,
        spellID = entry.spellID,
        cd = cooldown,
        startTime = ready and 0 or startTime,
        readyAt = ready and 0 or readyAt,
        charges = entry.charges or 1,
        source = entry.source,
        kind = "RAID_DEF",
      }
    end
  end

  return entries
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
      runtimeKey = entry.runtimeKey or entry.key,
      bar = bar,
      name = entry.name,
      spellName = entry.spellName,
      class = entry.class,
      spellID = entry.spellID,
      cd = entry.cd,
      startTime = entry.startTime or 0,
      readyAt = entry.readyAt or 0,
      previewText = entry.previewText,
      previewValue = entry.previewValue,
      source = entry.source,
      kind = "RAID_DEF",
      charges = entry.charges or 1,
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

  PopulateBars(BuildRuntimeBarEntries())
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    db = addon.db and addon.db.DefensiveRaidTracker
    Sync.RegisterPrefix()

    if db and db.enabled then
      RefreshRuntimeRoster()
      CreateContainer()
      UpdatePartyData()
    end

  elseif event == "PLAYER_ENTERING_WORLD" then
    runtime.engine:Reset()
    RefreshRuntimeRoster()

    if db and db.enabled then
      CreateContainer()
      UpdatePartyData()
    end

    AfterDelay(1.0, function()
      AnnouncePresence()
    end)

  elseif event == "CHALLENGE_MODE_START" then
    runtime.engine:Reset()
    RefreshRuntimeRoster()

    if db and db.enabled then
      UpdatePartyData()
    end

    AfterDelay(1.0, function()
      AnnouncePresence()
    end)

  elseif event == "GROUP_ROSTER_UPDATE" then
    RefreshRuntimeRoster()

    if db and db.enabled then
      UpdatePartyData()
    end

    AfterDelay(1.0, function()
      AnnouncePresence()
    end)

  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    if db and db.enabled then
      UpdatePartyData()
    end

  elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
    InvalidateLocalTalentCache()
    RefreshRuntimeRoster()
    if db and db.enabled then
      UpdatePartyData()
    end

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if not db or not db.enabled then return end

    local unit, _, spellID = ...
    if unit ~= "player" then return end
    if type(spellID) ~= "number" then return end

    local trackedSpell = GetTrackedRaidDefensiveInfo(spellID)
    if not trackedSpell then
      return
    end

    local now = GetTime()
    local playerGUID = UnitGUID("player")
    local canonicalSpellID = trackedSpell.spellID or spellID
    addon:DebugLog("rdef", "self cast", "event", spellID, "spell", canonicalSpellID, "cd", trackedSpell.cd)
    local applied = runtime.engine:ApplySelfCast(playerGUID, canonicalSpellID, now, now + trackedSpell.cd)
    if applied then
      applied.playerName = ShortName(UnitName("player"))
      applied.classToken = trackedSpell.classToken or select(2, UnitClass("player"))
      applied.unitToken = "player"
      applied.kind = "RAID_DEF"
      applied.baseCd = trackedSpell.cd
      applied.cd = trackedSpell.cd
      applied.charges = trackedSpell.charges or 1

      if db.syncEnabled ~= false then
        addon:DebugLog("rdef", "send sync", canonicalSpellID, "cd", trackedSpell.cd, "readyAt", now + trackedSpell.cd)
        Sync.Send("DEF_STATE", {
          spellID = canonicalSpellID,
          kind = "RAID_DEF",
          cd = trackedSpell.cd,
          charges = trackedSpell.charges or 1,
          readyAt = now + trackedSpell.cd,
        })
      end
      UpdatePartyData()
    end

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, _, sender = ...
    if prefix ~= Sync.GetPrefix() then
      return
    end

    HandleSyncMessage(message, sender)
  end
end)

addon.DefensiveRaidTracker = module
addon:RegisterModule(module)
