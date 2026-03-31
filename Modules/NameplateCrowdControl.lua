local addon = _G.SunderingTools
if not addon then return end

local Watcher = assert(
  _G.SunderingToolsPartyCrowdControlAuraWatcher,
  "SunderingToolsPartyCrowdControlAuraWatcher must load before NameplateCrowdControl.lua"
)
local Sync = assert(
  _G.SunderingToolsCombatTrackSync,
  "SunderingToolsCombatTrackSync must load before NameplateCrowdControl.lua"
)

local module = {
  key = "NameplateCrowdControl",
  label = "Nameplate Crowd Control",
  description = "Show active crowd control on nameplates while the aura exists.",
  order = 20,
  defaults = {
    enabled = true,
    showInDungeon = true,
    showInWorld = true,
    iconSize = 22,
    offsetX = 0,
    offsetY = 16,
    showTimer = true,
    showTooltip = true,
  },
}

local db = addon.db and addon.db.NameplateCrowdControl
local previewEnabled = false
local previewFrame = nil
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local GENERIC_CC_ICON = "Interface\\Icons\\Spell_Frost_ChainsOfIce"
local SYNC_CORRELATION_WINDOW = 1.0
local SYNC_RETENTION_WINDOW = 3.0

local runtime = {
  watcher = Watcher.New({
    getTime = GetTime,
    isSecretValue = _G.issecretvalue,
    isCrowdControl = function(aura)
      return aura and aura.isCrowdControl == true
    end,
  }),
  activeByUnit = {},
  recentSyncs = {},
  correlatedAuras = {},
}

local function IsNameplateUnit(unitToken)
  return type(unitToken) == "string" and string.match(unitToken, "^nameplate%d+$") ~= nil
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

local function BuildAuraKey(unitToken, auraInstanceID)
  if not unitToken or not auraInstanceID then
    return nil
  end

  return tostring(unitToken) .. ":" .. tostring(auraInstanceID)
end

local function ResolveSourceShortName(sourceUnit)
  if type(sourceUnit) ~= "string" or sourceUnit == "" then
    return nil
  end

  local okName, sourceName = pcall(UnitName, sourceUnit)
  if okName and sourceName and sourceName ~= "" then
    return ShortName(sourceName)
  end

  return nil
end

local function PruneRecentSyncs(now)
  now = now or GetTime()

  local kept = {}
  for _, syncEvent in ipairs(runtime.recentSyncs) do
    if (now - (syncEvent.observedAt or 0)) <= SYNC_RETENTION_WINDOW then
      kept[#kept + 1] = syncEvent
    end
  end

  runtime.recentSyncs = kept
end

local function EnsureCorrelationState(payload)
  if type(payload) ~= "table" then
    return payload
  end

  if payload.icon ~= nil or payload.iconFileID ~= nil then
    return payload
  end

  if type(payload.spellID) == "number" and payload.spellID > 0 then
    return payload
  end

  payload.correlationState = "CC_UNKNOWN"
  return payload
end

local function ApplyCorrelationMatch(payload, match)
  if type(payload) ~= "table" then
    return payload
  end

  EnsureCorrelationState(payload)

  if type(match) == "table" and type(match.spellID) == "number" and match.spellID > 0 then
    payload.syncSpellID = match.spellID
    payload.syncSenderShort = match.senderShort
    payload.correlationState = "SYNCED"
  end

  return payload
end

local function RestoreCorrelationMatch(payload)
  if type(payload) ~= "table" then
    return payload
  end

  EnsureCorrelationState(payload)

  local auraKey = BuildAuraKey(payload.unitToken, payload.auraInstanceID)
  local match = auraKey and runtime.correlatedAuras[auraKey] or nil
  if match then
    ApplyCorrelationMatch(payload, match)
  end

  return payload
end

local function GetSpellIcon(spellID)
  if spellID and C_Spell and C_Spell.GetSpellTexture then
    return C_Spell.GetSpellTexture(spellID)
  end

  if spellID and GetSpellTexture then
    return GetSpellTexture(spellID)
  end

  return FALLBACK_ICON
end

local function ResolvePayloadIcon(payload)
  if type(payload) == "table" then
    local icon = payload.icon or payload.iconFileID
    if icon ~= nil then
      return icon
    end

    local syncedSpellID = payload.syncSpellID or payload.spellID
    if type(syncedSpellID) == "number" and syncedSpellID > 0 then
      local resolvedIcon = GetSpellIcon(syncedSpellID)
      if resolvedIcon ~= FALLBACK_ICON then
        return resolvedIcon
      end
    end

    if payload.correlationState == "CC_UNKNOWN" then
      return GENERIC_CC_ICON
    end
  end

  return GetSpellIcon(payload and payload.spellID or nil)
end

local function HasDisplayablePayload(payload)
  if type(payload) ~= "table" then
    return false
  end

  if payload.icon ~= nil or payload.iconFileID ~= nil then
    return true
  end

  if payload.correlationState == "CC_UNKNOWN" then
    return true
  end

  return ResolvePayloadIcon(payload) ~= FALLBACK_ICON
end

local function ResolveSynchronizedPayload(unitToken, payload)
  if type(payload) ~= "table" then
    return payload
  end

  payload.unitToken = payload.unitToken or unitToken
  RestoreCorrelationMatch(payload)
  EnsureCorrelationState(payload)

  if payload.correlationState ~= "CC_UNKNOWN" or payload.syncSpellID ~= nil then
    return payload
  end

  local auraKey = BuildAuraKey(unitToken, payload.auraInstanceID)
  local now = GetTime()
  PruneRecentSyncs(now)
  local sourceShort = ResolveSourceShortName(payload.sourceUnit)

  if not sourceShort then
    return payload
  end

  local matchedSpellID = nil
  local matchedSync = nil

  for _, syncEvent in ipairs(runtime.recentSyncs) do
    local delta = now - (syncEvent.observedAt or 0)
    if syncEvent.senderShort == sourceShort and delta >= 0 and delta <= SYNC_CORRELATION_WINDOW then
      if matchedSpellID == nil then
        matchedSpellID = syncEvent.spellID
        matchedSync = syncEvent
      elseif matchedSpellID ~= syncEvent.spellID then
        return payload
      end
    end
  end

  if auraKey and matchedSync and matchedSpellID then
    runtime.correlatedAuras[auraKey] = {
      spellID = matchedSpellID,
      senderShort = matchedSync.senderShort,
      observedAt = matchedSync.observedAt,
    }
    ApplyCorrelationMatch(payload, runtime.correlatedAuras[auraKey])
  end

  return payload
end

local function FormatRemaining(remaining)
  if type(remaining) ~= "number" or remaining <= 0 then
    return ""
  end

  if remaining >= 10 then
    return tostring(math.floor(remaining + 0.5))
  end

  return string.format("%.1f", remaining)
end

local function IsCurrentContextAllowed()
  if not db or not db.enabled then
    return false
  end

  local _, instanceType = GetInstanceInfo()
  if instanceType == "party" then
    return db.showInDungeon ~= false
  elseif instanceType == "raid" or instanceType == "arena" then
    return false
  end

  return db.showInWorld ~= false
end

local function PickDisplayAura(unitToken)
  local active = runtime.activeByUnit[unitToken]
  local best = nil

  for _, payload in pairs(active or {}) do
    if not best then
      best = payload
    else
      local bestRemaining = best.remaining or -1
      local currentRemaining = payload.remaining or -1
      if currentRemaining > bestRemaining then
        best = payload
      elseif currentRemaining == bestRemaining and (payload.auraInstanceID or 0) < (best.auraInstanceID or 0) then
        best = payload
      end
    end
  end

  return best
end

local function EnsureAuraFrame(parent)
  if not parent then
    return nil
  end

  local frame = parent.SunderingToolsNameplateCrowdControl
  if frame then
    return frame
  end

  frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(28, 28)
  frame:EnableMouse(true)

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetAllPoints()
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  frame.border = frame:CreateTexture(nil, "OVERLAY")
  frame.border:SetAllPoints()
  frame.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
  frame.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
  frame.border:SetVertexColor(0.9, 0.3, 0.3, 0.9)

  frame.cooldownText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.cooldownText:SetPoint("CENTER", frame, "CENTER", 0, 0)
  frame.cooldownText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
  frame.cooldownText:SetJustifyH("CENTER")
  frame.cooldownText:SetJustifyV("MIDDLE")

  frame:SetScript("OnEnter", function(self)
    if not db or db.showTooltip == false then
      return
    end

  local payload = self._payload
  if not payload then
    return
  end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Crowd Control Active", 1, 1, 1)
    local tooltipSpellID = payload.syncSpellID or payload.spellID
    if tooltipSpellID and GameTooltip.SetSpellByID then
      GameTooltip:SetSpellByID(tooltipSpellID)
    elseif payload.name and payload.name ~= "" then
      GameTooltip:AddLine(payload.name, 0.95, 0.82, 0.18)
    else
      GameTooltip:AddLine("Restricted aura", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  frame:Hide()

  parent.SunderingToolsNameplateCrowdControl = frame
  return frame
end

local function HideUnitFrame(unitToken)
  local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unitToken)
  local frame = nameplate and nameplate.SunderingToolsNameplateCrowdControl or nil
  if frame then
    frame._payload = nil
    frame:Hide()
  end
end

local function UpdateUnitFrame(unitToken)
  if not IsNameplateUnit(unitToken) or not IsCurrentContextAllowed() then
    HideUnitFrame(unitToken)
    return
  end

  local nameplate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unitToken)
  if not nameplate then
    return
  end

  local payload = PickDisplayAura(unitToken)
  payload = ResolveSynchronizedPayload(unitToken, payload)
  local frame = EnsureAuraFrame(nameplate)
  if not frame or not payload or not HasDisplayablePayload(payload) then
    HideUnitFrame(unitToken)
    return
  end

  frame:ClearAllPoints()
  frame:SetPoint("BOTTOM", nameplate, "TOP", db.offsetX or 0, db.offsetY or 0)
  frame:SetSize(db.iconSize or 22, db.iconSize or 22)
  frame.icon:SetTexture(ResolvePayloadIcon(payload))
  frame.cooldownText:SetShown(db.showTimer ~= false and payload.remaining ~= nil)
  frame.cooldownText:SetText(FormatRemaining(payload.remaining))
  frame._payload = payload
  frame:Show()
end

local function BuildCrowdControlSnapshot(unitToken)
  local snapshot = {}
  local auras = C_UnitAuras and C_UnitAuras.GetUnitAuras and C_UnitAuras.GetUnitAuras(unitToken, "HARMFUL|CROWD_CONTROL")

  for _, aura in ipairs(auras or {}) do
    if aura and aura.auraInstanceID then
      aura.isCrowdControl = true
      snapshot[#snapshot + 1] = aura
    end
  end

  return snapshot
end

local function UpdateInfoTouchesCrowdControl(unitToken, updateInfo)
  if not updateInfo or updateInfo.isFullUpdate then
    return true
  end

  if C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID then
    for _, aura in ipairs(updateInfo.addedAuras or {}) do
      local auraInstanceID = aura and aura.auraInstanceID or nil
      if auraInstanceID and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unitToken, auraInstanceID, "HARMFUL|CROWD_CONTROL") then
        return true
      end
    end

    for _, auraInstanceID in ipairs(updateInfo.updatedAuraInstanceIDs or {}) do
      if auraInstanceID and not C_UnitAuras.IsAuraFilteredOutByInstanceID(unitToken, auraInstanceID, "HARMFUL|CROWD_CONTROL") then
        return true
      end
    end
  elseif next(updateInfo.addedAuras or {}) or next(updateInfo.updatedAuraInstanceIDs or {}) then
    return true
  end

  local active = runtime.watcher.activeByUnit[unitToken]
  for _, auraInstanceID in ipairs(updateInfo.removedAuraInstanceIDs or {}) do
    if active and active[auraInstanceID] then
      return true
    end
  end

  return false
end

local function RefreshUnit(unitToken)
  if not IsNameplateUnit(unitToken) then
    return
  end

  if not db or not db.enabled or not IsCurrentContextAllowed() or not UnitExists(unitToken) then
    runtime.watcher:RemoveUnit(unitToken)
    runtime.activeByUnit[unitToken] = nil
    HideUnitFrame(unitToken)
    return
  end

  runtime.watcher:ProcessAuraSnapshot(unitToken, BuildCrowdControlSnapshot(unitToken))
end

local function RefreshAllNameplates()
  for index = 1, 40 do
    local unitToken = "nameplate" .. index
    if UnitExists(unitToken) then
      RefreshUnit(unitToken)
    else
      runtime.watcher:RemoveUnit(unitToken)
      runtime.activeByUnit[unitToken] = nil
      HideUnitFrame(unitToken)
    end
  end
end

local function EnsurePreviewFrame()
  if previewFrame then
    return previewFrame
  end

  previewFrame = CreateFrame("Frame", "SunderingToolsNameplateCrowdControlPreview", UIParent)
  previewFrame:SetSize(160, 42)
  previewFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
  previewFrame:SetFrameStrata("DIALOG")

  previewFrame.nameplate = previewFrame:CreateTexture(nil, "BACKGROUND")
  previewFrame.nameplate:SetPoint("BOTTOMLEFT", previewFrame, "BOTTOMLEFT", 20, 10)
  previewFrame.nameplate:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", -20, 10)
  previewFrame.nameplate:SetHeight(12)
  previewFrame.nameplate:SetColorTexture(0.15, 0.15, 0.15, 0.9)

  previewFrame.castBar = previewFrame:CreateTexture(nil, "ARTWORK")
  previewFrame.castBar:SetPoint("TOPLEFT", previewFrame.nameplate, "BOTTOMLEFT", 0, 4)
  previewFrame.castBar:SetPoint("TOPRIGHT", previewFrame.nameplate, "BOTTOMRIGHT", 0, 4)
  previewFrame.castBar:SetHeight(8)
  previewFrame.castBar:SetColorTexture(0.56, 0.34, 0.12, 0.9)

  previewFrame.label = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  previewFrame.label:SetPoint("BOTTOM", previewFrame.nameplate, "TOP", 0, 16)
  previewFrame.label:SetText("Nameplate CC Preview")

  previewFrame.iconHost = CreateFrame("Frame", nil, previewFrame)
  previewFrame.icon = EnsureAuraFrame(previewFrame.iconHost)
  previewFrame.icon:SetParent(previewFrame)

  return previewFrame
end

local function UpdatePreviewFrame()
  local frame = EnsurePreviewFrame()
  if not frame or not db then
    return
  end

  if not previewEnabled or not db.enabled then
    frame:Hide()
    return
  end

  frame.icon:ClearAllPoints()
  frame.icon:SetPoint("BOTTOM", frame.nameplate, "TOP", db.offsetX or 0, db.offsetY or 0)
  frame.icon:SetSize(db.iconSize or 22, db.iconSize or 22)
  frame.icon.icon:SetTexture(GetSpellIcon(118))
  frame.icon.cooldownText:SetShown(db.showTimer ~= false)
  frame.icon.cooldownText:SetText("4.2")
  frame.icon._payload = {
    spellID = 118,
    remaining = 4.2,
  }
  frame.icon:Show()
  frame:Show()
end

function module:SetPreviewEnabled(enabled)
  previewEnabled = enabled and true or false
  UpdatePreviewFrame()
end

function module:SetEditMode(enabled)
  module:SetPreviewEnabled(enabled)
end

function module:buildSettings(panel, helpers, addonRef, moduleDB)
  db = moduleDB

  local stateLabel = helpers:CreateDividerLabel(panel, "State", nil, 0)
  local stateBody = helpers:CreateSectionHint(panel, "Show active crowd control directly on enemy nameplates.", 520)
  stateBody:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)

  local enabledBox = helpers:CreateInlineCheckbox(panel, "Enable Nameplate Crowd Control", moduleDB.enabled, function(value)
    addonRef:SetModuleValue("NameplateCrowdControl", "enabled", value)
  end)
  enabledBox:SetPoint("TOPLEFT", stateBody, "BOTTOMLEFT", 0, -12)

  local previewButton = helpers:CreateActionButton(panel, "Preview Nameplate CC", function()
    module:SetPreviewEnabled(not previewEnabled)
  end)
  previewButton:SetPoint("TOPLEFT", enabledBox, "TOPRIGHT", 12, 0)

  local visibilityLabel = helpers:CreateDividerLabel(panel, "Visibility", previewButton, -22)
  local visibilityBody = helpers:CreateSectionHint(panel, "Only Dungeon and World contexts remain visible for this layer.", 520)
  visibilityBody:SetPoint("TOPLEFT", visibilityLabel, "BOTTOMLEFT", 0, -8)

  local dungeonBox = helpers:CreateInlineCheckbox(panel, "Show in Dungeons", moduleDB.showInDungeon ~= false, function(value)
    addonRef:SetModuleValue("NameplateCrowdControl", "showInDungeon", value)
  end)
  dungeonBox:SetPoint("TOPLEFT", visibilityBody, "BOTTOMLEFT", 0, -12)

  local worldBox = helpers:CreateInlineCheckbox(panel, "Show in World", moduleDB.showInWorld ~= false, function(value)
    addonRef:SetModuleValue("NameplateCrowdControl", "showInWorld", value)
  end)
  worldBox:SetPoint("TOPLEFT", dungeonBox, "BOTTOMLEFT", 0, -8)

  local layoutColumn, behaviorColumn = helpers:CreateSectionColumns(panel, worldBox, -26)

  local layoutLabel = helpers:CreateDividerLabel(layoutColumn, "Layout", nil, 0)
  local layoutBody = helpers:CreateSectionHint(layoutColumn, "Adjust icon scale and vertical placement above the nameplate.", 250)
  layoutBody:SetPoint("TOPLEFT", layoutLabel, "BOTTOMLEFT", 0, -8)

  local iconSizeSlider = helpers:CreateLabeledSlider(layoutColumn, "Icon Size", 14, 36, 1, moduleDB.iconSize, function(value)
    addonRef:SetModuleValue("NameplateCrowdControl", "iconSize", value)
  end, 250)
  iconSizeSlider:SetPoint("TOPLEFT", layoutBody, "BOTTOMLEFT", 0, -12)

  local offsetXSlider = helpers:CreateLabeledSlider(layoutColumn, "Offset X", -30, 30, 1, moduleDB.offsetX, function(value)
    addonRef:SetModuleValue("NameplateCrowdControl", "offsetX", value)
  end, 250)
  offsetXSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -10)

  local offsetYSlider = helpers:CreateLabeledSlider(layoutColumn, "Offset Y", -10, 40, 1, moduleDB.offsetY, function(value)
    addonRef:SetModuleValue("NameplateCrowdControl", "offsetY", value)
  end, 250)
  offsetYSlider:SetPoint("TOPLEFT", offsetXSlider, "BOTTOMLEFT", 0, -10)

  local behaviorLabel = helpers:CreateDividerLabel(behaviorColumn, "Behavior", nil, 0)
  local behaviorBody = helpers:CreateSectionHint(behaviorColumn, "Timers are secondary to the icon; tooltips stay optional.", 250)
  behaviorBody:SetPoint("TOPLEFT", behaviorLabel, "BOTTOMLEFT", 0, -8)

  local timerBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show Timer Text", moduleDB.showTimer ~= false, function(value)
    addonRef:SetModuleValue("NameplateCrowdControl", "showTimer", value)
  end)
  timerBox:SetPoint("TOPLEFT", behaviorBody, "BOTTOMLEFT", 0, -12)

  local tooltipBox = helpers:CreateInlineCheckbox(behaviorColumn, "Show Tooltip", moduleDB.showTooltip ~= false, function(value)
    addonRef:SetModuleValue("NameplateCrowdControl", "showTooltip", value)
  end)
  tooltipBox:SetPoint("TOPLEFT", timerBox, "BOTTOMLEFT", 0, -8)
end

function module:onConfigChanged(_, moduleDB)
  db = moduleDB
  UpdatePreviewFrame()
  RefreshAllNameplates()
end

runtime.watcher:RegisterCallback(function(event, payload)
  if type(payload) ~= "table" or not payload.unitToken then
    return
  end

  local unitToken = payload.unitToken
  runtime.activeByUnit[unitToken] = runtime.activeByUnit[unitToken] or {}

  if event == "CC_APPLIED" or event == "CC_UPDATED" then
    RestoreCorrelationMatch(payload)
    ResolveSynchronizedPayload(unitToken, payload)
    runtime.activeByUnit[unitToken][payload.auraInstanceID] = payload
  elseif event == "CC_REMOVED" then
    runtime.correlatedAuras[BuildAuraKey(unitToken, payload.auraInstanceID)] = nil
    runtime.activeByUnit[unitToken][payload.auraInstanceID] = nil
    if not next(runtime.activeByUnit[unitToken]) then
      runtime.activeByUnit[unitToken] = nil
    end
  end

  UpdateUnitFrame(unitToken)
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    db = addon.db and addon.db.NameplateCrowdControl
    Sync.RegisterPrefix()
    UpdatePreviewFrame()
    RefreshAllNameplates()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    previewEnabled = false
    for unitToken in pairs(runtime.activeByUnit) do
      runtime.watcher:RemoveUnit(unitToken)
      HideUnitFrame(unitToken)
    end
    wipe(runtime.activeByUnit)
    wipe(runtime.correlatedAuras)
    wipe(runtime.recentSyncs)
    UpdatePreviewFrame()
    RefreshAllNameplates()
    return
  end

  if event == "NAME_PLATE_UNIT_ADDED" then
    local unitToken = ...
    RefreshUnit(unitToken)
    return
  end

  if event == "NAME_PLATE_UNIT_REMOVED" then
    local unitToken = ...
    runtime.watcher:RemoveUnit(unitToken)
    runtime.activeByUnit[unitToken] = nil
    HideUnitFrame(unitToken)
    return
  end

  if event == "UNIT_AURA" then
    local unitToken, updateInfo = ...
    if not IsNameplateUnit(unitToken) or not UpdateInfoTouchesCrowdControl(unitToken, updateInfo) then
      return
    end

    RefreshUnit(unitToken)
    return
  end

  if event == "CHAT_MSG_ADDON" then
    local prefix, message, _, sender = ...
    if prefix ~= Sync.GetPrefix() then
      return
    end

    local messageType, payload = Sync.Decode(message)
    if messageType ~= "CC" or type(payload) ~= "table" then
      return
    end

    if type(payload.spellID) ~= "number" or payload.spellID <= 0 then
      return
    end

    runtime.recentSyncs[#runtime.recentSyncs + 1] = {
      spellID = payload.spellID,
      senderShort = ShortName(sender),
      observedAt = GetTime(),
    }
    PruneRecentSyncs()

    for unitToken, unitPayloads in pairs(runtime.activeByUnit) do
      for _, activePayload in pairs(unitPayloads or {}) do
        ResolveSynchronizedPayload(unitToken, activePayload)
      end
      UpdateUnitFrame(unitToken)
    end
  end
end)

addon.NameplateCrowdControl = module
addon:RegisterModule(module)
