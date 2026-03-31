local addon = _G.SunderingTools
if not addon then return end

local Model = assert(
  _G.SunderingToolsPartyDefensiveTrackerModel,
  "SunderingToolsPartyDefensiveTrackerModel must load before PartyDefensiveTracker.lua"
)
local SpellDB = assert(
  _G.SunderingToolsCombatTrackSpellDB,
  "SunderingToolsCombatTrackSpellDB must load before PartyDefensiveTracker.lua"
)
local Sync = assert(
  _G.SunderingToolsCombatTrackSync,
  "SunderingToolsCombatTrackSync must load before PartyDefensiveTracker.lua"
)
local Engine = assert(
  _G.SunderingToolsCombatTrackEngine,
  "SunderingToolsCombatTrackEngine must load before PartyDefensiveTracker.lua"
)
local Fallback = assert(
  _G.SunderingToolsPartyDefensiveAuraFallback,
  "SunderingToolsPartyDefensiveAuraFallback must load before PartyDefensiveTracker.lua"
)

local module = {
  key = "PartyDefensiveTracker",
  label = "Party Defensive Tracker",
  description = "Attach party defensive icons to Blizzard raid-style party frames.",
  order = 25,
  defaults = {
    enabled = true,
    previewWhenSolo = true,
    maxIcons = 4,
    iconSize = 20,
    iconSpacing = 1,
    attachPoint = "RIGHT",
    relativePoint = "LEFT",
    offsetX = -2,
    offsetY = 0,
    showTooltip = true,
  },
}

local db = addon.db and addon.db.PartyDefensiveTracker
local editModePreview = false
local hookedPartyFrame = nil
local hookRetryScheduled = false
local attachmentTicker = nil
local ATTACHMENT_POINT_OPTIONS = {
  "TOPLEFT",
  "TOP",
  "TOPRIGHT",
  "LEFT",
  "CENTER",
  "RIGHT",
  "BOTTOMLEFT",
  "BOTTOM",
  "BOTTOMRIGHT",
}

local runtime = {
  engine = Engine.New(),
  partyUsers = {},
  fallback = Fallback.New({
    getTime = GetTime,
    resolveSpell = function(spellID)
      return SpellDB.ResolveDefensiveSpell(spellID)
    end,
  }),
}
local localTalentRanks = {}
local localTalentConfigID = nil

local function NormalizeAttachmentSettings(moduleDB)
  if type(moduleDB) ~= "table" then
    return
  end

  moduleDB.syncEnabled = nil
  moduleDB.strictSyncMode = nil

  local missingRelativePoint = moduleDB.relativePoint == nil or moduleDB.relativePoint == ""
  local looksLikeLegacyDefault =
    (moduleDB.attachPoint == nil or moduleDB.attachPoint == "TOPRIGHT")
    and (moduleDB.offsetX == nil or moduleDB.offsetX == -2 or moduleDB.offsetX == -4)
    and (moduleDB.offsetY == nil or moduleDB.offsetY == -2)

  if missingRelativePoint and looksLikeLegacyDefault then
    moduleDB.attachPoint = "RIGHT"
    moduleDB.relativePoint = "LEFT"
    moduleDB.offsetX = -2
    moduleDB.offsetY = 0
    moduleDB.iconSize = 20
    moduleDB.iconSpacing = 1
    return
  end

  moduleDB.attachPoint = moduleDB.attachPoint or "RIGHT"
  moduleDB.relativePoint = moduleDB.relativePoint or "LEFT"
    if moduleDB.offsetX == nil then
      moduleDB.offsetX = -2
  end
  if moduleDB.offsetY == nil then
    moduleDB.offsetY = 0
  end
  if moduleDB.iconSize == nil then
    moduleDB.iconSize = 20
  end
  if moduleDB.iconSpacing == nil then
    moduleDB.iconSpacing = 1
  end
end

local function EnsureModuleDB()
  if type(db) == "table" then
    return db
  end

  local addonDB = addon and addon.db
  local moduleDB = addonDB and ((addonDB.modules and addonDB.modules.PartyDefensiveTracker) or addonDB.PartyDefensiveTracker) or nil
  if type(moduleDB) ~= "table" then
    return nil
  end

  NormalizeAttachmentSettings(moduleDB)
  db = moduleDB
  return db
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

local function GetTrackedDefensiveInfo(spellID)
  local trackedSpell = SpellDB.ResolveLocalDefensiveSpell(spellID, GetLocalPlayerSpecID(), IsLocalSpellKnown)
  if trackedSpell and trackedSpell.kind == "DEF" then
    return trackedSpell
  end

  return nil
end

local function GetLocalOwnedDefensiveSpells(classToken)
  local specID = GetLocalPlayerSpecID()
  return SpellDB.GetLocallyKnownDefensiveSpellsForClass(classToken, specID, IsLocalSpellKnown), specID
end

local function IsAttachmentActive()
  local moduleDB = EnsureModuleDB()
  return editModePreview or (moduleDB and moduleDB.enabled)
end

local function BuildCompactPartyFrameUnits()
  local units = {}
  local seen = {}

  if not CompactPartyFrame or type(CompactPartyFrame.memberUnitFrames) ~= "table" then
    return units
  end

  for _, memberFrame in ipairs(CompactPartyFrame.memberUnitFrames) do
    local unitToken = memberFrame.unit or memberFrame.displayedUnit
    if unitToken and not seen[unitToken] and UnitExists(unitToken) then
      seen[unitToken] = true
      units[#units + 1] = unitToken
    end
  end

  return units
end

local function BuildRuntimeUnits()
  local units = BuildCompactPartyFrameUnits()

  if #units > 0 then
    return units
  end

  if UnitExists("player") then
    units[#units + 1] = "player"
  end

  if IsInGroup and IsInGroup() then
    for index = 1, 4 do
      local unit = "party" .. index
      if UnitExists(unit) then
        units[#units + 1] = unit
      end
    end
  end

  return units
end

local function BuildRuntimeKey(playerGUID, spellID)
  if not playerGUID or not spellID then
    return nil
  end

  return tostring(playerGUID) .. ":" .. tostring(spellID)
end

local function BuildRemoteGuid(userKey)
  return "sync:" .. tostring(userKey or "unknown")
end

local function BuildSpellSet(spellIDs)
  local spellSet = {}
  for _, spellID in ipairs(spellIDs or {}) do
    spellSet[spellID] = true
  end
  return spellSet
end

local function BuildDefensiveAuraSnapshot(unitToken)
  local snapshot = {}
  local seen = {}
  local filters = {
    "HELPFUL|BIG_DEFENSIVE",
    "HELPFUL|EXTERNAL_DEFENSIVE",
  }

  for _, filter in ipairs(filters) do
    local auras = C_UnitAuras and C_UnitAuras.GetUnitAuras and C_UnitAuras.GetUnitAuras(unitToken, filter)
    for _, aura in ipairs(auras or {}) do
      if aura and aura.auraInstanceID and not seen[aura.auraInstanceID] then
        seen[aura.auraInstanceID] = true
        snapshot[#snapshot + 1] = aura
      end
    end
  end

  return snapshot
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

local function ShouldShowPreview()
  if not db or not db.enabled then
    return false
  end

  if editModePreview then
    return true
  end

  return db.previewWhenSolo and not IsInGroup()
end

local function ResetAttachmentSettings(moduleDB)
  if type(moduleDB) ~= "table" then
    return
  end

  moduleDB.attachPoint = module.defaults.attachPoint
  moduleDB.relativePoint = module.defaults.relativePoint
  moduleDB.offsetX = module.defaults.offsetX
  moduleDB.offsetY = module.defaults.offsetY
  moduleDB.maxIcons = module.defaults.maxIcons
  moduleDB.iconSize = module.defaults.iconSize
  moduleDB.iconSpacing = module.defaults.iconSpacing
  moduleDB.showTooltip = module.defaults.showTooltip
end

local function GetEntrySpellInfo(entry)
  if type(entry) ~= "table" or type(entry.spellID) ~= "number" then
    return nil
  end

  return SpellDB.ResolveDefensiveSpell(entry.spellID)
    or SpellDB.ResolveLocalDefensiveSpell(entry.spellID, GetLocalPlayerSpecID(), IsLocalSpellKnown)
    or SpellDB.GetTrackedSpell(entry.spellID)
end

local function CreateIcon(parent)
  local icon = CreateFrame("Frame", nil, parent)
  icon:EnableMouse(true)
  icon.icon = icon:CreateTexture(nil, "ARTWORK")
  icon.icon:SetAllPoints()
  icon.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon.cooldownText = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  icon.cooldownText:SetPoint("CENTER", icon, "CENTER", 0, 0)
  icon.cooldownText:SetJustifyH("CENTER")
  icon.cooldownText:SetJustifyV("MIDDLE")
  icon.cooldownText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  icon:SetAlpha(1)
  icon:SetScript("OnEnter", function(self)
    if not db or db.showTooltip == false then
      return
    end

    local entry = self._entry
    if not entry then
      return
    end

    local spellInfo = GetEntrySpellInfo(entry)
    local now = GetTime()
    local cooldown = entry.cd or 0
    local startTime = entry.startTime or 0
    local remaining = math.max(0, cooldown - (now - startTime))

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(entry.playerName or "Unknown", 1, 1, 1)
    if spellInfo and spellInfo.name then
      GameTooltip:AddLine(spellInfo.name, 1, 1, 1)
    end
    if startTime > 0 and remaining > 0 then
      GameTooltip:AddLine(string.format("Cooldown: %s", Model.FormatTimerText(remaining)), 0.95, 0.6, 0.15)
    else
      GameTooltip:AddLine("Status: Ready", 0.2, 0.95, 0.3)
    end
    GameTooltip:Show()
  end)
  icon:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  icon:Hide()
  return icon
end

local function RefreshAttachmentAnchor(attachment, memberFrame)
  if not attachment or not memberFrame or not db then
    return
  end

  attachment:ClearAllPoints()
  attachment:SetPoint(
    db.attachPoint or "RIGHT",
    memberFrame,
    db.relativePoint or "LEFT",
    db.offsetX or 0,
    db.offsetY or 0
  )
end

local function EnsureAttachment(memberFrame)
  if not memberFrame then
    return nil
  end

  local attachment = memberFrame.SunderingToolsPartyDefensiveAttachment
  if attachment then
    attachment._ownerFrame = memberFrame
    attachment._entries = attachment._entries or {}
    attachment._icons = attachment._icons or {}
    RefreshAttachmentAnchor(attachment, memberFrame)
    return attachment
  end

  attachment = CreateFrame("Frame", nil, memberFrame)
  attachment._ownerFrame = memberFrame
  attachment._entries = {}
  attachment._icons = {}
  RefreshAttachmentAnchor(attachment, memberFrame)
  memberFrame.SunderingToolsPartyDefensiveAttachment = attachment
  return attachment
end

local function LayoutAttachment(attachment)
  if not attachment or not db then
    return
  end

  local iconSize = tonumber(db.iconSize) or 16
  local spacing = tonumber(db.iconSpacing) or 2
  local count = math.max(1, tonumber(db.maxIcons) or 4)

  attachment:SetSize((count * iconSize) + (math.max(0, count - 1) * spacing), iconSize)

  for index = 1, count do
    local icon = attachment._icons[index]
    if not icon then
      icon = CreateIcon(attachment)
      attachment._icons[index] = icon
    end

    icon:ClearAllPoints()
    if index == 1 then
      icon:SetPoint("TOPLEFT", attachment, "TOPLEFT", 0, 0)
    else
      icon:SetPoint("LEFT", attachment._icons[index - 1], "RIGHT", spacing, 0)
    end
    icon:SetSize(iconSize, iconSize)
  end
end

local function CollectEntriesForUnit(unitToken)
  local entries = {}
  local now = GetTime()

  if not unitToken then
    return entries
  end

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("DEF")) do
    if entry.unitToken == unitToken then
      local cooldown = entry.baseCd or entry.cd or 0
      local startTime = entry.startTime or 0
      local readyAt = entry.readyAt or 0

      if readyAt > 0 and startTime <= 0 and cooldown > 0 then
        startTime = readyAt - cooldown
      end

      entries[#entries + 1] = {
        key = entry.key,
        spellID = entry.spellID,
        kind = "DEF",
        startTime = startTime,
        readyAt = readyAt,
        cd = cooldown,
        playerGUID = entry.playerGUID,
        playerName = entry.playerName,
        classToken = entry.classToken,
      }
    end
  end

  return Model.SortIcons(entries, now)
end

local function RenderAttachment(memberFrame, entries)
  local attachment = EnsureAttachment(memberFrame)
  if not attachment then
    return
  end

  LayoutAttachment(attachment)
  attachment._entries = {}

  local limit = math.min(#entries, tonumber(db.maxIcons) or 4)
  for index = 1, limit do
    local entry = entries[index]
    local icon = attachment._icons[index]
    local texture = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spellID)) or nil
    local now = GetTime()
    local remaining = math.max(0, (entry.cd or 0) - (now - (entry.startTime or 0)))
    local text = ""

    if (entry.startTime or 0) > 0 and remaining > 0 then
      text = Model.FormatTimerText(remaining)
    end

    attachment._entries[index] = entry
    icon._entry = entry
    icon.icon:SetTexture(texture)
    icon.cooldownText:SetText(text)
    icon:SetAlpha(text ~= "" and 0.85 or 1)
    icon:Show()
  end

  for index = limit + 1, #attachment._icons do
    attachment._icons[index]._entry = nil
    attachment._icons[index]:Hide()
  end

  if limit > 0 then
    attachment:Show()
  else
    attachment:Hide()
  end
end

local function HideUnusedAttachments(seenFrames)
  local partyFrame = CompactPartyFrame
  if not partyFrame or type(partyFrame.memberUnitFrames) ~= "table" then
    return
  end

  for _, memberFrame in ipairs(partyFrame.memberUnitFrames) do
    if memberFrame.SunderingToolsPartyDefensiveAttachment and not seenFrames[memberFrame] then
      memberFrame.SunderingToolsPartyDefensiveAttachment._entries = {}
      memberFrame.SunderingToolsPartyDefensiveAttachment:Hide()
    end
  end
end

local UpdateAttachments

local function HasActiveAttachmentCooldowns()
  local now = GetTime()

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("DEF")) do
    local cooldown = entry.baseCd or entry.cd or 0
    local startTime = entry.startTime or 0
    local readyAt = entry.readyAt or 0

    if readyAt > 0 and startTime <= 0 and cooldown > 0 then
      startTime = readyAt - cooldown
    end

    if startTime > 0 and cooldown > 0 and (now - startTime) < cooldown then
      return true
    end
  end

  return false
end

local function RefreshAttachmentTicker()
  local shouldTick = false

  if db and db.enabled then
    shouldTick = ShouldShowPreview() or HasActiveAttachmentCooldowns()
  end

  if not shouldTick then
    if attachmentTicker then
      attachmentTicker:Cancel()
      attachmentTicker = nil
    end
    return
  end

  if attachmentTicker or not (C_Timer and C_Timer.NewTicker) then
    return
  end

  attachmentTicker = C_Timer.NewTicker(1, function()
    if not db or not db.enabled then
      if attachmentTicker then
        attachmentTicker:Cancel()
        attachmentTicker = nil
      end
      return
    end

    UpdateAttachments()
  end)
end

local function BuildPreviewEntriesForUnit(unitToken)
  local _, classToken = UnitClass(unitToken or "player")
  local preview = {}
  local now = GetTime()

  for _, entry in ipairs(Model.BuildPreviewIcons(classToken or "DEATHKNIGHT")) do
    local previewEntry = {
      key = entry.key,
      spellID = entry.spellID,
      kind = "DEF",
      cd = entry.cd or 0,
      startTime = entry.startTime or 0,
      readyAt = 0,
    }

    if entry.previewRemaining and entry.previewRemaining > 0 and (entry.cd or 0) > 0 then
      previewEntry.startTime = now - ((entry.cd or 0) - entry.previewRemaining)
      previewEntry.readyAt = previewEntry.startTime + (entry.cd or 0)
    end

    preview[#preview + 1] = previewEntry
  end

  return Model.SortIcons(preview, now)
end

UpdateAttachments = function()
  local moduleDB = EnsureModuleDB()
  if not moduleDB then
    HideUnusedAttachments({})
    RefreshAttachmentTicker()
    return
  end

  local partyFrame = CompactPartyFrame
  if not partyFrame or type(partyFrame.memberUnitFrames) ~= "table" then
    RefreshAttachmentTicker()
    return
  end

  if not IsAttachmentActive() then
    HideUnusedAttachments({})
    RefreshAttachmentTicker()
    return
  end

  local seenFrames = {}

  for _, memberFrame in ipairs(partyFrame.memberUnitFrames) do
    local unitToken = memberFrame.unit or memberFrame.displayedUnit
    local entries

    if ShouldShowPreview() then
      if unitToken and UnitExists(unitToken) then
        entries = BuildPreviewEntriesForUnit(unitToken)
      elseif memberFrame == partyFrame.memberUnitFrames[1] then
        entries = BuildPreviewEntriesForUnit("player")
      end
    elseif unitToken then
      entries = CollectEntriesForUnit(unitToken)
    end

    if entries and #entries > 0 then
      RenderAttachment(memberFrame, entries)
      seenFrames[memberFrame] = true
    end
  end

  HideUnusedAttachments(seenFrames)
  RefreshAttachmentTicker()
end

local TryHookCompactPartyFrameLater

local function HookCompactPartyFrame()
  local partyFrame = CompactPartyFrame
  if not partyFrame then
    TryHookCompactPartyFrameLater()
    return
  end

  if hookedPartyFrame == partyFrame then
    UpdateAttachments()
    return
  end

  if hooksecurefunc and partyFrame.RefreshMembers then
    hooksecurefunc(partyFrame, "RefreshMembers", function()
      UpdateAttachments()
    end)
  end

  hookedPartyFrame = partyFrame
  hookRetryScheduled = false
  UpdateAttachments()
end

TryHookCompactPartyFrameLater = function()
  if hookRetryScheduled or not IsAttachmentActive() then
    return
  end

  hookRetryScheduled = true
  AfterDelay(0.2, function()
    hookRetryScheduled = false
    if not IsAttachmentActive() then
      return
    end

    HookCompactPartyFrame()
  end)
end

local PruneRuntimeEntriesForUser
local PruneRuntimeState
local ReconcilePartyUser

local function RegisterExpectedDefensiveEntries(playerGUID, playerName, classToken, spellIDs, unitToken, specID)
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
        key = BuildRuntimeKey(playerGUID, spellID),
        playerGUID = playerGUID,
        playerName = playerName,
        classToken = classToken,
        unitToken = unitToken,
        spellID = spellID,
        kind = "DEF",
        baseCd = trackedSpell.cd,
        cd = trackedSpell.cd,
        charges = trackedSpell.charges or 1,
        startTime = 0,
        readyAt = 0,
      })
    end
  end
end

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
          spellEntries, specID = GetLocalOwnedDefensiveSpells(classToken)
        elseif previousUser and type(previousUser.spellIDs) == "table" and #previousUser.spellIDs > 0 then
          spellEntries = SpellDB.GetKnownDefensiveSpellsForClass(classToken, specID, previousUser.spellIDs)
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
          hasExplicitManifest = false,
        }
        runtime.partyUsers[playerName] = user

        ReconcilePartyUser(user, previousUser)
        RegisterExpectedDefensiveEntries(playerGUID, playerName, classToken, spellIDs, unit, specID)
        PruneRuntimeEntriesForUser(playerGUID, spellIDs)
      end
    end
  end

  PruneRuntimeState()
end

local function IsTrackedSender(userKey)
  if not userKey then
    return false
  end

  for _, unit in ipairs(BuildRuntimeUnits()) do
    if UnitExists(unit) and ShortName(UnitName(unit)) == userKey then
      return true
    end
  end

  local user = runtime.partyUsers[userKey]
  return user ~= nil and user.unitToken ~= nil
end

local function GetOrCreatePartyUser(userKey, fallbackSpellID)
  local user = runtime.partyUsers[userKey]
  if user then
    return user
  end

  local trackedSpell = fallbackSpellID and GetTrackedDefensiveInfo(fallbackSpellID) or nil
  user = {
    key = userKey,
    playerGUID = BuildRemoteGuid(userKey),
    playerName = userKey,
    classToken = trackedSpell and trackedSpell.classToken or nil,
    specID = nil,
    unitToken = nil,
    spellIDs = {},
    hasExplicitManifest = false,
  }
  runtime.partyUsers[userKey] = user
  return user
end

local function RegisterUserManifest(user, spellIDs)
  user.spellIDs = {}
  user.hasExplicitManifest = true

  for _, spellID in ipairs(spellIDs or {}) do
    local trackedSpell = SpellDB.ResolveDefensiveSpell(spellID, user.specID)
    if trackedSpell then
      user.spellIDs[#user.spellIDs + 1] = spellID
      user.classToken = user.classToken or trackedSpell.classToken
    end
  end

  PruneRuntimeEntriesForUser(user.playerGUID, user.spellIDs)
  RegisterExpectedDefensiveEntries(user.playerGUID, user.playerName, user.classToken, user.spellIDs, user.unitToken, user.specID)
end

local function RefreshFallbackSnapshot(unitToken)
  if not unitToken or unitToken == "player" then
    return
  end

  if not db or not db.enabled or not UnitExists(unitToken) then
    runtime.fallback:RemoveUnit(unitToken)
    return
  end

  runtime.fallback:ProcessAuraSnapshot(unitToken, BuildDefensiveAuraSnapshot(unitToken))
end

local function RefreshFallbackRoster()
  for _, unit in ipairs(BuildRuntimeUnits()) do
    if unit ~= "player" then
      RefreshFallbackSnapshot(unit)
    end
  end
end

local function ApplyDefensiveFallback(payload)
  local unit = payload and payload.ownerUnit
  local spellID = payload and payload.spellID
  if not unit or unit == "player" or not UnitExists(unit) or type(spellID) ~= "number" then
    return
  end

  local userKey = ShortName(UnitName(unit))
  local user = userKey and runtime.partyUsers[userKey] or nil
  if not user or not user.playerGUID then
    return
  end

  local trackedSpell = SpellDB.ResolveDefensiveSpell(spellID, user.specID)
  if not trackedSpell or trackedSpell.kind ~= "DEF" then
    return
  end

  local spellSet = BuildSpellSet(user.spellIDs)
  if not spellSet[spellID] then
    user.spellIDs[#user.spellIDs + 1] = spellID
  end

  local runtimeKey = BuildRuntimeKey(user.playerGUID, spellID)
  local existing = runtime.engine:GetEntry(runtimeKey)
  local readyAt = payload.readyAt or ((payload.startTime or GetTime()) + (payload.baseCd or trackedSpell.cd))
  if existing then
    if existing.source == "self" or existing.source == "sync" then
      return
    end
    if (existing.readyAt or 0) >= readyAt then
      return
    end
  end

  local applied = runtime.engine:UpsertEntry({
    key = runtimeKey,
    playerGUID = user.playerGUID,
    playerName = user.playerName,
    classToken = user.classToken or trackedSpell.classToken,
    unitToken = user.unitToken or unit,
    spellID = spellID,
    source = payload.source or "aura",
    kind = "DEF",
    startTime = payload.startTime or GetTime(),
    readyAt = readyAt,
    baseCd = payload.baseCd or trackedSpell.cd,
    cd = payload.baseCd or trackedSpell.cd,
    charges = trackedSpell.charges or 1,
  })

  if applied then
    UpdateAttachments()
  end
end

PruneRuntimeEntriesForUser = function(playerGUID, spellIDs)
  if not playerGUID then
    return
  end

  local allowedSpells = BuildSpellSet(spellIDs)
  for _, entry in ipairs(runtime.engine:GetEntriesByKind("DEF")) do
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

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("DEF")) do
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

  if previousUser.hasExplicitManifest then
    user.hasExplicitManifest = true
  end

  if previousUser.playerGUID == user.playerGUID then
    return
  end

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("DEF")) do
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

local function SendCurrentSelfState()
  if not db or not db.enabled then
    return
  end

  if not IsInGroup or not IsInGroup() then
    return
  end

  local playerGUID = UnitGUID("player")
  if not playerGUID then
    return
  end

  for _, entry in ipairs(runtime.engine:GetEntriesByKind("DEF")) do
    if entry.playerGUID == playerGUID then
      local remaining = GetEntryRemaining(entry)
      if remaining > 0 then
        Sync.Send("DEF_STATE", {
          spellID = entry.spellID,
          kind = "DEF",
          cd = entry.baseCd or entry.cd or 0,
          charges = entry.charges or 1,
          remaining = remaining,
        })
      end
    end
  end
end

local function AnnouncePresence()
  if not db or not db.enabled then
    return
  end

  if not IsInGroup or not IsInGroup() then
    return
  end

  local _, classToken = UnitClass("player")
  local ownedSpells, specID = GetLocalOwnedDefensiveSpells(classToken)
  Sync.Send("HELLO", {
    classToken = classToken,
    specID = specID,
  })

  Sync.Send("DEF_MANIFEST", {
    kind = "DEF",
    spells = ExtractSpellIDs(ownedSpells),
  })
  SendCurrentSelfState()
end

local function SchedulePresenceAnnounce()
  if not db or not db.enabled then
    return
  end

  AfterDelay(1.0, function()
    if db and db.enabled then
      AnnouncePresence()
    end
  end)
end

local function HandleSyncHelloMessage(payload, sender)
  local userKey = NormalizeName(sender)
  if not userKey or not IsTrackedSender(userKey) then
    return
  end

  local user = GetOrCreatePartyUser(userKey)
  if payload and payload.classToken and payload.classToken ~= "" then
    user.classToken = payload.classToken
  end

  if payload and type(payload.specID) == "number" and payload.specID > 0 then
    user.specID = payload.specID
  end

  SendCurrentSelfState()
  UpdateAttachments()
end

local function HandleSyncManifestMessage(payload, sender)
  local userKey = NormalizeName(sender)
  if not userKey or not IsTrackedSender(userKey) then
    return
  end

  if payload and payload.kind ~= nil and payload.kind ~= "DEF" then
    return
  end

  local user = GetOrCreatePartyUser(userKey)
  RegisterUserManifest(user, payload and payload.spells or {})
  PruneRuntimeState()
  UpdateAttachments()
end

local function HandleSyncDefensiveStateMessage(payload, sender)
  local userKey = NormalizeName(sender)
  if not userKey or not IsTrackedSender(userKey) or type(payload) ~= "table" then
    return
  end

  if payload.kind ~= nil and payload.kind ~= "DEF" then
    return
  end

  local user = GetOrCreatePartyUser(userKey, payload.spellID)
  local trackedSpell = SpellDB.ResolveDefensiveSpell(payload.spellID, user.specID)
  if not trackedSpell then
    return
  end

  if not user.classToken then
    user.classToken = trackedSpell.classToken
  end
  local spellSet = BuildSpellSet(user.spellIDs)
  if user.hasExplicitManifest and not spellSet[payload.spellID] then
    return
  end
  if not spellSet[payload.spellID] then
    user.spellIDs[#user.spellIDs + 1] = payload.spellID
  end

  local cooldown = payload.cd
  if type(cooldown) ~= "number" or cooldown <= 0 then
    cooldown = trackedSpell.cd
  end

  local now = GetTime()
  local remaining = payload.remaining
  if type(remaining) ~= "number" or remaining < 0 then
    remaining = nil
  end

  local applied = runtime.engine:ApplySyncState(user.playerGUID, payload.spellID, {
    kind = payload.kind or "DEF",
    cd = cooldown,
    charges = payload.charges or 1,
    remaining = remaining,
    observedAt = now,
    readyAt = payload.readyAt,
    startTime = payload.startTime,
  })

  if applied then
    applied.playerName = user.playerName
    applied.classToken = user.classToken
    applied.unitToken = user.unitToken
    applied.kind = "DEF"
    applied.baseCd = applied.baseCd or cooldown
    applied.cd = cooldown
  end

  UpdateAttachments()
end

local function HandleSyncMessage(message, sender)
  if not db or not db.enabled then
    return
  end

  local messageType, payload = Sync.Decode(message)
  if messageType == "HELLO"
    or (messageType == "DEF_MANIFEST" and (payload == nil or payload.kind == nil or payload.kind == "DEF"))
    or (messageType == "DEF_STATE" and (payload == nil or payload.kind == nil or payload.kind == "DEF"))
  then
    addon:DebugLog("pdef", "recv sync", sender or "?", message or "")
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
  HookCompactPartyFrame()
  UpdateAttachments()
end

module.applyDefensiveFallback = ApplyDefensiveFallback

function module:ResetPosition(moduleDB)
  moduleDB = moduleDB or db or (addon.db and addon.db.modules and addon.db.modules.PartyDefensiveTracker)
  if not moduleDB then
    return
  end

  ResetAttachmentSettings(moduleDB)
  NormalizeAttachmentSettings(moduleDB)
  db = moduleDB
  HookCompactPartyFrame()
  UpdateAttachments()
end

function module:buildSettings(panel, helpers, addonRef, moduleDB)
  db = moduleDB

  local function GetEditButtonLabel()
    if addonRef.db.global.editMode and (
      addonRef.db.global.activeEditModule == "PartyDefensiveTracker"
      or addonRef.db.global.activeEditModule == "ALL"
    ) then
      return "Lock Tracker"
    end

    return "Open Edit Mode"
  end

  local stateLabel = helpers:CreateDividerLabel(panel, "State", nil, 0)
  local stateBody = helpers:CreateSectionHint(panel, "Enable the attachment tracker and place it around the party frame.", 520)
  stateBody:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)

  local enabledBox = helpers:CreateInlineCheckbox(panel, "Enable Party Defensive Tracker", moduleDB.enabled, function(value)
    addonRef:SetModuleValue("PartyDefensiveTracker", "enabled", value)
  end)
  enabledBox:SetPoint("TOPLEFT", stateBody, "BOTTOMLEFT", 0, -12)

  local editButton = helpers:CreateActionButton(panel, GetEditButtonLabel(), function(self)
    local isActive = addonRef.db.global.editMode and (
      addonRef.db.global.activeEditModule == "PartyDefensiveTracker"
      or addonRef.db.global.activeEditModule == "ALL"
    )
    addonRef:SetEditMode(not isActive, isActive and nil or "PartyDefensiveTracker")
    self:SetText(GetEditButtonLabel())
    addonRef:RefreshSettings()
  end)

  local resetButton = helpers:CreateActionButton(panel, "Reset Position", function()
    module:ResetPosition(moduleDB)
    addonRef:RefreshSettings()
  end)
  helpers:PlaceRow(enabledBox, editButton, resetButton, -12, 12)

  local stateHint = helpers:CreateSectionHint(panel, "Edit mode previews the icons directly on Blizzard party frames.", 420)
  stateHint:SetPoint("TOPLEFT", editButton, "BOTTOMLEFT", 0, -12)

  local behaviorColumn, layoutColumn = helpers:CreateSectionColumns(panel, stateHint, -24)

  local behaviorLabel = helpers:CreateDividerLabel(behaviorColumn, "Behavior", nil, 0)
  local behaviorBody = helpers:CreateSectionHint(behaviorColumn, "Preview and tooltip behavior.", 250)
  behaviorBody:SetPoint("TOPLEFT", behaviorLabel, "BOTTOMLEFT", 0, -8)

  local tooltipBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show Tooltip", moduleDB.showTooltip ~= false, function(value)
    addonRef:SetModuleValue("PartyDefensiveTracker", "showTooltip", value)
  end)
  tooltipBox:SetPoint("TOPLEFT", behaviorBody, "BOTTOMLEFT", 0, -12)

  local behaviorHint = helpers:CreateSectionHint(
    behaviorColumn,
    "SunderingTools keeps sync and aura fallback automatic; tooltips show owner, spell, and status.",
    250
  )
  behaviorHint:SetPoint("TOPLEFT", tooltipBox, "BOTTOMLEFT", 0, -12)

  local layoutLabel = helpers:CreateDividerLabel(layoutColumn, "Layout", nil, 0)
  local layoutBody = helpers:CreateSectionHint(layoutColumn, "Adjust icon count, size, spacing, and attachment points.", 250)
  layoutBody:SetPoint("TOPLEFT", layoutLabel, "BOTTOMLEFT", 0, -8)

  local maxIconsSlider = helpers:CreateLabeledSlider(layoutColumn, "Maximum Icons", 1, 8, 1, moduleDB.maxIcons, function(value)
    addonRef:SetModuleValue("PartyDefensiveTracker", "maxIcons", value)
  end, 250)
  maxIconsSlider:SetPoint("TOPLEFT", layoutBody, "BOTTOMLEFT", 0, -12)

  local iconSizeSlider = helpers:CreateLabeledSlider(layoutColumn, "Icon Size", 12, 32, 1, moduleDB.iconSize, function(value)
    addonRef:SetModuleValue("PartyDefensiveTracker", "iconSize", value)
  end, 250)
  iconSizeSlider:SetPoint("TOPLEFT", maxIconsSlider, "BOTTOMLEFT", 0, -10)

  local iconSpacingSlider = helpers:CreateLabeledSlider(layoutColumn, "Icon Spacing", 0, 8, 1, moduleDB.iconSpacing, function(value)
    addonRef:SetModuleValue("PartyDefensiveTracker", "iconSpacing", value)
  end, 250)
  iconSpacingSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -10)

  local attachPointDropdown = helpers:CreateLabeledDropdown(
    layoutColumn,
    "Attach Point",
    ATTACHMENT_POINT_OPTIONS,
    moduleDB.attachPoint,
    210,
    function(value)
      addonRef:SetModuleValue("PartyDefensiveTracker", "attachPoint", value)
    end
  )
  attachPointDropdown:SetPoint("TOPLEFT", iconSpacingSlider, "BOTTOMLEFT", 0, -10)

  local relativePointDropdown = helpers:CreateLabeledDropdown(
    layoutColumn,
    "Relative Point",
    ATTACHMENT_POINT_OPTIONS,
    moduleDB.relativePoint,
    210,
    function(value)
      addonRef:SetModuleValue("PartyDefensiveTracker", "relativePoint", value)
    end
  )
  relativePointDropdown:SetPoint("TOPLEFT", attachPointDropdown, "BOTTOMLEFT", 0, -10)

  local offsetXSlider = helpers:CreateLabeledSlider(layoutColumn, "Offset X", -40, 40, 1, moduleDB.offsetX, function(value)
    addonRef:SetModuleValue("PartyDefensiveTracker", "offsetX", value)
  end, 250)
  offsetXSlider:SetPoint("TOPLEFT", relativePointDropdown, "BOTTOMLEFT", 0, -10)

  local offsetYSlider = helpers:CreateLabeledSlider(layoutColumn, "Offset Y", -40, 40, 1, moduleDB.offsetY, function(value)
    addonRef:SetModuleValue("PartyDefensiveTracker", "offsetY", value)
  end, 250)
  offsetYSlider:SetPoint("TOPLEFT", offsetXSlider, "BOTTOMLEFT", 0, -10)
end

function module:onConfigChanged(_, moduleDB)
  NormalizeAttachmentSettings(moduleDB)
  db = moduleDB
  HookCompactPartyFrame()
  if moduleDB and moduleDB.enabled then
    RefreshRuntimeRoster()
  end
  UpdateAttachments()
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    db = addon.db and addon.db.PartyDefensiveTracker
    NormalizeAttachmentSettings(db)
    Sync.RegisterPrefix()
    HookCompactPartyFrame()

    if db and db.enabled then
      RefreshRuntimeRoster()
      RefreshFallbackRoster()
      UpdateAttachments()
    end

  elseif event == "PLAYER_ENTERING_WORLD" then
    EnsureModuleDB()
    runtime.engine:Reset()
    runtime.fallback:Reset()
    RefreshRuntimeRoster()
    RefreshFallbackRoster()
    HookCompactPartyFrame()
    UpdateAttachments()
    SchedulePresenceAnnounce()

  elseif event == "CHALLENGE_MODE_START" then
    EnsureModuleDB()
    runtime.engine:Reset()
    runtime.fallback:Reset()
    RefreshRuntimeRoster()
    RefreshFallbackRoster()
    HookCompactPartyFrame()
    UpdateAttachments()
    SchedulePresenceAnnounce()

  elseif event == "GROUP_ROSTER_UPDATE" then
    EnsureModuleDB()
    RefreshRuntimeRoster()
    RefreshFallbackRoster()
    HookCompactPartyFrame()
    UpdateAttachments()
    SchedulePresenceAnnounce()

  elseif event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
    EnsureModuleDB()
    InvalidateLocalTalentCache()
    RefreshRuntimeRoster()
    RefreshFallbackRoster()
    HookCompactPartyFrame()
    UpdateAttachments()

  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if not db or not db.enabled then return end

    local unit, _, spellID = ...
    if unit ~= "player" then return end
    if type(spellID) ~= "number" then return end

    local trackedSpell = GetTrackedDefensiveInfo(spellID)
    if not trackedSpell then
      return
    end

    local now = GetTime()
    local playerGUID = UnitGUID("player")
    local canonicalSpellID = trackedSpell.spellID or spellID
    addon:DebugLog("pdef", "self cast", "event", spellID, "spell", canonicalSpellID, "cd", trackedSpell.cd)
    local applied = runtime.engine:ApplySelfCast(playerGUID, canonicalSpellID, now, now + trackedSpell.cd)
    if applied then
      applied.playerName = ShortName(UnitName("player"))
      applied.classToken = trackedSpell.classToken or select(2, UnitClass("player"))
      applied.unitToken = "player"
      applied.kind = "DEF"
      applied.baseCd = trackedSpell.cd
      applied.cd = trackedSpell.cd
      applied.charges = trackedSpell.charges or 1

      if IsInGroup() then
        addon:DebugLog("pdef", "send sync", canonicalSpellID, "cd", trackedSpell.cd, "remaining", trackedSpell.cd)
        Sync.Send("DEF_STATE", {
          spellID = canonicalSpellID,
          kind = "DEF",
          cd = trackedSpell.cd,
          charges = trackedSpell.charges or 1,
          remaining = trackedSpell.cd,
        })
      end
      UpdateAttachments()
    end

  elseif event == "UNIT_AURA" then
    if not db or not db.enabled then
      return
    end

    local unitToken = ...
    RefreshFallbackSnapshot(unitToken)

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, _, sender = ...
    if prefix ~= Sync.GetPrefix() then
      return
    end

    HandleSyncMessage(message, sender)
  end
end)

runtime.fallback:RegisterCallback(ApplyDefensiveFallback)

addon.PartyDefensiveTracker = module
addon:RegisterModule(module)
