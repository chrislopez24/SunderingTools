-- BloodlustSound
-- Play sound and show icon when bloodlust/heroism is cast

local addon = _G.SunderingTools
if not addon then return end

local Model = assert(
  _G.SunderingToolsBloodlustSoundModel,
  "SunderingToolsBloodlustSoundModel must load before BloodlustSound.lua"
)
local FramePositioning = assert(
  _G.SunderingToolsFramePositioning,
  "SunderingToolsFramePositioning must load before BloodlustSound.lua"
)
local TrackerFrame = assert(
  _G.SunderingToolsTrackerFrame,
  "SunderingToolsTrackerFrame must load before BloodlustSound.lua"
)

local module = {
  key = "BloodlustSound",
  label = "Bloodlust Tracker",
  description = "Sound alerts, icon behavior, and placement.",
  order = 20,
  defaults = {
    enabled = true,
    hideIcon = false,
    iconSize = 64,
    posX = 0,
    posY = 100,
    positionMode = "CENTER_OFFSET",
    soundFile = "Interface\\AddOns\\SunderingTools\\sounds\\pedrolust.mp3",
    soundChannel = "Master",
    iconStyle = "BL_ICON",
    customIconPath = "",
    duration = 40,
  },
}

local db = addon.db and addon.db.BloodlustSound

local BL_ICON_PEDRO = "Interface\\AddOns\\SunderingTools\\assets\\art\\pedro.tga"
local DEFAULT_BL_SPELL_ID = 2825
local PEDRO_ATLAS_COLS = 4
local PEDRO_ATLAS_ROWS = 8
local PEDRO_ATLAS_WIDTH = 1024
local PEDRO_ATLAS_HEIGHT = 2048
local PEDRO_USED_WIDTH = 770
local PEDRO_USED_HEIGHT = 1536
local PEDRO_FRAME_COUNT = 32
local PEDRO_FPS = 6
local BLOODLUST_AURA_IDS = {
  2825,   -- Bloodlust
  32182,  -- Heroism
  80353,  -- Time Warp
  264667, -- Primal Rage
  178207, -- Drums of Fury
  230935, -- Drums of the Mountain
  272678,
  160452,
  256740,
  292686,
  386540,
  390386, -- Fury of the Aspects
  381301,
}
local BLOODLUST_AURA_FALLBACK_NAMES = {
  "bloodlust",
  "heroism",
  "time warp",
  "primal rage",
  "drums of fury",
  "drums of the mountain",
  "fury of the aspects",
}
local LOCKOUT_AURA_IDS = {
  57723,  -- Exhaustion
  57724,  -- Sated
  80354,  -- Temporal Displacement
  264689, -- Fatigued
  390435, -- Exhaustion
}
local DEFAULT_LOCKOUT_DURATION = 600

local frame
local activeTimer
local lastSeenExpirationTime
local editModeEnabled = false
local displayState = "HIDDEN"
local bloodlustAuraNames

local RefreshAuraState
local GetPlayerAuraBySpellID

local function NormalizeName(value)
  if type(value) ~= "string" then
    return nil
  end

  if issecretvalue and issecretvalue(value) then
    return nil
  end

  local normalized = string.lower(value)
  normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
  if normalized == "" then
    return nil
  end

  return normalized
end

local function IsSecretValue(value)
  return value ~= nil and issecretvalue ~= nil and issecretvalue(value)
end

local function SanitizeAuraNumber(value)
  if type(value) ~= "number" or IsSecretValue(value) then
    return nil
  end

  return value
end

local function SanitizeAuraAsset(value)
  if IsSecretValue(value) then
    return nil
  end

  return value
end

local function BuildAuraNameSet(spellIDs, fallbackNames)
  local names = {}

  for _, fallbackName in ipairs(fallbackNames or {}) do
    names[fallbackName] = true
  end

  for _, spellID in ipairs(spellIDs or {}) do
    local spellName =
      (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
      or (GetSpellInfo and GetSpellInfo(spellID))
    local normalizedName = NormalizeName(spellName)
    if normalizedName then
      names[normalizedName] = true
    end
  end

  return names
end

local function GetBloodlustAuraNames()
  if not bloodlustAuraNames then
    bloodlustAuraNames = BuildAuraNameSet(BLOODLUST_AURA_IDS, BLOODLUST_AURA_FALLBACK_NAMES)
  end

  return bloodlustAuraNames
end

local function IsTrackedTriggerAura(spellID, normalizedName)
  spellID = SanitizeAuraNumber(spellID)
  if spellID then
    for _, trackedSpellID in ipairs(BLOODLUST_AURA_IDS) do
      if trackedSpellID == spellID then
        return true
      end
    end
  end

  return normalizedName ~= nil and GetBloodlustAuraNames()[normalizedName] == true
end

local function IsTrackedLockoutAura(spellID)
  spellID = SanitizeAuraNumber(spellID)
  if not spellID then
    return false
  end

  for _, trackedSpellID in ipairs(LOCKOUT_AURA_IDS) do
    if trackedSpellID == spellID then
      return true
    end
  end

  return false
end

local function FindActiveTriggerAura()
  for _, spellID in ipairs(BLOODLUST_AURA_IDS) do
    local aura = GetPlayerAuraBySpellID(spellID)
    if aura then
      local expirationTime = SanitizeAuraNumber(aura.expirationTime)
      local icon = SanitizeAuraAsset(aura.icon or aura.iconFileID)
      local auraSpellID = SanitizeAuraNumber(aura.spellId) or spellID
      return true, expirationTime, {
        spellId = auraSpellID,
        name = SanitizeAuraAsset(aura.name),
        icon = icon,
        iconFileID = icon,
        expirationTime = expirationTime,
      }
    end
  end

  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    local index = 1
    while true do
      local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
      if not aura then
        break
      end

      local spellID = SanitizeAuraNumber(aura.spellId)
      local expirationTime = SanitizeAuraNumber(aura.expirationTime)
      local icon = SanitizeAuraAsset(aura.icon or aura.iconFileID)

      if IsTrackedTriggerAura(spellID, nil) then
        return true, expirationTime, {
          spellId = spellID,
          name = SanitizeAuraAsset(aura.name),
          icon = icon,
          iconFileID = icon,
          expirationTime = expirationTime,
        }
      end

      local normalizedName = NormalizeName(aura.name)
      if IsTrackedTriggerAura(nil, normalizedName) then
        return true, expirationTime, {
          spellId = spellID,
          name = SanitizeAuraAsset(aura.name),
          icon = icon,
          iconFileID = icon,
          expirationTime = expirationTime,
        }
      end

      index = index + 1
    end
  end

  if UnitAura then
    for index = 1, 40 do
      local name, icon, _, _, _, expirationTime, _, _, _, spellID = UnitAura("player", index, "HELPFUL")
      if not name then
        break
      end

      spellID = SanitizeAuraNumber(spellID)
      expirationTime = SanitizeAuraNumber(expirationTime)
      icon = SanitizeAuraAsset(icon)

      if IsTrackedTriggerAura(spellID, nil) then
        return true, expirationTime, {
          spellId = spellID,
          name = name,
          icon = icon,
          iconFileID = icon,
          expirationTime = expirationTime,
        }
      end

      local normalizedName = NormalizeName(name)
      if IsTrackedTriggerAura(nil, normalizedName) then
        return true, expirationTime, {
          spellId = spellID,
          name = name,
          icon = icon,
          iconFileID = icon,
          expirationTime = expirationTime,
        }
      end
    end
  end

  return false, nil, nil
end

GetPlayerAuraBySpellID = function(spellID)
  if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
    return nil
  end

  local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
  if ok then
    return aura
  end

  return nil
end

local function FindActiveLockoutAura()
  for _, spellID in ipairs(LOCKOUT_AURA_IDS) do
    local aura = GetPlayerAuraBySpellID(spellID)
    if aura then
      local expirationTime = SanitizeAuraNumber(aura.expirationTime)
      local duration = SanitizeAuraNumber(aura.duration)
      local icon = SanitizeAuraAsset(aura.icon or aura.iconFileID)
      return true, expirationTime, {
        spellId = spellID,
        name = SanitizeAuraAsset(aura.name),
        icon = icon,
        iconFileID = icon,
        expirationTime = expirationTime,
        duration = duration,
      }, duration
    end
  end

  if UnitAura then
    for index = 1, 40 do
      local name, icon, _, _, duration, expirationTime, _, _, _, spellID = UnitAura("player", index, "HARMFUL")
      if not name then
        break
      end

      spellID = SanitizeAuraNumber(spellID)
      duration = SanitizeAuraNumber(duration)
      expirationTime = SanitizeAuraNumber(expirationTime)
      icon = SanitizeAuraAsset(icon)

      if IsTrackedLockoutAura(spellID) then
        return true, expirationTime, {
          spellId = spellID,
          name = name,
          icon = icon,
          iconFileID = icon,
          expirationTime = expirationTime,
          duration = duration,
        }, duration
      end
    end
  end

  return false, nil, nil, nil
end

local function IsPedroStyle()
  return (db and db.iconStyle or "BL_ICON") == "PEDRO"
end

local function GetCurrentBloodlustIcon()
  local hasAura, _, aura = FindActiveTriggerAura()
  if hasAura and aura then
    local icon = SanitizeAuraAsset(aura.icon or aura.iconFileID)
    local spellID = SanitizeAuraNumber(aura.spellId) or DEFAULT_BL_SPELL_ID
    return icon or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
  end

  if C_Spell and C_Spell.GetSpellTexture then
    return C_Spell.GetSpellTexture(DEFAULT_BL_SPELL_ID)
  end

  return 132313
end

local function ResolveIconTexture()
  local iconStyle = db and db.iconStyle or "BL_ICON"

  if iconStyle == "PEDRO" then
    return BL_ICON_PEDRO
  end

  if iconStyle == "CUSTOM" then
    local customPath = db and db.customIconPath or ""
    if customPath ~= "" then
      return customPath
    end
    return BL_ICON_PEDRO
  end

  return GetCurrentBloodlustIcon()
end

local function ApplyPedroFrame(frameIndex)
  if not frame or not frame.icon then
    return
  end

  local col = frameIndex % PEDRO_ATLAS_COLS
  local row = math.floor(frameIndex / PEDRO_ATLAS_COLS) % PEDRO_ATLAS_ROWS
  local u0 = 0
  local v0 = 0
  local u1 = PEDRO_USED_WIDTH / PEDRO_ATLAS_WIDTH
  local v1 = PEDRO_USED_HEIGHT / PEDRO_ATLAS_HEIGHT
  local cellW = (u1 - u0) / PEDRO_ATLAS_COLS
  local cellH = (v1 - v0) / PEDRO_ATLAS_ROWS
  local left = u0 + (col * cellW)
  local right = left + cellW
  local top = v0 + (row * cellH)
  local bottom = top + cellH
  local insetX = 0.5 / PEDRO_ATLAS_WIDTH
  local insetY = 0.5 / PEDRO_ATLAS_HEIGHT
  left = left + insetX
  right = right - insetX
  top = top + insetY
  bottom = bottom - insetY
  frame.icon:SetTexCoord(left, right, top, bottom)
end

local function UpdateIconTexture()
  if not frame or not frame.icon then
    return
  end

  frame.icon:SetTexture(ResolveIconTexture())

  if (db and db.iconStyle or "BL_ICON") == "PEDRO" then
    ApplyPedroFrame(0)
    return
  end

  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local function SetTimerText(value)
  if not frame or not frame.timerText then
    return
  end

  frame.timerText:SetText(value or "")
end

local function SetStatusText(value, r, g, b)
  if not frame or not frame.statusText then
    return
  end

  if value and value ~= "" then
    frame.statusText:SetText(value)
    frame.statusText:SetTextColor(r or 1, g or 1, b or 1)
    frame.statusText:Show()
  else
    frame.statusText:SetText("")
    frame.statusText:Hide()
  end
end

local function SetStatusLayout(anchorPoint, relativeTo, relativePoint, offsetX, offsetY, fontSize)
  if not frame or not frame.statusText then
    return
  end

  frame.statusText:ClearAllPoints()
  frame.statusText:SetPoint(anchorPoint, relativeTo or frame, relativePoint or anchorPoint, offsetX or 0, offsetY or 0)
  frame.statusText:SetFont("Fonts\\FRIZQT__.TTF", fontSize or 13, "OUTLINE")
end

local function StopTicker()
  if activeTimer then
    activeTimer:Cancel()
    activeTimer = nil
  end
end

local function UpdateFrameVisibility()
  if not frame or not db then
    return
  end

  local shouldShow = editModeEnabled
    or (db.enabled and not db.hideIcon and displayState ~= "HIDDEN")

  if shouldShow then
    frame:Show()
  else
    frame:Hide()
  end
end

local function UpdateEditLabelVisibility(enabled)
  if not frame or not frame.editLabel then
    return
  end

  if enabled then
    frame.editLabel:Show()
  else
    frame.editLabel:Hide()
  end
end

local function UpdateAnchorVisuals(enabled)
  TrackerFrame.UpdateEditModeVisuals(frame, enabled, UpdateEditLabelVisibility)
end

local function CheckActiveBloodlust()
  local hasAura, expirationTime = FindActiveTriggerAura()
  return hasAura, expirationTime
end

local function CheckActiveLockout()
  local hasAura, expirationTime, aura, duration = FindActiveLockoutAura()
  return hasAura, expirationTime, aura, duration
end

local function CheckFreshBloodlust()
  local hasBloodlust, expiration = CheckActiveBloodlust()
  if not hasBloodlust then
    lastSeenExpirationTime = nil
    return false, nil
  end

  if expiration ~= lastSeenExpirationTime then
    lastSeenExpirationTime = expiration
    return true, expiration
  end

  return false, expiration
end

local function RefreshFrameLayout()
  if not frame or not db then return end

  frame:SetSize(db.iconSize, db.iconSize)
  FramePositioning.ApplySavedPosition(frame, db, module.defaults.posX, module.defaults.posY)
end

local function EnsureFrame()
  if frame then
    RefreshFrameLayout()
    UpdateAnchorVisuals(editModeEnabled)
    UpdateFrameVisibility()
    return frame
  end

  if not db then return nil end

  frame = TrackerFrame.CreateContainerShell(
    "SunderingToolsBloodlustFrame",
    "Bloodlust Tracker"
  )
  RefreshFrameLayout()

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetAllPoints()
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.icon:SetTexture(ResolveIconTexture())

  frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  frame.cooldown:SetAllPoints()
  frame.cooldown:SetDrawEdge(false)
  frame.cooldown:SetHideCountdownNumbers(true)

  frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.timerText:SetPoint("CENTER", 0, 0)
  frame.timerText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
  frame.timerText:SetTextColor(1, 1, 0)

  frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.statusText:SetPoint("TOP", frame, "BOTTOM", 0, -4)
  frame.statusText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
  frame.statusText:SetTextColor(0.4, 1, 0.4)
  frame.statusText:Hide()

  frame:SetScript("OnDragStart", function(self)
    if not editModeEnabled then
      return
    end
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    FramePositioning.SaveAbsolutePosition(self, db)
  end)
  if frame.dragHandle then
    frame.dragHandle:SetScript("OnDragStart", function()
      frame:GetScript("OnDragStart")(frame)
    end)
    frame.dragHandle:SetScript("OnDragStop", function()
      frame:GetScript("OnDragStop")(frame)
    end)
  end

  if frame.editLabel then
    frame.editLabel:ClearAllPoints()
    frame.editLabel:SetPoint("TOP", 0, -8)
    frame.editLabel:SetText("Bloodlust Tracker")
  end

  UpdateAnchorVisuals(editModeEnabled)
  UpdateIconTexture()
  UpdateFrameVisibility()
  return frame
end

function module:ResetPosition(moduleDB)
  moduleDB = moduleDB or db or (addon.db and addon.db.modules and addon.db.modules.BloodlustSound)
  if not moduleDB then return end

  FramePositioning.ResetToDefault(frame, moduleDB, module.defaults.posX, module.defaults.posY)
  db = moduleDB
end

local function StopEffect()
  if module.lastHandle then
    StopSound(module.lastHandle)
    module.lastHandle = nil
  end

  StopTicker()
  displayState = "HIDDEN"
  if frame and frame.cooldown then
    frame.cooldown:SetCooldown(0, 0)
  end
  SetTimerText("")
  SetStatusText(nil)
  UpdateFrameVisibility()
end

local function ShouldShowReadyState()
  local inCombat = InCombatLockdown and InCombatLockdown() or false
  local inGroup = (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or false
  return inCombat and inGroup
end

local function ShowReadyState()
  if not db or not db.enabled then
    StopEffect()
    return
  end

  StopTicker()
  displayState = "READY"

  local displayFrame = EnsureFrame()
  if not displayFrame then
    return
  end

  displayFrame.icon:Show()
  displayFrame.cooldown:Show()
  if displayFrame.cooldown then
    displayFrame.cooldown:SetCooldown(0, 0)
  end
  UpdateIconTexture()
  SetTimerText("")
  SetStatusLayout("CENTER", displayFrame, "CENTER", 0, 0, 24)
  SetStatusText("BL READY", 0.2, 1, 0.2)
  UpdateFrameVisibility()
end

local function ShowLockoutState(expirationTime, aura, duration)
  if not db or not db.enabled then
    StopEffect()
    return
  end

  StopTicker()
  displayState = "LOCKOUT"

  local displayFrame = EnsureFrame()
  if not displayFrame then
    return
  end

  displayFrame.icon:Hide()
  displayFrame.cooldown:Hide()
  displayFrame.cooldown:SetCooldown(0, 0)
  SetTimerText("")

  local now = GetTime()
  local lockoutDuration = duration
  if expirationTime and expirationTime > now and (not lockoutDuration or lockoutDuration <= 0) then
    lockoutDuration = expirationTime - now
  end
  if not lockoutDuration or lockoutDuration <= 0 then
    lockoutDuration = DEFAULT_LOCKOUT_DURATION
    expirationTime = now + lockoutDuration
  end

  local auraName = type(aura and aura.name) == "string" and aura.name or "Lockout"
  SetStatusLayout("CENTER", displayFrame, "CENTER", 0, 0, 18)

  local function tick()
    local timeLeft = expirationTime - GetTime()
    if timeLeft <= 0 then
      RefreshAuraState()
      return
    end

    SetStatusText(string.format("%s: %s", auraName, Model.FormatCompactDuration(timeLeft)), 1, 0.85, 0.2)
  end

  tick()
  activeTimer = C_Timer.NewTicker(0.1, tick)
  UpdateFrameVisibility()
end

local function PlayEffect(expirationTime, forcePlay)
  if not db or (not db.enabled and not forcePlay) then return end

  StopEffect()
  displayState = "ACTIVE"

  local channel = Model.NormalizeChannel(db.soundChannel)
  if db.soundFile and db.soundFile ~= "" then
    local _, handle = PlaySoundFile(db.soundFile, channel)
    module.lastHandle = handle
  end

  if db.hideIcon then
    return
  end

  local displayFrame = EnsureFrame()
  if not displayFrame then return end

  displayFrame.icon:Show()
  displayFrame.cooldown:Show()
  UpdateIconTexture()
  SetStatusLayout("TOP", displayFrame, "BOTTOM", 0, -4, 13)
  SetStatusText(nil)
  displayFrame:Show()

  local now = GetTime()
  local auraDuration
  if expirationTime and expirationTime > now then
    auraDuration = expirationTime - now
  end

  local duration = Model.ResolveDuration(auraDuration, db.duration or module.defaults.duration)
  local endTime = now + duration
  local startedAt = now

  displayFrame.cooldown:SetCooldown(now, duration)
  SetTimerText(math.ceil(duration))

  activeTimer = C_Timer.NewTicker(0.1, function()
    local timeLeft = endTime - GetTime()
    if timeLeft <= 0 then
      RefreshAuraState()
    else
      if IsPedroStyle() then
        local elapsed = GetTime() - startedAt
        local frameIndex = math.floor(elapsed * PEDRO_FPS) % PEDRO_FRAME_COUNT
        ApplyPedroFrame(frameIndex)
      end
      SetTimerText(math.ceil(timeLeft))
    end
  end)

  UpdateFrameVisibility()
end

function module:Test(moduleDB)
  if moduleDB then
    db = moduleDB
  end

  PlayEffect(nil, true)
end

function module:Stop()
  StopEffect()
end

function module:SetEditMode(enabled)
  editModeEnabled = enabled and true or false
  if not db then
    db = addon.db and addon.db.modules and addon.db.modules.BloodlustSound
  end

  EnsureFrame()
  UpdateAnchorVisuals(editModeEnabled)
  UpdateFrameVisibility()
end

function module:buildSettings(panel, helpers, addonRef, moduleDB)
  db = moduleDB

  local function GetEditButtonLabel()
    if addonRef.db.global.editMode and (
      addonRef.db.global.activeEditModule == "BloodlustSound"
      or addonRef.db.global.activeEditModule == "ALL"
    ) then
      return "Lock Tracker"
    end

    return "Open Edit Mode"
  end

  local stateLabel = helpers:CreateDividerLabel(panel, "State", nil, 0)
  local stateBody = helpers:CreateSectionHint(panel, "Enable the alert and place the icon if you use it.", 520)
  stateBody:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)

  local enabledBox = helpers:CreateInlineCheckbox(panel, "Enable Bloodlust Tracker", moduleDB.enabled, function(value)
    addonRef:SetModuleValue("BloodlustSound", "enabled", value)
  end)
  enabledBox:SetPoint("TOPLEFT", stateBody, "BOTTOMLEFT", 0, -12)

  local hideIconBox = helpers:CreateInlineCheckbox(panel, "Hide Bloodlust Icon", moduleDB.hideIcon, function(value)
    addonRef:SetModuleValue("BloodlustSound", "hideIcon", value)
  end)
  hideIconBox:SetPoint("TOPLEFT", enabledBox, "BOTTOMLEFT", 0, -8)

  local editButton = helpers:CreateActionButton(panel, GetEditButtonLabel(), function(self)
    local isActive = addonRef.db.global.editMode and (
      addonRef.db.global.activeEditModule == "BloodlustSound"
      or addonRef.db.global.activeEditModule == "ALL"
    )
    addonRef:SetEditMode(not isActive, isActive and nil or "BloodlustSound")
    self:SetText(GetEditButtonLabel())
    addonRef:RefreshSettings()
  end)

  local resetButton = helpers:CreateActionButton(panel, "Reset Position", function()
    module:ResetPosition(moduleDB)
  end)
  helpers:PlaceRow(hideIconBox, editButton, resetButton, -12, 12)

  local stateHint = helpers:CreateSectionHint(panel, "Hide the icon if you only want the sound cue. Edit mode lets you move it safely.", 460)
  stateHint:SetPoint("TOPLEFT", editButton, "BOTTOMLEFT", 0, -10)

  local behaviorLabel = helpers:CreateDividerLabel(panel, "Behavior", stateHint, -22)
  local behaviorBody = helpers:CreateSectionHint(panel, "Choose the sound file and output channel.", 520)
  behaviorBody:SetPoint("TOPLEFT", behaviorLabel, "BOTTOMLEFT", 0, -8)

  local soundFileInput = helpers:CreateLabeledEditBox(panel, "Sound File", helpers.WideControlWidth, moduleDB.soundFile or "", function(value)
    addonRef:SetModuleValue("BloodlustSound", "soundFile", value)
  end)
  soundFileInput:SetPoint("TOPLEFT", behaviorBody, "BOTTOMLEFT", 0, -12)

  local channelDropdown = helpers:CreateLabeledDropdown(
    panel,
    "Sound Channel",
    Model.ChannelOptions(),
    Model.NormalizeChannel(moduleDB.soundChannel),
    180,
    function(value)
      addonRef:SetModuleValue("BloodlustSound", "soundChannel", value)
    end
  )
  local testButton = helpers:CreateActionButton(panel, "Test Sound", function()
    module:Test(moduleDB)
  end)
  helpers:PlaceRow(soundFileInput, channelDropdown, testButton, -8, helpers.ColumnGap)

  local stopButton = helpers:CreateActionButton(panel, "Stop Sound", function()
    module:Stop()
  end)
  stopButton:SetPoint("TOPLEFT", testButton, "TOPRIGHT", 12, 0)

  local durationSlider = helpers:CreateLabeledSlider(panel, "Duration", 5, 60, 1, moduleDB.duration or module.defaults.duration, function(value)
    addonRef:SetModuleValue("BloodlustSound", "duration", value)
  end, 220)
  durationSlider:SetPoint("TOPLEFT", channelDropdown, "BOTTOMLEFT", 0, -10)

  local layoutLabel = helpers:CreateDividerLabel(panel, "Layout", durationSlider, -22)
  local layoutBody = helpers:CreateSectionHint(panel, "Adjust icon size and placement.", 520)
  layoutBody:SetPoint("TOPLEFT", layoutLabel, "BOTTOMLEFT", 0, -8)

  local iconStyleDropdown = helpers:CreateLabeledDropdown(
    panel,
    "BL Icon Style",
    {
      { label = "BL Icon", value = "BL_ICON" },
      { label = "Pedro", value = "PEDRO" },
      { label = "Custom", value = "CUSTOM" },
    },
    moduleDB.iconStyle,
    176,
    function(value)
      addonRef:SetModuleValue("BloodlustSound", "iconStyle", value)
      addonRef:RefreshSettings()
    end
  )
  local iconSizeSlider = helpers:CreateLabeledSlider(panel, "Icon Size", 32, 128, 1, moduleDB.iconSize, function(value)
    addonRef:SetModuleValue("BloodlustSound", "iconSize", value)
  end, 220)
  helpers:PlaceRow(layoutBody, iconStyleDropdown, iconSizeSlider, -12, helpers.ColumnGap)

  local customIconInput
  if moduleDB.iconStyle == "CUSTOM" then
    customIconInput = helpers:CreateLabeledEditBox(panel, "Custom Icon Path", helpers.WideControlWidth, moduleDB.customIconPath or "", function(value)
      addonRef:SetModuleValue("BloodlustSound", "customIconPath", value)
    end)
    customIconInput:SetPoint("TOPLEFT", iconStyleDropdown, "BOTTOMLEFT", 0, -8)
  end

  local helpAnchor = customIconInput or iconSizeSlider
  local helpText = helpers:CreateSectionHint(panel, "Use edit mode to move the icon in-game.", 420)
  helpText:SetPoint("TOPLEFT", helpAnchor, "BOTTOMLEFT", 0, -12)
end

function module:onConfigChanged(_, moduleDB, key)
  db = moduleDB

  if key == "enabled" then
    if moduleDB.enabled then
      EnsureFrame()
      RefreshAuraState()
    else
      StopEffect()
    end
    UpdateFrameVisibility()
    return
  end

  if key == "hideIcon" then
    EnsureFrame()
    RefreshAuraState()
    return
  end

  if key == "iconSize" or key == "posX" or key == "posY" then
    EnsureFrame()
    UpdateFrameVisibility()
    return
  end

  if key == "iconStyle" or key == "customIconPath" then
    EnsureFrame()
    RefreshAuraState()
  end
end

RefreshAuraState = function()
  if not db or not db.enabled then
    StopEffect()
    return
  end

  local hasBloodlust, expiration = CheckActiveBloodlust()
  if hasBloodlust then
    if expiration then
      lastSeenExpirationTime = expiration
    end
    if displayState ~= "ACTIVE" then
      PlayEffect(expiration, true)
    end
    return
  end

  local hasLockout, lockoutExpiration, aura, duration = CheckActiveLockout()
  if hasLockout then
    ShowLockoutState(lockoutExpiration, aura, duration)
    return
  end

  if ShouldShowReadyState() then
    ShowReadyState()
  else
    StopEffect()
  end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    db = addon.db.BloodlustSound
    if db and db.enabled then
      EnsureFrame()
      local hasBloodlust, expiration = CheckActiveBloodlust()
      if hasBloodlust then
        addon:DebugLog("bloodlust", "resume active effect", expiration)
      end
      RefreshAuraState()
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    if not db then
      db = addon.db and addon.db.BloodlustSound
    end
    if db and db.enabled then
      EnsureFrame()
      RefreshAuraState()
    end
    return
  end

  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    RefreshAuraState()
    return
  end

  if event == "UNIT_AURA" then
    local unitTarget = ...
    if unitTarget == "player" then
      local hasFreshBloodlust, expiration = CheckFreshBloodlust()
      if hasFreshBloodlust then
        addon:DebugLog("bloodlust", "fresh bloodlust detected", expiration)
        PlayEffect(expiration)
        return
      end

      RefreshAuraState()
    end
  end
end)

SLASH_SUNDERINGTOOLS_TEST1 = "/su test"
SlashCmdList["SUNDERINGTOOLS_TEST"] = function()
  if addon.db.BloodlustSound.enabled then
    module:Test(addon.db.BloodlustSound)
    print("|cff00ff00SunderingTools:|r Bloodlust test triggered!")
  else
    print("|cff00ff00SunderingTools:|r Bloodlust sound is disabled.")
  end
end

module.Play = PlayEffect
addon.BloodlustSound = module
addon:RegisterModule(module)
