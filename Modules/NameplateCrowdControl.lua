local addon = _G.SunderingTools
if not addon then return end

local Watcher = assert(
  _G.SunderingToolsPartyCrowdControlAuraWatcher,
  "SunderingToolsPartyCrowdControlAuraWatcher must load before NameplateCrowdControl.lua"
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

local runtime = {
  watcher = Watcher.New({
    getTime = GetTime,
    isSecretValue = _G.issecretvalue,
    isCrowdControl = function(aura)
      return aura and aura.isCrowdControl == true
    end,
  }),
  activeByUnit = {},
}

local function IsNameplateUnit(unitToken)
  return type(unitToken) == "string" and string.match(unitToken, "^nameplate%d+$") ~= nil
end

local function GetSpellIcon(spellID)
  if spellID and C_Spell and C_Spell.GetSpellTexture then
    return C_Spell.GetSpellTexture(spellID)
  end

  if spellID and GetSpellTexture then
    return GetSpellTexture(spellID)
  end

  return "Interface\\Icons\\INV_Misc_QuestionMark"
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
    if payload.spellID and GameTooltip.SetSpellByID then
      GameTooltip:SetSpellByID(payload.spellID)
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
  local frame = EnsureAuraFrame(nameplate)
  if not frame or not payload then
    HideUnitFrame(unitToken)
    return
  end

  frame:ClearAllPoints()
  frame:SetPoint("BOTTOM", nameplate, "TOP", db.offsetX or 0, db.offsetY or 0)
  frame:SetSize(db.iconSize or 22, db.iconSize or 22)
  frame.icon:SetTexture(GetSpellIcon(payload.spellID))
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
    runtime.activeByUnit[unitToken][payload.auraInstanceID] = payload
  elseif event == "CC_REMOVED" then
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

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    db = addon.db and addon.db.NameplateCrowdControl
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
  end
end)

addon.NameplateCrowdControl = module
addon:RegisterModule(module)
