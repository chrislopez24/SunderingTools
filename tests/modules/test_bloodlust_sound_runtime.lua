local function buildModuleDefaults(overrides)
  local defaults = {
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
  }

  for key, value in pairs(overrides or {}) do
    defaults[key] = value
  end

  return defaults
end

local function loadModule(moduleDB)
  moduleDB = buildModuleDefaults(moduleDB)

  _G.SunderingTools = nil
  _G.SunderingToolsBloodlustSoundModel = nil
  _G.SunderingToolsFramePositioning = nil
  _G.SunderingToolsTrackerFrame = nil

  local createdFrames = {}
  local state = {
    now = 100,
    inCombat = false,
    inGroup = false,
    auras = {},
    helpfulAuras = {},
    spellNames = {},
    soundCalls = {},
    stoppedSounds = {},
    shell = nil,
    ticker = nil,
    secretName = "__SECRET_AURA_NAME__",
    secretSpellID = {},
  }

  local function newUiObject(parent)
    local object = {
      parent = parent,
      shown = true,
      points = {},
      size = { 0, 0 },
    }

    function object:SetPoint(...)
      self.points[#self.points + 1] = { ... }
    end

    function object:ClearAllPoints()
      self.points = {}
    end

    function object:SetSize(width, height)
      self.size = { width, height }
    end

    function object:SetAllPoints(target)
      self.allPoints = target or true
    end

    function object:SetTexture(texture)
      self.texture = texture
    end

    function object:SetTexCoord(...)
      self.texCoord = { ... }
    end

    function object:SetFont(...)
      self.font = { ... }
    end

    function object:SetTextColor(...)
      self.textColor = { ... }
    end

    function object:SetText(text)
      self.text = text
    end

    function object:SetDrawEdge(value)
      self.drawEdge = value
    end

    function object:SetHideCountdownNumbers(value)
      self.hideCountdownNumbers = value
    end

    function object:SetCooldown(startTime, duration)
      self.cooldownStart = startTime
      self.cooldownDuration = duration
    end

    function object:Show()
      self.shown = true
    end

    function object:Hide()
      self.shown = false
    end

    return object
  end

  local function newFrame(frameType, parent)
    local frame = newUiObject(parent)
    frame.frameType = frameType
    frame.events = {}
    frame.scripts = {}
    frame.children = {}

    function frame:RegisterEvent(event)
      self.events[#self.events + 1] = event
    end

    function frame:SetScript(name, callback)
      self.scripts[name] = callback
    end

    function frame:CreateTexture(_, layer)
      local texture = newUiObject(self)
      texture.layer = layer
      self.children[#self.children + 1] = texture
      return texture
    end

    function frame:CreateFontString(_, layer)
      local fontString = newUiObject(self)
      fontString.layer = layer
      self.children[#self.children + 1] = fontString
      return fontString
    end

    function frame:StartMoving()
      self.moving = true
    end

    function frame:StopMovingOrSizing()
      self.moving = false
    end

    return frame
  end

  local addon = {
    db = {
      global = {
        editMode = false,
        activeEditModule = nil,
      },
      modules = {
        BloodlustSound = moduleDB,
      },
      BloodlustSound = moduleDB,
    },
    modules = {},
    RegisterModule = function(self, module)
      self.modules[module.key] = module
    end,
    DebugLog = function() end,
  }

  _G.SunderingTools = addon
  dofile("Modules/BloodlustSoundModel.lua")

  _G.SunderingToolsFramePositioning = {
    ApplySavedPosition = function() end,
    SaveAbsolutePosition = function() end,
    ResetToDefault = function() end,
  }
  _G.SunderingToolsTrackerFrame = {
    CreateContainerShell = function()
      local shell = newFrame("Frame", nil)
      shell.dragHandle = newFrame("Frame", shell)
      shell.editLabel = shell:CreateFontString(nil, "OVERLAY")
      state.shell = shell
      return shell
    end,
    UpdateEditModeVisuals = function(_, _, callback)
      if callback then
        callback(false)
      end
    end,
  }
  _G.C_UnitAuras = {
    GetPlayerAuraBySpellID = function(spellID)
      return state.auras[spellID]
    end,
    GetAuraDataByIndex = function(unit, index, filter)
      if unit ~= "player" or filter ~= "HELPFUL" then
        return nil
      end

      return state.helpfulAuras[index]
    end,
  }
  _G.C_Spell = {
    GetSpellTexture = function(spellID)
      if spellID == state.secretSpellID then
        error("attempt to use a secret spell id", 0)
      end
      return "texture:" .. tostring(spellID)
    end,
    GetSpellName = function(spellID)
      return state.spellNames[spellID]
    end,
  }
  _G.GetSpellInfo = function(spellID)
    if state.spellNames[spellID] then
      return state.spellNames[spellID]
    end

    local aura = state.auras[spellID]
    if aura and aura.name then
      return aura.name
    end

    for _, helpfulAura in ipairs(state.helpfulAuras) do
      if helpfulAura and helpfulAura.spellId == spellID then
        return helpfulAura.name
      end
    end

    return "spell:" .. tostring(spellID)
  end
  _G.C_Timer = {
    NewTicker = function(_, callback)
      local ticker = {
        cancelled = false,
        callback = callback,
        Cancel = function(self)
          self.cancelled = true
        end,
      }
      state.ticker = ticker
      return ticker
    end,
  }
  _G.CreateFrame = function(frameType, _, parent)
    local frame = newFrame(frameType, parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
  end
  _G.GetTime = function()
    return state.now
  end
  _G.InCombatLockdown = function()
    return state.inCombat
  end
  _G.IsInGroup = function()
    return state.inGroup
  end
  _G.IsInRaid = function()
    return false
  end
  _G.PlaySoundFile = function(path, channel)
    state.soundCalls[#state.soundCalls + 1] = {
      path = path,
      channel = channel,
    }
    return true, #state.soundCalls
  end
  _G.StopSound = function(handle)
    state.stoppedSounds[#state.stoppedSounds + 1] = handle
  end
  _G.SlashCmdList = {}
  _G.issecretvalue = function(value)
    return value == state.secretName or value == state.secretSpellID
  end

  local originalLower = string.lower
  string.lower = function(value)
    if value == state.secretName then
      error("attempt to perform string conversion on a secret string value", 0)
    end

    return originalLower(value)
  end

  dofile("Modules/BloodlustSound.lua")

  local eventFrame = createdFrames[#createdFrames]
  state.onEvent = eventFrame.scripts.OnEvent
  state.module = addon.modules.BloodlustSound
  state.advance = function(seconds)
    state.now = state.now + seconds
    if state.ticker and not state.ticker.cancelled and state.ticker.callback then
      state.ticker.callback()
    end
  end

  return state
end

do
  local state = loadModule()
  state.onEvent(nil, "PLAYER_LOGIN")

  assert(state.shell ~= nil, "bloodlust frame should initialize on login when enabled")
  assert(state.shell.shown == false, "ready state should stay hidden outside combat when no lockout is active")
  assert(state.shell.statusText == nil or state.shell.statusText.shown == false, "ready state label should stay hidden outside combat")
  assert(#state.soundCalls == 0, "ready state should not play the bloodlust sound")

  state.inCombat = true
  state.inGroup = false
  state.onEvent(nil, "PLAYER_REGEN_DISABLED")
  assert(state.shell.shown == false, "ready state should stay hidden in combat when not grouped")

  state.inGroup = true
  state.onEvent(nil, "PLAYER_REGEN_DISABLED")

  assert(state.shell.shown == true, "ready state should show the bloodlust frame after entering combat")
  assert(state.shell.statusText and state.shell.statusText.text == "BL READY", "ready state should show the larger BL READY label in grouped combat")
  assert(state.shell.statusText.font and state.shell.statusText.font[2] == 24, "ready state should use a larger status label size")
  assert(state.shell.timerText.text == "", "ready state should not show an active countdown")

  state.inCombat = false
  state.onEvent(nil, "PLAYER_REGEN_ENABLED")
  assert(state.shell.shown == false, "ready state should hide again when leaving combat")
end

do
  local state = loadModule()
  state.auras[57724] = {
    spellId = 57724,
    name = "Sated",
    expirationTime = 700,
    duration = 600,
    icon = "sated",
  }

  state.onEvent(nil, "PLAYER_LOGIN")

  assert(state.shell.shown == true, "lockout state should keep the tracker visible")
  assert(state.shell.statusText and state.shell.statusText.text == "LOCKOUT", "lockout state should label the tracker")
  assert(state.shell.cooldown.cooldownDuration == 600, "lockout state should use the live debuff duration")
  assert(state.shell.timerText.text == 600, "lockout state should show the remaining debuff time")
  assert(#state.soundCalls == 0, "lockout state should not play the bloodlust sound")

  state.auras[57724] = nil
  state.onEvent(nil, "UNIT_AURA", "player")

  assert(state.shell.shown == false, "clearing the lockout outside combat should keep the tracker hidden")
end

do
  local state = loadModule()
  state.helpfulAuras[1] = {
    spellId = 80353,
    name = "Time Warp",
    expirationTime = 130,
    icon = "timewarp",
  }

  state.onEvent(nil, "PLAYER_LOGIN")

  assert(#state.soundCalls == 1, "an active bloodlust buff should play the effect when resuming on login")
  assert(state.shell.shown == true, "an active bloodlust buff should show the frame")
  assert(state.shell.cooldown.cooldownStart == 100, "the cooldown swipe should start at the current time")
  assert(state.shell.cooldown.cooldownDuration == 30, "the cooldown swipe should use the active aura duration instead of the fallback duration")
  assert(state.shell.timerText.text == 30, "the timer should reflect the active buff duration")
  assert(state.shell.statusText == nil or state.shell.statusText.shown == false, "active bloodlust should hide the ready/lockout label")

  state.helpfulAuras[1] = nil
  state.onEvent(nil, "UNIT_AURA", "player")

  assert(state.shell.shown == false, "removing the bloodlust buff outside combat should hide the ready state")
end

do
  local state = loadModule()
  state.helpfulAuras[1] = {
    spellId = 999999,
    name = "Drums of Fury",
    expirationTime = 118,
    icon = "drums",
  }

  state.onEvent(nil, "PLAYER_LOGIN")

  assert(#state.soundCalls == 1, "known bloodlust fallback names should trigger even when the spell ID is not in the fixed player-aura lookup")
  assert(state.shell.shown == true, "known bloodlust fallback names should still show the frame")
  assert(state.shell.cooldown.cooldownDuration == 18, "fallback-name detection should still use the live aura expiration time")
  assert(state.shell.statusText == nil or state.shell.statusText.shown == false, "fallback-name bloodlust should still use the active-effect view")
end

do
  local state = loadModule()
  state.auras[57724] = {
    spellId = 57724,
    name = "Sated",
    expirationTime = 700,
    duration = 600,
    icon = "sated",
  }
  state.helpfulAuras[1] = {
    spellId = 80353,
    name = "Time Warp",
    expirationTime = 140,
    icon = "timewarp",
  }

  state.onEvent(nil, "PLAYER_LOGIN")

  assert(#state.soundCalls == 1, "an active bloodlust buff should take priority over the lockout display")
  assert(state.shell.cooldown.cooldownDuration == 40, "active bloodlust should continue to drive the countdown while lockout is also present")
  assert(state.shell.statusText == nil or state.shell.statusText.shown == false, "active bloodlust should hide the lockout label while the buff is up")
end

do
  local state = loadModule()
  state.helpfulAuras[1] = {
    spellId = 80353,
    name = state.secretName,
    expirationTime = 140,
    icon = "timewarp",
  }

  state.onEvent(nil, "PLAYER_LOGIN")

  assert(#state.soundCalls == 1, "tracked bloodlust spell IDs should not require normalizing a secret aura name")
  assert(state.shell.shown == true, "tracked bloodlust spell IDs should still show the frame when the aura name is secret")
  assert(state.shell.cooldown.cooldownDuration == 40, "tracked bloodlust spell IDs should still use the active aura expiration time")
end

do
  local state = loadModule()
  state.helpfulAuras[1] = {
    spellId = state.secretSpellID,
    name = "Time Warp",
    expirationTime = 140,
    icon = nil,
    iconFileID = nil,
  }

  state.onEvent(nil, "PLAYER_LOGIN")

  assert(#state.soundCalls == 1, "known bloodlust names should still trigger when the spell id is secret")
  assert(state.shell.shown == true, "a secret spell id should not prevent the active bloodlust frame from showing")
  assert(state.shell.icon and state.shell.icon.texture == "texture:2825", "a secret spell id should fall back to the default bloodlust texture")
  assert(state.shell.cooldown.cooldownDuration == 40, "a secret spell id should still preserve the live aura expiration time")
end

do
  local state = loadModule()
  state.spellNames[2825] = "Ansia de sangre"
  state.spellNames[80353] = "Distorsion temporal"
  state.helpfulAuras[1] = {
    spellId = state.secretSpellID,
    name = "Distorsion temporal",
    expirationTime = 140,
    icon = "timewarp",
  }

  state.onEvent(nil, "PLAYER_LOGIN")

  assert(#state.soundCalls == 1, "localized bloodlust names should trigger even when the active aura spell id is secret")
  assert(state.shell.shown == true, "localized bloodlust names should still show the active tracker state")
  assert(state.shell.cooldown.cooldownDuration == 40, "localized bloodlust names should preserve the live aura expiration time")
  assert(state.shell.statusText == nil or state.shell.statusText.shown == false, "localized bloodlust names should not fall through to lockout state")
end

do
  local state = loadModule()
  state.helpfulAuras[1] = {
    spellId = 80353,
    name = "Time Warp",
    expirationTime = 140,
    icon = "timewarp",
  }

  state.onEvent(nil, "PLAYER_LOGIN")
  assert(#state.soundCalls == 1, "active bloodlust should start exactly one sound playback before stop verification")

  state.module:Stop()

  assert(#state.stoppedSounds == 1, "Stop Sound should stop the current playback handle")
  assert(#state.soundCalls == 1, "Stop Sound should not immediately restart the active bloodlust sound")
  assert(state.shell.shown == false, "Stop Sound should hide the tracker until a new aura event reactivates it")
end
