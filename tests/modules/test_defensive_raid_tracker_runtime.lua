local Sync = dofile("Core/CombatTrackSync.lua")

local function buildModuleDefaults(overrides)
  local defaults = {
    enabled = true,
    syncEnabled = true,
    previewWhenSolo = true,
    maxBars = 3,
    growDirection = "DOWN",
    spacing = 0,
    iconSize = 18,
    barWidth = 190,
    barHeight = 18,
    fontSize = 11,
    showHeader = true,
    showInDungeon = true,
    showInRaid = true,
    showInWorld = true,
    showInArena = true,
    hideOutOfCombat = false,
    showReady = true,
    tooltipOnHover = true,
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
  _G.SunderingToolsCombatTrackSync = nil
  _G.SunderingToolsCombatTrackEngine = nil
  _G.SunderingToolsDefensiveRaidTrackerModel = nil

  local createdFrames = {}
  local sentMessages = {}
  local delayedCallbacks = {}

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

    function object:SetShown(shown)
      self.shown = shown and true or false
    end

    function object:IsShown()
      return self.shown
    end

    function object:SetAlpha(alpha)
      self.alpha = alpha
    end

    function object:SetText(textValue)
      self.text = textValue
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
        DefensiveRaidTracker = moduleDB,
      },
      DefensiveRaidTracker = moduleDB,
    },
    modules = {},
    RegisterModule = function(self, module)
      self.modules[module.key] = module
    end,
    DebugLog = function() end,
  }

  _G.SunderingTools = addon
  dofile("Core/CombatTrackSpellDB.lua")
  dofile("Core/CombatTrackSync.lua")
  dofile("Core/CombatTrackEngine.lua")
  dofile("Modules/DefensiveRaidTrackerModel.lua")

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
  _G.C_Timer = {
    After = function(_, callback)
      delayedCallbacks[#delayedCallbacks + 1] = callback
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
  _G.CreateFrame = function(frameType, _, parent)
    local frame = newFrame(frameType, parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
  end
  _G.IsInGroup = function()
    return roster._group == true
  end
  _G.IsInRaid = function()
    return roster._raid == true
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
  _G.GetSpecialization = function()
    return roster.player and roster.player.specID and 1 or nil
  end
  _G.GetSpecializationInfo = function()
    return roster.player and roster.player.specID or nil
  end
  _G.GetInstanceInfo = function()
    return nil, "none"
  end
  _G.InCombatLockdown = function()
    return false
  end
  _G.GetTime = function()
    return 100
  end
  _G.Ambiguate = function(name)
    return string.match(name or "", "^([^%-]+)") or name
  end
  _G.wipe = function(tbl)
    for key in pairs(tbl) do
      tbl[key] = nil
    end
  end
  _G.IsPlayerSpell = function(spellID)
    local knownSpells = roster.player and roster.player.knownSpells or nil
    if type(knownSpells) ~= "table" then
      return true
    end

    return knownSpells[spellID] == true
  end
  _G.IsSpellKnownOrOverridesKnown = _G.IsPlayerSpell
  _G.C_ClassTalents = {
    GetActiveConfigID = function()
      return roster.player and roster.player.activeConfigID or nil
    end,
  }
  _G.C_Traits = {
    GetConfigInfo = function(configID)
      if configID ~= (roster.player and roster.player.activeConfigID) then
        return nil
      end

      return {
        treeIDs = roster.player and roster.player.treeIDs or {},
      }
    end,
    GetTreeNodes = function(treeID)
      local nodesByTree = roster.player and roster.player.nodesByTree or {}
      return nodesByTree[treeID] or {}
    end,
    GetNodeInfo = function(configID, nodeID)
      if configID ~= (roster.player and roster.player.activeConfigID) then
        return nil
      end

      local nodeInfo = roster.player and roster.player.nodeInfo and roster.player.nodeInfo[nodeID] or nil
      if not nodeInfo then
        return nil
      end

      return nodeInfo
    end,
    GetEntryInfo = function(configID, entryID)
      if configID ~= (roster.player and roster.player.activeConfigID) then
        return nil
      end

      local definitionID = roster.player and roster.player.entryDefinitions and roster.player.entryDefinitions[entryID] or nil
      if not definitionID then
        return nil
      end

      return {
        definitionID = definitionID,
      }
    end,
    GetDefinitionInfo = function(definitionID)
      local spellID = roster.player and roster.player.definitionSpells and roster.player.definitionSpells[definitionID] or nil
      if not spellID then
        return nil
      end

      return {
        spellID = spellID,
      }
    end,
  }

  dofile("Modules/DefensiveRaidTracker.lua")

  local eventFrame = createdFrames[#createdFrames]
  local onEvent = eventFrame and eventFrame.scripts and eventFrame.scripts.OnEvent
  assert(type(onEvent) == "function", "tracker event frame should register an OnEvent handler")

  local runtime
  for index = 1, 20 do
    local name, value = debug.getupvalue(onEvent, index)
    if name == "runtime" then
      runtime = value
      break
    end
  end

  assert(type(runtime) == "table", "runtime state should be captured by the tracker event handler")

  return {
    addon = addon,
    moduleDB = moduleDB,
    roster = roster,
    onEvent = onEvent,
    runtime = runtime,
    sentMessages = sentMessages,
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
  }
end

local function getRaidEntryKeys(runtime)
  local keys = {}
  for _, entry in ipairs(runtime.engine:GetEntriesByKind("RAID_DEF")) do
    keys[#keys + 1] = entry.key
  end
  table.sort(keys)
  return keys
end

do
  local state = loadTracker({
    enabled = false,
    syncEnabled = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  })

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:51052:RAID_DEF:120:1:120", nil, "Other-Realm")

  assert(#getRaidEntryKeys(state.runtime) == 0, "disabled raid defensive tracker should ignore inbound sync state")
  assert(next(state.runtime.partyUsers) == nil, "disabled raid defensive tracker should not create remote users from sync traffic")
end

do
  local state = loadTracker({
    enabled = true,
    syncEnabled = false,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  })

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:51052:RAID_DEF:120:1:120", nil, "Other-Realm")

  assert(#getRaidEntryKeys(state.runtime) == 0, "sync-disabled raid defensive tracker should ignore inbound sync state")
  assert(next(state.runtime.partyUsers) == nil, "sync-disabled raid defensive tracker should not create remote users from sync traffic")
end

do
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
      specID = 250,
    },
  })

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:48707:DEF:60:1:160", nil, "Other-Realm")

  assert(#getRaidEntryKeys(state.runtime) == 0, "raid defensive tracker should ignore synced party defensive states")
  assert(state.runtime.partyUsers.Other == nil, "raid defensive tracker should not create users from non-raid-def sync payloads")
end

do
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
      specID = 250,
    },
  })

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_MANIFEST:DEF:48707,48792", nil, "Other-Realm")

  assert(#getRaidEntryKeys(state.runtime) == 0, "raid defensive tracker should ignore party-def manifests from the shared sync prefix")
  assert(state.runtime.partyUsers.Other == nil, "raid defensive tracker should not create users from party-def manifests")
end

do
  local roster = {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, roster)

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:51052:RAID_DEF:120:1:120", nil, "Other-Realm")
  local placeholderKeys = getRaidEntryKeys(state.runtime)
  assert(#placeholderKeys == 1 and placeholderKeys[1] == "sync:Other:51052", "sync-only users should create a placeholder runtime entry before roster data arrives")

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_MANIFEST:", nil, "Other-Realm")
  assert(#getRaidEntryKeys(state.runtime) == 0, "empty manifests should prune stale raid defensive runtime entries")

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:51052:RAID_DEF:120:1:120", nil, "Other-Realm")
  roster._group = true
  roster.party1 = {
    guid = "party-guid",
    name = "Other-Realm",
    classToken = "DEATHKNIGHT",
  }

  state.onEvent(nil, "GROUP_ROSTER_UPDATE")

  local reconciledKeys = getRaidEntryKeys(state.runtime)
  local remoteEntryCount = 0
  local foundRosterEntry = false
  local foundPlaceholderEntry = false
  for _, key in ipairs(reconciledKeys) do
    if key == "party-guid:51052" then
      remoteEntryCount = remoteEntryCount + 1
      foundRosterEntry = true
    elseif key == "sync:Other:51052" then
      foundPlaceholderEntry = true
    end
  end

  assert(foundRosterEntry == true, "roster refresh should reconcile placeholder sync users to the live roster identity")
  assert(foundPlaceholderEntry == false, "roster refresh should remove the stale placeholder runtime entry once a real roster identity is known")
  assert(remoteEntryCount == 1, "roster refresh should not leave duplicate remote raid defensive entries for the same player")
  assert(state.runtime.partyUsers.Other.playerGUID == "party-guid", "party user state should use the live roster guid after reconciliation")
end

do
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
    strictSyncMode = true,
  }, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
      specID = 250,
    },
    party1 = {
      guid = "party-guid",
      name = "Other-Realm",
      classToken = "DEATHKNIGHT",
      specID = 250,
    },
  })

  state.onEvent(nil, "GROUP_ROSTER_UPDATE")
  local baselineKeys = getRaidEntryKeys(state.runtime)
  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:51052:RAID_DEF:120:1:120", nil, "Other-Realm")
  local keysWithoutManifest = getRaidEntryKeys(state.runtime)
  assert(#keysWithoutManifest == #baselineKeys, "strict raid defensive mode should ignore synced state until a manifest is known")

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_MANIFEST:RAID_DEF:51052", nil, "Other-Realm")
  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:51052:RAID_DEF:120:1:120", nil, "Other-Realm")
  local keysWithManifest = getRaidEntryKeys(state.runtime)
  assert(#keysWithManifest == (#baselineKeys + 1), "strict raid defensive mode should accept synced state after a manifest announces the spell")
end

do
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "PRIEST",
      specID = 256,
      knownSpells = {
        [62618] = true,
        [64843] = true,
      },
    },
  })

  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()

  local manifestPayload
  for _, sent in ipairs(state.sentMessages) do
    local messageType, payload = Sync.Decode(sent.message)
    if messageType == "DEF_MANIFEST" then
      manifestPayload = payload
    end
  end

  assert(type(manifestPayload) == "table", "raid defensive tracker should broadcast a manifest for the local player")
  local manifestSet = {}
  for _, spellID in ipairs(manifestPayload.spells or {}) do
    manifestSet[spellID] = true
  end

  assert(manifestSet[62618] == true, "raid defensive manifests should include learned raid defensives")
  assert(manifestSet[64843] == true, "raid defensive manifests should include additional learned raid defensives")
  assert(manifestSet[271466] ~= true, "raid defensive manifests should not advertise unlearned spec/talent gated raid defensives")

  local barrierEntry = state.runtime.engine:GetEntry("player-guid:62618")
  assert(barrierEntry ~= nil and barrierEntry.baseCd == 180, "raid defensive runtime should register learned raid defensives for the local player")
end

do
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "PALADIN",
      specID = 65,
      knownSpells = {
        [31821] = true,
      },
      activeConfigID = 1,
      treeIDs = { 11 },
      nodesByTree = { [11] = { 101 } },
      nodeInfo = {
        [101] = {
          activeEntry = { entryID = 201 },
          activeRank = 1,
        },
      },
      entryDefinitions = {
        [201] = 301,
      },
      definitionSpells = {
        [301] = 392911,
      },
    },
  })

  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()

  local auraMasteryEntry = state.runtime.engine:GetEntry("player-guid:31821")
  assert(auraMasteryEntry ~= nil, "raid defensive runtime should register Aura Mastery for the local player")
  assert(auraMasteryEntry.baseCd == 150, "raid defensive runtime should seed Aura Mastery with the locally reduced Holy Paladin cooldown")
end

do
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
      specID = 252,
      knownSpells = {
        [51052] = true,
      },
      activeConfigID = 2,
      treeIDs = { 12 },
      nodesByTree = { [12] = { 102 } },
      nodeInfo = {
        [102] = {
          activeEntry = { entryID = 202 },
          activeRank = 1,
        },
      },
      entryDefinitions = {
        [202] = 302,
      },
      definitionSpells = {
        [302] = 374383,
      },
    },
  })

  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()
  state.onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 145629)

  local amzEntry = state.runtime.engine:GetEntry("player-guid:51052")
  assert(amzEntry ~= nil, "raid defensive tracker should normalize Anti-Magic Zone aura spellcasts back to the canonical spell")
  assert(amzEntry.baseCd == 180, "raid defensive tracker should apply local talent cooldown reductions for Anti-Magic Zone")
  assert(amzEntry.readyAt == 280, "raid defensive tracker should derive readyAt from the locally reduced Anti-Magic Zone cooldown")

  local syncedState
  for _, sent in ipairs(state.sentMessages) do
    local messageType, payload = Sync.Decode(sent.message)
    if messageType == "DEF_STATE" and payload.spellID == 51052 then
      syncedState = payload
    end
  end

  assert(type(syncedState) == "table", "raid defensive self casts should broadcast sync state for Anti-Magic Zone")
  assert(syncedState.kind == "RAID_DEF", "raid defensive self casts should broadcast the RAID_DEF kind")
  assert(syncedState.cd == 180, "raid defensive self casts should sync the locally reduced Anti-Magic Zone cooldown")
  assert(syncedState.remaining == 180, "raid defensive self casts should sync the locally reduced remaining cooldown for Anti-Magic Zone")
end
