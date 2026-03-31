local Sync = dofile("Core/CombatTrackSync.lua")

local function buildModuleDefaults(overrides)
  local defaults = {
    enabled = true,
    previewWhenSolo = true,
    maxBars = 4,
    growDirection = "DOWN",
    spacing = 0,
    iconSize = 18,
    barWidth = 190,
    barHeight = 18,
    fontSize = 11,
    showHeader = true,
    showInDungeon = true,
    showInWorld = true,
    hideOutOfCombat = false,
    showReady = true,
    tooltipOnHover = true,
    readySoundEnabled = false,
    readySoundPath = "Interface\\AddOns\\SunderingTools\\sounds\\ready.mp3",
    readySoundChannel = "Master",
  }

  for key, value in pairs(overrides or {}) do
    defaults[key] = value
  end

  return defaults
end

local function loadTracker(moduleDB, roster)
  roster = roster or {}
  moduleDB = buildModuleDefaults(moduleDB)

  _G.SunderingTools = nil
  _G.SunderingToolsCombatTrackSpellDB = nil
  _G.SunderingToolsCooldownViewerMeta = nil
  _G.SunderingToolsCombatTrackSync = nil
  _G.SunderingToolsCombatTrackEngine = nil
  _G.SunderingToolsInterruptTrackerModel = nil
  _G.SunderingToolsFramePositioning = nil
  _G.SunderingToolsTrackerFrame = nil
  _G.SunderingToolsTrackerSettings = nil

  local createdFrames = {}
  local sentMessages = {}
  local delayedCallbacks = {}
  local activeTickers = {}
  local now = 100

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

    function object:SetWidth(width)
      self.size[1] = width
    end

    function object:SetHeight(height)
      self.size[2] = height
    end

    function object:Show()
      self.shown = true
    end

    function object:Hide()
      self.shown = false
    end

    function object:IsShown()
      return self.shown
    end

    function object:SetShown(shown)
      self.shown = shown and true or false
    end

    function object:SetAlpha(alpha)
      self.alpha = alpha
    end

    function object:SetText(text)
      self.text = text
    end

    function object:SetTextColor(...)
      self.textColor = { ... }
    end

    function object:SetFont(...)
      self.font = { ... }
    end

    function object:SetShadowOffset(...)
      self.shadowOffset = { ... }
    end

    function object:SetShadowColor(...)
      self.shadowColor = { ... }
    end

    function object:SetJustifyH(value)
      self.justifyH = value
    end

    function object:SetJustifyV(value)
      self.justifyV = value
    end

    function object:SetAllPoints(target)
      self.allPoints = target or true
    end

    function object:SetTexture(texture)
      self.texture = texture
    end

    function object:SetColorTexture(...)
      self.color = { ... }
    end

    function object:SetTexCoord(...)
      self.texCoord = { ... }
    end

    function object:SetVertexColor(...)
      self.vertexColor = { ... }
    end

    function object:SetStatusBarColor(...)
      self.statusBarColor = { ... }
    end

    function object:SetStatusBarTexture(texture)
      self.statusBarTexture = texture
    end

    function object:GetStatusBarTexture()
      return self.statusBarTexture
    end

    function object:SetMinMaxValues(minValue, maxValue)
      self.minMax = { minValue, maxValue }
    end

    function object:SetValue(value)
      self.value = value
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

    function frame:RegisterUnitEvent(event, ...)
      self.events[#self.events + 1] = { event, ... }
    end

    function frame:UnregisterAllEvents()
      self.events = {}
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

    function frame:EnableMouse(enabled)
      self.mouseEnabled = enabled and true or false
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
        InterruptTracker = moduleDB,
      },
      InterruptTracker = moduleDB,
    },
    modules = {},
    RegisterModule = function(self, module)
      self.modules[module.key] = module
    end,
    DebugLog = function() end,
  }

  _G.SunderingTools = addon
  dofile("Core/CombatTrackSpellDB.lua")
  dofile("Core/CooldownViewerMeta.lua")
  dofile("Core/CombatTrackSync.lua")
  dofile("Core/CombatTrackEngine.lua")
  dofile("Core/TrackerSettings.lua")
  dofile("Modules/InterruptTrackerModel.lua")

  _G.SunderingToolsFramePositioning = {
    ApplySavedPosition = function() end,
    SaveAbsolutePosition = function() end,
    ResetToDefault = function() end,
  }
  _G.SunderingToolsTrackerFrame = {
    CreateContainerShell = function()
      return newFrame("Frame", nil)
    end,
    UpdateEditModeVisuals = function(_, _, callback)
      if callback then
        callback(false)
      end
    end,
  }

  _G.CreateFrame = function(frameType, _, parent)
    local frame = newFrame(frameType, parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
  end
  _G.C_Timer = {
    After = function(_, callback)
      delayedCallbacks[#delayedCallbacks + 1] = callback
    end,
    NewTicker = function(interval, callback)
      local ticker = {
        interval = interval,
        callback = callback,
        cancelled = false,
      }

      function ticker:Cancel()
        self.cancelled = true
      end

      activeTickers[#activeTickers + 1] = ticker
      return ticker
    end,
  }
  _G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function()
      return true
    end,
    SendAddonMessage = function(prefix, message, channel)
      sentMessages[#sentMessages + 1] = {
        prefix = prefix,
        message = message,
        channel = channel,
      }
      return true
    end,
  }
  _G.C_Spell = {
    GetSpellTexture = function(spellID)
      return "texture:" .. tostring(spellID)
    end,
  }
  _G.PlaySoundFile = function() end
  _G.SlashCmdList = {}
  _G.GameTooltip = {
    SetOwner = function() end,
    ClearLines = function() end,
    AddLine = function() end,
    Show = function() end,
    Hide = function() end,
  }
  _G.LibStub = nil
  _G.IsInGroup = function()
    return roster._group == true
  end
  _G.IsInRaid = function()
    return roster._raid == true
  end
  _G.GetNumGroupMembers = function()
    local count = 0
    for unit in pairs(roster) do
      if type(unit) == "string" and (unit:match("^party%d+$") or unit:match("^raid%d+$")) then
        count = count + 1
      end
    end
    if roster._group then
      count = count + 1
    end
    return count
  end
  _G.UnitExists = function(unit)
    return roster[unit] ~= nil
  end
  _G.UnitGUID = function(unit)
    return roster[unit] and roster[unit].guid or nil
  end
  _G.UnitName = function(unit)
    return roster[unit] and roster[unit].name or nil
  end
  _G.UnitClass = function(unit)
    local classToken = roster[unit] and roster[unit].classToken or nil
    return classToken, classToken
  end
  _G.UnitGroupRolesAssigned = function(unit)
    return roster[unit] and roster[unit].role or "DAMAGER"
  end
  _G.UnitPowerType = function(unit)
    return roster[unit] and roster[unit].powerType or nil
  end
  _G.UnitIsUnit = function(left, right)
    return left == right
  end
  _G.UnitIsPlayer = function(unit)
    return roster[unit] ~= nil and not tostring(unit):find("pet", 1, true)
  end
  _G.GetSpecialization = function()
    return roster.player and roster.player.specID and 1 or nil
  end
  _G.GetSpecializationInfo = function()
    local player = roster.player or {}
    return player.specID or 0, nil, nil, nil, player.role or "DAMAGER"
  end
  _G.GetInstanceInfo = function()
    return nil, "none"
  end
  _G.InCombatLockdown = function()
    return false
  end
  _G.GetTime = function()
    return now
  end
  _G.Ambiguate = function(name)
    return string.match(name or "", "^([^%-]+)") or name
  end
  _G.wipe = function(tbl)
    for key in pairs(tbl) do
      tbl[key] = nil
    end
  end
  _G.issecretvalue = function()
    return false
  end

  dofile("Modules/InterruptTracker.lua")

  local eventFrame = createdFrames[#createdFrames]
  local onEvent = eventFrame and eventFrame.scripts and eventFrame.scripts.OnEvent
  assert(type(onEvent) == "function", "interrupt tracker event frame should expose an OnEvent handler")

  local runtime
  for index = 1, 20 do
    local name, value = debug.getupvalue(onEvent, index)
    if name == "runtime" then
      runtime = value
      break
    end
  end

  assert(type(runtime) == "table", "interrupt tracker runtime should be reachable from the event handler")

  return {
    addon = addon,
    onEvent = onEvent,
    runtime = runtime,
    sentMessages = sentMessages,
    activeTickers = activeTickers,
    roster = roster,
    setTime = function(value)
      now = value
    end,
    clearMessages = function()
      for index = #sentMessages, 1, -1 do
        sentMessages[index] = nil
      end
    end,
    flushTimers = function()
      while #delayedCallbacks > 0 do
        local callbacks = delayedCallbacks
        delayedCallbacks = {}
        for _, callback in ipairs(callbacks) do
          if callback then
            callback()
          end
        end
      end
    end,
    tickAll = function()
      for _, ticker in ipairs(activeTickers) do
        if not ticker.cancelled and ticker.callback then
          ticker.callback()
        end
      end
    end,
  }
end

local function findLatestPayload(messages, messageType)
  local payload
  for _, sent in ipairs(messages) do
    local decodedType, decodedPayload = Sync.Decode(sent.message)
    if decodedType == messageType then
      payload = decodedPayload
    end
  end
  return payload
end

do
  local state = loadTracker(nil, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "ROGUE",
      specID = 259,
      role = "DAMAGER",
    },
    party1 = {
      guid = "party-guid",
      name = "Other-Realm",
      classToken = "MAGE",
      specID = 62,
      role = "DAMAGER",
    },
    nameplate1 = {
      guid = "enemy-guid",
      name = "Enemy",
      classToken = "NPC",
    },
  })

  state.onEvent(nil, "PLAYER_LOGIN")
  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()
  state.clearMessages()

  state.setTime(100)
  state.runtime.partyWatchFrames[1].scripts.OnEvent()
  state.setTime(100.2)
  state.runtime.nameplateWatchFrames.nameplate1.scripts.OnEvent(nil, "UNIT_SPELLCAST_INTERRUPTED", "nameplate1")

  local entry = state.runtime.engine:GetEntry("party-guid:2139")
  assert(entry ~= nil, "enemy interrupted events should correlate a recent party cast to the tracked interrupt spell")
  assert(entry.source == "correlated", "party interrupt correlation should be recorded as a correlated engine entry")
  assert(entry.readyAt == 124.2, "party interrupt correlation should project the full cooldown from the resolved interrupt spell")
end

do
  local state = loadTracker(nil, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "ROGUE",
      specID = 259,
      role = "DAMAGER",
    },
    party1 = {
      guid = "party-guid",
      name = "Other-Realm",
      classToken = "MAGE",
      specID = 62,
      role = "DAMAGER",
    },
    nameplate1 = {
      guid = "enemy-guid",
      name = "Enemy",
      classToken = "NPC",
    },
  })

  state.onEvent(nil, "PLAYER_LOGIN")
  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()
  state.clearMessages()

  state.setTime(100)
  state.runtime.partyWatchFrames[1].scripts.OnEvent()
  state.onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1766)
  state.setTime(100.2)
  state.runtime.nameplateWatchFrames.nameplate1.scripts.OnEvent(nil, "UNIT_SPELLCAST_INTERRUPTED", "nameplate1")

  local selfEntry = state.runtime.engine:GetEntry("player-guid:1766")
  local partyEntry = state.runtime.engine:GetEntry("party-guid:2139")
  assert(selfEntry ~= nil and selfEntry.source == "self", "exact self interrupt casts should stay authoritative when a tie exists")
  assert(partyEntry == nil or partyEntry.startTime == 0 or partyEntry.readyAt == 0, "party correlation should not steal credit from an exact self interrupt tie")
end

do
  local state = loadTracker(nil, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "ROGUE",
      specID = 259,
      role = "DAMAGER",
    },
    party1 = {
      guid = "party-a-guid",
      name = "Alpha-Realm",
      classToken = "MAGE",
      specID = 62,
      role = "DAMAGER",
    },
    party2 = {
      guid = "party-b-guid",
      name = "Beta-Realm",
      classToken = "WARLOCK",
      specID = 266,
      role = "DAMAGER",
      powerType = 0,
    },
    nameplate1 = {
      guid = "enemy-guid",
      name = "Enemy",
      classToken = "NPC",
    },
  })

  state.onEvent(nil, "PLAYER_LOGIN")
  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()

  state.setTime(100)
  state.runtime.partyWatchFrames[1].scripts.OnEvent()
  state.runtime.partyWatchFrames[2].scripts.OnEvent()
  state.setTime(100.2)
  state.runtime.nameplateWatchFrames.nameplate1.scripts.OnEvent(nil, "UNIT_SPELLCAST_INTERRUPTED", "nameplate1")

  local mageEntry = state.runtime.engine:GetEntry("party-a-guid:2139")
  local warlockEntry = state.runtime.engine:GetEntry("party-b-guid:19647")
  assert(mageEntry == nil or mageEntry.startTime == 0 or mageEntry.readyAt == 0, "ambiguous interrupt candidates should be dropped instead of guessing a winner")
  assert(warlockEntry == nil or warlockEntry.startTime == 0 or warlockEntry.readyAt == 0, "ambiguous interrupt candidates should consume the timestamps without crediting the wrong player")
end

do
  local state = loadTracker(nil, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "ROGUE",
      specID = 259,
      role = "DAMAGER",
    },
  })

  state.onEvent(nil, "PLAYER_LOGIN")
  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()
  state.clearMessages()

  state.setTime(100)
  state.onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1766)
  local initialSyncCount = 0
  for _, sent in ipairs(state.sentMessages) do
    local messageType = Sync.Decode(sent.message)
    if messageType == "INT" then
      initialSyncCount = initialSyncCount + 1
    end
  end

  state.setTime(105)
  state.tickAll()

  local syncCountAfterTick = 0
  for _, sent in ipairs(state.sentMessages) do
    local messageType = Sync.Decode(sent.message)
    if messageType == "INT" then
      syncCountAfterTick = syncCountAfterTick + 1
    end
  end

  assert(syncCountAfterTick > initialSyncCount, "active local interrupt cooldowns should periodically rebroadcast INT state for late sync recovery")
end

do
  local state = loadTracker(nil, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "ROGUE",
      specID = 259,
      role = "DAMAGER",
    },
    party1 = {
      guid = "party-guid",
      name = "Other-Realm",
      classToken = "MAGE",
      specID = 62,
      role = "DAMAGER",
    },
  })

  state.onEvent(nil, "PLAYER_LOGIN")
  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()
  state.clearMessages()

  state.setTime(100)
  state.onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1766)
  state.clearMessages()

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "HELLO:MAGE:62", nil, "Other-Realm")

  local replayed = findLatestPayload(state.sentMessages, "INT")
  assert(type(replayed) == "table", "peer HELLO messages should trigger replay of the current local interrupt cooldown state")
  assert(replayed.spellID == 1766, "interrupt replay after HELLO should carry the active canonical interrupt spell")
  assert(replayed.remaining == 15, "interrupt replay after HELLO should send the current remaining cooldown")
end
