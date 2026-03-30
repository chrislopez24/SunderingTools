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
    auras = {},
    helpfulAuras = {},
    soundCalls = {},
    stoppedSounds = {},
    shell = nil,
    ticker = nil,
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
      return "texture:" .. tostring(spellID)
    end,
  }
  _G.GetSpellInfo = function(spellID)
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
  state.auras[57724] = {
    expirationTime = 700,
    icon = "sated",
  }

  state.onEvent(nil, "PLAYER_LOGIN")

  assert(state.shell ~= nil, "bloodlust frame should initialize on login when enabled")
  assert(state.shell.shown == false, "exhaustion alone should not show the bloodlust frame")
  assert(#state.soundCalls == 0, "exhaustion alone should not play the bloodlust sound")
end

do
  local state = loadModule()
  state.onEvent(nil, "PLAYER_LOGIN")

  state.auras[57724] = {
    expirationTime = 700,
    icon = "sated",
  }
  state.onEvent(nil, "UNIT_AURA", "player")

  assert(state.shell.shown == false, "unit aura updates with exhaustion only should not show the bloodlust frame")
  assert(#state.soundCalls == 0, "unit aura updates with exhaustion only should not play the bloodlust sound")
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

  state.helpfulAuras[1] = nil
  state.onEvent(nil, "UNIT_AURA", "player")

  assert(state.shell.shown == false, "removing the bloodlust buff should hide the frame immediately")
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
end
