-- BloodlustSound
-- Play sound and show icon when bloodlust/heroism is cast

local addon = _G.SunderingTools
if not addon then return end

local Model = dofile("Modules/BloodlustSoundModel.lua")

local module = {
  key = "BloodlustSound",
  label = "Bloodlust Sound",
  order = 20,
  defaults = {
    enabled = true,
    hideIcon = false,
    iconSize = 64,
    posX = 0,
    posY = 100,
    soundFile = "Interface\\AddOns\\SunderingTools\\sounds\\pedrolust.mp3",
    soundChannel = "Master",
    duration = 40,
  },
}

local db = addon.db and addon.db.BloodlustSound

local BloodlustSpells = {
  2825,   -- Bloodlust (Shaman)
  32182,  -- Heroism (Shaman)
  80353,  -- Time Warp (Mage)
  90355,  -- Ancient Hysteria (Hunter - Core Hound)
  160452, -- Netherwinds (Hunter - Nether Ray)
  264667, -- Primal Rage (Hunter - Ferocity)
  390386, -- Fury of the Aspects (Evoker)
}

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

local frame
local activeTimer

local function CheckExhaustion()
  for _, spellID in ipairs(ExhaustionIDs) do
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if aura then
      local remaining = aura.expirationTime - GetTime()
      if remaining >= 595 then
        return true, aura.expirationTime
      end
    end
  end

  return false, nil
end

local function RefreshFrameLayout()
  if not frame or not db then return end

  frame:SetSize(db.iconSize, db.iconSize)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
end

local function EnsureFrame()
  if frame then
    RefreshFrameLayout()
    return frame
  end

  if not db then return nil end

  frame = CreateFrame("Frame", "SunderingToolsBloodlustFrame", UIParent)
  RefreshFrameLayout()

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(0, 0, 0, 0.5)

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetAllPoints()
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.icon:SetTexture(132313)

  frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  frame.cooldown:SetAllPoints()
  frame.cooldown:SetDrawEdge(false)
  frame.cooldown:SetHideCountdownNumbers(true)

  frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.timerText:SetPoint("CENTER", 0, 0)
  frame.timerText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
  frame.timerText:SetTextColor(1, 1, 0)

  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    db.posX = x
    db.posY = y
  end)

  frame:Hide()
  return frame
end

function module:ResetPosition(moduleDB)
  moduleDB = moduleDB or db or (addon.db and addon.db.modules and addon.db.modules.BloodlustSound)
  if not moduleDB then return end

  moduleDB.posX = module.defaults.posX
  moduleDB.posY = module.defaults.posY
  db = moduleDB

  if frame then
    RefreshFrameLayout()
  end
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

  if frame then
    frame:Hide()
  end
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

  displayFrame:Show()

  local now = GetTime()
  local auraDuration
  if expirationTime and expirationTime > now then
    auraDuration = expirationTime - now
  end

  local duration = Model.ResolveDuration(auraDuration, db.duration or module.defaults.duration)
  local endTime = now + duration

  displayFrame.cooldown:SetCooldown(now, duration)
  displayFrame.timerText:SetText(math.ceil(duration))

  activeTimer = C_Timer.NewTicker(0.1, function()
    local timeLeft = endTime - GetTime()
    if timeLeft <= 0 then
      StopEffect()
    else
      displayFrame.timerText:SetText(math.ceil(timeLeft))
    end
  end)
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

function module:buildSettings(panel, helpers, addonRef, moduleDB)
  db = moduleDB

  local enabledBox = helpers:CreateCheckbox(panel, "Enable Bloodlust Sound", moduleDB.enabled, function(value)
    addonRef:SetModuleValue("BloodlustSound", "enabled", value)
  end)
  enabledBox:SetPoint("TOPLEFT", 0, 0)

  local hideIconBox = helpers:CreateCheckbox(panel, "Hide Bloodlust Icon", moduleDB.hideIcon, function(value)
    addonRef:SetModuleValue("BloodlustSound", "hideIcon", value)
  end)
  hideIconBox:SetPoint("TOPLEFT", enabledBox, "BOTTOMLEFT", 0, -8)

  local iconSizeSlider = helpers:CreateSlider(panel, "Icon Size", 32, 128, 1, moduleDB.iconSize, function(value)
    addonRef:SetModuleValue("BloodlustSound", "iconSize", value)
  end)
  iconSizeSlider:SetPoint("TOPLEFT", hideIconBox, "BOTTOMLEFT", 4, -16)

  local soundFileInput = helpers:CreateEditBox(panel, "Sound File", 300, moduleDB.soundFile or "", function(value)
    addonRef:SetModuleValue("BloodlustSound", "soundFile", value)
  end)
  soundFileInput:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", -4, -12)

  local channelDropdown = helpers:CreateDropdown(
    panel,
    "Sound Channel",
    Model.ChannelOptions(),
    Model.NormalizeChannel(moduleDB.soundChannel),
    180,
    function(value)
      addonRef:SetModuleValue("BloodlustSound", "soundChannel", value)
    end
  )
  channelDropdown:SetPoint("TOPLEFT", soundFileInput, "BOTTOMLEFT", 0, -8)

  local testButton = helpers:CreateButton(panel, "Test Sound", function()
    module:Test(moduleDB)
  end)
  testButton:SetPoint("TOPLEFT", channelDropdown, "BOTTOMLEFT", 4, -16)

  local stopButton = helpers:CreateButton(panel, "Stop Sound", function()
    module:Stop()
  end)
  stopButton:SetPoint("TOPLEFT", testButton, "TOPRIGHT", 12, 0)

  local resetButton = helpers:CreateButton(panel, "Reset Position", function()
    module:ResetPosition(moduleDB)
  end)
  resetButton:SetPoint("TOPLEFT", testButton, "BOTTOMLEFT", 0, -8)

  local helpText = helpers:CreateText(
    panel,
    "Use the icon in-game to drag it after enabling the module.",
    "GameFontHighlight",
    320
  )
  helpText:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", -4, -12)
end

function module:onConfigChanged(_, moduleDB, key)
  db = moduleDB

  if key == "enabled" then
    if moduleDB.enabled then
      EnsureFrame()
    else
      StopEffect()
    end
    return
  end

  if key == "hideIcon" then
    if moduleDB.hideIcon and frame then
      frame:Hide()
    elseif not moduleDB.hideIcon then
      EnsureFrame()
    end
    return
  end

  if key == "iconSize" or key == "posX" or key == "posY" then
    EnsureFrame()
  end
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    db = addon.db.BloodlustSound
    if db and db.enabled then
      EnsureFrame()
    end
    return
  end

  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, _, spellID = ...
    for _, id in ipairs(BloodlustSpells) do
      if spellID == id then
        C_Timer.After(0.5, function()
          local hasExhaustion, expiration = CheckExhaustion()
          if hasExhaustion then
            PlayEffect(expiration)
          end
        end)
        break
      end
    end
    return
  end

  if event == "UNIT_AURA" then
    local unitTarget = ...
    if unitTarget == "player" then
      local hasExhaustion, expiration = CheckExhaustion()
      if hasExhaustion and (not activeTimer or not frame or not frame:IsShown()) then
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
