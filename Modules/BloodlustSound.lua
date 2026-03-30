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
  label = "Bloodlust Sound",
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

local ExhaustionIDs = {
  57723,  -- Exhaustion
  57724,  -- Sated
  80354,  -- Temporal Displacement
  95809,  -- Insanity
  160455, -- Fatigued
  207400, -- Temporal Displacement (different)
  264689, -- Fatigued
  390435, -- Exhaustion (Evoker)
}
local ExhaustionDuration = 600
local ExhaustionFreshWindow = 5
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
  390386, -- Fury of the Aspects
}

local frame
local activeTimer
local lastSeenExpirationTime
local editModeEnabled = false

local function IsPedroStyle()
  return (db and db.iconStyle or "BL_ICON") == "PEDRO"
end

local function GetCurrentBloodlustIcon()
  for _, spellID in ipairs(BLOODLUST_AURA_IDS) do
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if aura then
      return aura.icon or aura.iconFileID or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
    end
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

local function UpdateFrameVisibility()
  if not frame or not db then
    return
  end

  local shouldShow = editModeEnabled
    or (db.enabled and not db.hideIcon and activeTimer ~= nil)

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

local function CheckExhaustion()
  for _, spellID in ipairs(ExhaustionIDs) do
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if aura then
      return true, aura.expirationTime
    end
  end

  return false, nil
end

local function CheckFreshExhaustion()
  for _, spellID in ipairs(ExhaustionIDs) do
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if aura then
      local remaining = aura.expirationTime - GetTime()
      if remaining >= (ExhaustionDuration - ExhaustionFreshWindow) then
        if aura.expirationTime ~= lastSeenExpirationTime then
          lastSeenExpirationTime = aura.expirationTime
          return true, aura.expirationTime
        end
        return false, aura.expirationTime
      end

      lastSeenExpirationTime = aura.expirationTime
      return false, aura.expirationTime
    end
  end

  lastSeenExpirationTime = nil
  return false, nil
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
    "Bloodlust Sound"
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
    frame.editLabel:SetText("Bloodlust Sound")
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

  if activeTimer then
    activeTimer:Cancel()
    activeTimer = nil
  end

  UpdateFrameVisibility()
end

local function PlayEffect(expirationTime, forcePlay)
  if not db or (not db.enabled and not forcePlay) then return end

  StopEffect()

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

  UpdateIconTexture()
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
  displayFrame.timerText:SetText(math.ceil(duration))

  activeTimer = C_Timer.NewTicker(0.1, function()
    local timeLeft = endTime - GetTime()
    if timeLeft <= 0 then
      StopEffect()
    else
      if IsPedroStyle() then
        local elapsed = GetTime() - startedAt
        local frameIndex = math.floor(elapsed * PEDRO_FPS) % PEDRO_FRAME_COUNT
        ApplyPedroFrame(frameIndex)
      end
      displayFrame.timerText:SetText(math.ceil(timeLeft))
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

  local enabledBox = helpers:CreateInlineCheckbox(panel, "Enable Bloodlust Sound", moduleDB.enabled, function(value)
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

  local layoutLabel = helpers:CreateDividerLabel(panel, "Layout", channelDropdown, -22)
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
    else
      StopEffect()
    end
    UpdateFrameVisibility()
    return
  end

  if key == "hideIcon" then
    EnsureFrame()
    UpdateIconTexture()
    UpdateFrameVisibility()
    return
  end

  if key == "iconSize" or key == "posX" or key == "posY" then
    EnsureFrame()
    UpdateFrameVisibility()
    return
  end

  if key == "iconStyle" or key == "customIconPath" then
    EnsureFrame()
    UpdateIconTexture()
    UpdateFrameVisibility()
  end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    db = addon.db.BloodlustSound
    if db and db.enabled then
      EnsureFrame()
      local hasExhaustion, expiration = CheckExhaustion()
      if hasExhaustion then
        lastSeenExpirationTime = expiration
        addon:DebugLog("bloodlust", "resume active effect", expiration)
        PlayEffect(expiration)
      else
        UpdateFrameVisibility()
      end
    end
    return
  end

  if event == "UNIT_AURA" then
    local unitTarget = ...
    if unitTarget == "player" then
      local hasFreshExhaustion, expiration = CheckFreshExhaustion()
      if hasFreshExhaustion then
        addon:DebugLog("bloodlust", "fresh exhaustion detected", expiration)
        PlayEffect(expiration)
      end
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
