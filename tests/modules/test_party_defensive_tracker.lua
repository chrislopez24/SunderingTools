local SpellDB = dofile("Core/CombatTrackSpellDB.lua")
local Sync = dofile("Core/CombatTrackSync.lua")
local Model = dofile("Modules/PartyDefensiveTrackerModel.lua")

local preview = Model.BuildPreviewIcons("DEATHKNIGHT")
assert(#preview >= 3, "party defensive tracker should expose at least three preview icons")

for _, entry in ipairs(preview) do
  assert(entry.kind == "DEF", "preview icons should stay within party-frame defensive tracking")
  assert(entry.spellID ~= 51052, "party defensive preview icons should not include raid defensives")
end

local text, rounded = Model.FormatTimerText(31.6)
assert(text == "32s", "party defensive icon timers should round to the nearest whole second")
assert(rounded == 32, "rounded timer cache should match the rendered timer text")

local dkEntries = Model.GetAvailableSpells("DEATHKNIGHT")
local spellDBEntries = SpellDB.GetDefensiveSpellsForClass("DEATHKNIGHT")
assert(#dkEntries == #spellDBEntries, "party defensive model should expose the shared DEF catalog for the class")
assert(dkEntries[1].kind == "DEF", "party defensive model should only expose DEF entries")
assert(dkEntries[1].spellID == spellDBEntries[1].spellID, "party defensive model should preserve spell ids from the shared catalog")

local sorted = Model.SortIcons({
  { key = "ready-b", spellID = 48792, cd = 180, startTime = 0 },
  { key = "cooling-a", spellID = 48707, cd = 60, startTime = 70 },
  { key = "ready-a", spellID = 55233, cd = 90, startTime = 0 },
}, 100)

assert(sorted[1].key == "cooling-a", "active cooldown icons should sort ahead of ready icons")
assert(sorted[2].key == "ready-a", "ready icons should fall back to spell ordering")
assert(sorted[3].key == "ready-b", "ready icons should remain stable after active cooldowns")

local function buildModuleDefaults(overrides)
  local defaults = {
    enabled = true,
    syncEnabled = true,
    previewWhenSolo = true,
    maxIcons = 4,
    iconSize = 20,
    iconSpacing = 1,
    attachPoint = "RIGHT",
    relativePoint = "LEFT",
    offsetX = -2,
    offsetY = 0,
    showTooltip = true,
  }

  for key, value in pairs(overrides or {}) do
    defaults[key] = value
  end

  return defaults
end

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

  return frame
end

local function loadTracker(moduleDB, roster, compactPartyFrame)
  roster = roster or {}
  moduleDB = buildModuleDefaults(moduleDB)

  _G.SunderingTools = nil
  _G.SunderingToolsCombatTrackSpellDB = nil
  _G.SunderingToolsCombatTrackSync = nil
  _G.SunderingToolsCombatTrackEngine = nil
  _G.SunderingToolsPartyDefensiveTrackerModel = nil
  _G.CompactPartyFrame = compactPartyFrame

  local createdFrames = {}
  local delayedCallbacks = {}
  local sentMessages = {}
  local addon = {
    db = {
      global = {
        editMode = false,
        activeEditModule = nil,
      },
      modules = {
        PartyDefensiveTracker = moduleDB,
      },
      PartyDefensiveTracker = moduleDB,
    },
    modules = {},
    RegisterModule = function(self, module)
      self.modules[module.key] = module
    end,
    SetModuleValue = function(self, moduleKey, key, value)
      self.db.modules[moduleKey][key] = value
      self.db[moduleKey] = self.db.modules[moduleKey]
    end,
    RefreshSettings = function() end,
    DebugLog = function() end,
  }

  _G.SunderingTools = addon
  dofile("Core/CombatTrackSpellDB.lua")
  dofile("Core/CombatTrackSync.lua")
  dofile("Core/CombatTrackEngine.lua")
  dofile("Modules/PartyDefensiveTrackerModel.lua")

  _G.C_Timer = {
    After = function(_, callback)
      delayedCallbacks[#delayedCallbacks + 1] = callback
    end,
    NewTicker = function(_, callback)
      return {
        callback = callback,
        Cancel = function(self)
          self.cancelled = true
        end,
      }
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
  _G.hooksecurefunc = function() end
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
  _G.C_Spell = {
    GetSpellTexture = function(spellID)
      return "texture:" .. tostring(spellID)
    end,
  }
  _G.GameTooltip = {
    owner = nil,
    lines = {},
    shown = false,
    SetOwner = function(self, owner, anchor)
      self.owner = owner
      self.anchor = anchor
    end,
    ClearLines = function(self)
      self.lines = {}
    end,
    AddLine = function(self, text, ...)
      self.lines[#self.lines + 1] = {
        text = text,
        color = { ... },
      }
    end,
    Show = function(self)
      self.shown = true
    end,
    Hide = function(self)
      self.shown = false
    end,
  }

  dofile("Modules/PartyDefensiveTracker.lua")

  local eventFrame = createdFrames[#createdFrames]
  local onEvent = eventFrame and eventFrame.scripts and eventFrame.scripts.OnEvent
  assert(type(onEvent) == "function", "party defensive tracker should register an OnEvent handler")

  local runtime
  for index = 1, 24 do
    local name, value = debug.getupvalue(onEvent, index)
    if name == "runtime" then
      runtime = value
      break
    end
  end

  assert(type(runtime) == "table", "party defensive runtime should be captured by the tracker event handler")

  return {
    addon = addon,
    moduleDB = moduleDB,
    roster = roster,
    onEvent = onEvent,
    runtime = runtime,
    createdFrames = createdFrames,
    compactPartyFrame = compactPartyFrame,
    delayedCallbacks = delayedCallbacks,
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

local function buildCompactPartyFrame()
  local compactPartyFrame = {
    memberUnitFrames = {},
    RefreshMembers = function() end,
  }

  for index = 1, 5 do
    compactPartyFrame.memberUnitFrames[index] = newFrame("Button", compactPartyFrame)
  end

  return compactPartyFrame
end

local function getDefEntryKeys(runtime)
  local keys = {}
  for _, entry in ipairs(runtime.engine:GetEntriesByKind("DEF")) do
    keys[#keys + 1] = entry.key
  end
  table.sort(keys)
  return keys
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = false,
    syncEnabled = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, compactPartyFrame)

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:48707:DEF:60:1:160", nil, "Other-Realm")

  assert(#getDefEntryKeys(state.runtime) == 0, "disabled party defensive tracker should ignore inbound sync state")
  assert(next(state.runtime.partyUsers) == nil, "disabled party defensive tracker should not create remote users from sync traffic")

  state.roster._group = true
  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()
  assert(#state.sentMessages == 0, "disabled party defensive tracker should not broadcast sync traffic from delayed announce paths")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = true,
    syncEnabled = false,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, compactPartyFrame)

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:48707:DEF:60:1:160", nil, "Other-Realm")

  assert(#getDefEntryKeys(state.runtime) == 0, "sync-disabled party defensive tracker should ignore inbound sync state")
  assert(next(state.runtime.partyUsers) == nil, "sync-disabled party defensive tracker should not create remote users from sync traffic")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, compactPartyFrame)

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_MANIFEST:RAID_DEF:51052", nil, "Other-Realm")

  assert(#getDefEntryKeys(state.runtime) == 0, "party defensive tracker should ignore raid-def manifests from the shared sync prefix")
  assert(state.runtime.partyUsers.Other == nil, "party defensive tracker should not create users from raid-def manifests")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"
  compactPartyFrame.memberUnitFrames[2].unit = "party1"

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
  }, roster, compactPartyFrame)

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:48707:DEF:60:1:160", nil, "Other-Realm")
  assert(#getDefEntryKeys(state.runtime) == 0, "senders outside the tracked live roster should be ignored before the party subset is known")
  assert(state.runtime.partyUsers.Other == nil, "unknown senders should not create placeholder users before they join the tracked subset")

  roster._group = true
  roster.party1 = {
    guid = "party-guid",
    name = "Other-Realm",
    classToken = "DEATHKNIGHT",
  }

  state.onEvent(nil, "GROUP_ROSTER_UPDATE")
  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:48707:DEF:60:1:160", nil, "Other-Realm")

  local reconciledKeys = getDefEntryKeys(state.runtime)
  assert(#reconciledKeys >= 1, "group roster refresh should preserve tracked party defensive entries")

  local foundRosterEntry = false
  local foundPlaceholderEntry = false
  for _, key in ipairs(reconciledKeys) do
    if key == "party-guid:48707" then
      foundRosterEntry = true
    elseif key == "sync:Other:48707" then
      foundPlaceholderEntry = true
    end
  end

  assert(foundRosterEntry == true, "tracked party senders should apply DEF sync once the live compact party roster includes them")
  assert(foundPlaceholderEntry == false, "tracked party sync should not fall back to placeholder remote identities")

  local memberAttachment = compactPartyFrame.memberUnitFrames[2].SunderingToolsPartyDefensiveAttachment
  assert(type(memberAttachment) == "table", "party defensive tracker should attach a container to the owner compact party frame")
  assert(memberAttachment._ownerFrame == compactPartyFrame.memberUnitFrames[2], "attachment container should stay parented to the owner party frame")
  assert(type(memberAttachment.points) == "table" and #memberAttachment.points >= 1, "party defensive attachment should record an anchor point")
  assert(memberAttachment.points[1][1] == "RIGHT", "party defensive attachment should anchor from its right edge")
  assert(memberAttachment.points[1][3] == "LEFT", "party defensive attachment should sit outside the left edge of the unit frame")
  assert(type(memberAttachment._entries) == "table" and #memberAttachment._entries >= 1, "owner frame attachment should be populated from DEF runtime state")
  assert(memberAttachment._entries[1].spellID == 48707, "attached owner frame icons should render the tracked DEF spell")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"
  compactPartyFrame.memberUnitFrames[2].unit = "party1"

  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
    party1 = {
      guid = "party-guid",
      name = "Other-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, compactPartyFrame)

  state.onEvent(nil, "GROUP_ROSTER_UPDATE")
  local beforeKeys = getDefEntryKeys(state.runtime)
  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:48707:DEF:60:1:160", nil, "Intruder-Realm")

  local entryKeys = getDefEntryKeys(state.runtime)
  assert(#entryKeys == #beforeKeys, "non-party senders should not add placeholder defensive runtime entries")
  assert(state.runtime.partyUsers.Intruder == nil, "non-party senders should be ignored instead of creating placeholder users")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"
  compactPartyFrame.memberUnitFrames[2].unit = "raid1"

  local roster = {
    _group = true,
    _raid = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
    raid1 = {
      guid = "raid-guid",
      name = "Other-Realm",
      classToken = "DEATHKNIGHT",
    },
  }
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, roster, compactPartyFrame)

  state.onEvent(nil, "CHAT_MSG_ADDON", Sync.GetPrefix(), "DEF_STATE:48707:DEF:60:1:160", nil, "Other-Realm")
  state.onEvent(nil, "GROUP_ROSTER_UPDATE")

  assert(state.runtime.partyUsers.Other.playerGUID == "raid-guid", "raid-context compact party frames should still reconcile remote defensive owners from the live roster")

  local memberAttachment = compactPartyFrame.memberUnitFrames[2].SunderingToolsPartyDefensiveAttachment
  assert(type(memberAttachment) == "table", "raid-context compact party member frames should still receive defensive attachments")
  assert(type(memberAttachment._entries) == "table" and #memberAttachment._entries >= 1, "raid-context compact party frames should still render defensive entries")
  assert(memberAttachment._entries[1].spellID == 48707, "raid-context compact party frames should keep the tracked DEF spell on the owner frame")
end

do
  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
    previewWhenSolo = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, nil)

  state.addon.modules.PartyDefensiveTracker:SetEditMode(true)
  assert(_G.CompactPartyFrame == nil, "late-frame test should start without a compact party frame")

  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"
  _G.CompactPartyFrame = compactPartyFrame

  state.flushTimers()

  local memberAttachment = compactPartyFrame.memberUnitFrames[1].SunderingToolsPartyDefensiveAttachment
  assert(type(memberAttachment) == "table", "late compact party frame creation should still attach the defensive container in edit mode")
  assert(type(memberAttachment._entries) == "table" and #memberAttachment._entries >= 1, "late compact party frame creation should still populate preview defensive icons")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
    previewWhenSolo = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, compactPartyFrame)

  state.addon.modules.PartyDefensiveTracker:SetEditMode(true)

  local memberAttachment = compactPartyFrame.memberUnitFrames[1].SunderingToolsPartyDefensiveAttachment
  assert(type(memberAttachment) == "table", "edit mode should still attach to the live Blizzard compact party frame")
  assert(type(memberAttachment._entries) == "table" and #memberAttachment._entries >= 1, "edit mode should populate preview defensive icons on attached party frames")
  assert(memberAttachment._entries[1].kind == "DEF", "edit mode preview should stay within the party defensive catalog")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
    previewWhenSolo = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, compactPartyFrame)

  local patched = false
  for index = 1, 40 do
    local name = debug.getupvalue(state.onEvent, index)
    if name == "db" then
      debug.setupvalue(state.onEvent, index, nil)
      patched = true
      break
    end
  end

  assert(patched == true, "test harness should be able to simulate an uninitialized module db upvalue")

  local ok = pcall(function()
    state.onEvent(nil, "SPELLS_CHANGED")
  end)

  assert(ok == true, "party defensive tracker should tolerate SPELLS_CHANGED before PLAYER_LOGIN initializes db")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
    previewWhenSolo = true,
    attachPoint = "RIGHT",
    relativePoint = "LEFT",
    offsetX = -2,
    offsetY = 0,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, compactPartyFrame)

  state.addon.modules.PartyDefensiveTracker:SetEditMode(true)

  local memberAttachment = compactPartyFrame.memberUnitFrames[1].SunderingToolsPartyDefensiveAttachment
  assert(type(memberAttachment) == "table", "edit mode should create an attachment before reanchor verification")
  assert(memberAttachment.points[1][1] == "RIGHT", "initial attachment should use the configured point")
  assert(memberAttachment.points[1][3] == "LEFT", "initial attachment should use the configured relative point")
  assert(memberAttachment.points[1][4] == -2 and memberAttachment.points[1][5] == 0, "initial attachment should use the configured offsets")

  state.moduleDB.attachPoint = "TOPLEFT"
  state.moduleDB.relativePoint = "BOTTOMRIGHT"
  state.moduleDB.offsetX = 7
  state.moduleDB.offsetY = 11
  state.addon.modules.PartyDefensiveTracker:onConfigChanged(state.addon, state.moduleDB)

  assert(memberAttachment.points[1][1] == "TOPLEFT", "existing attachments should reanchor when attachPoint changes")
  assert(memberAttachment.points[1][3] == "BOTTOMRIGHT", "existing attachments should update relativePoint in place")
  assert(memberAttachment.points[1][4] == 7 and memberAttachment.points[1][5] == 11, "existing attachments should refresh offsets in place")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
    previewWhenSolo = true,
    showTooltip = true,
  }, {
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DEATHKNIGHT",
    },
  }, compactPartyFrame)

  state.addon.modules.PartyDefensiveTracker:SetEditMode(true)

  local memberAttachment = compactPartyFrame.memberUnitFrames[1].SunderingToolsPartyDefensiveAttachment
  local firstIcon = memberAttachment and memberAttachment._icons and memberAttachment._icons[1]
  assert(type(firstIcon) == "table", "attachment should create icon frames for tooltip verification")
  assert(type(firstIcon.scripts.OnEnter) == "function", "party defensive icons should register an OnEnter tooltip handler")
  assert(type(firstIcon.scripts.OnLeave) == "function", "party defensive icons should register an OnLeave tooltip handler")

  GameTooltip.owner = nil
  GameTooltip.lines = {}
  GameTooltip.shown = false
  firstIcon.scripts.OnEnter(firstIcon)
  assert(GameTooltip.owner == firstIcon, "tooltip-enabled icons should attach the GameTooltip on hover")
  assert(#GameTooltip.lines >= 1, "tooltip-enabled icons should populate at least one tooltip line")
  assert(GameTooltip.shown == true, "tooltip-enabled icons should show the tooltip")

  state.moduleDB.showTooltip = false
  state.addon.modules.PartyDefensiveTracker:onConfigChanged(state.addon, state.moduleDB)

  GameTooltip.owner = nil
  GameTooltip.lines = {}
  GameTooltip.shown = false
  firstIcon.scripts.OnEnter(firstIcon)
  assert(GameTooltip.owner == nil, "showTooltip=false should suppress tooltip ownership on hover")
  assert(#GameTooltip.lines == 0, "showTooltip=false should suppress tooltip content")
  assert(GameTooltip.shown == false, "showTooltip=false should suppress tooltip display")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "MONK",
      specID = 268,
      knownSpells = {
        [115203] = true,
        [119582] = true,
      },
    },
  }, compactPartyFrame)

  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()

  local manifestPayload
  for _, sent in ipairs(state.sentMessages) do
    local messageType, payload = Sync.Decode(sent.message)
    if messageType == "DEF_MANIFEST" then
      manifestPayload = payload
    end
  end

  assert(type(manifestPayload) == "table", "party defensive tracker should broadcast a manifest for the local player")
  local manifestSet = {}
  for _, spellID in ipairs(manifestPayload.spells or {}) do
    manifestSet[spellID] = true
  end

  assert(manifestSet[115203] == true, "party defensive manifests should include learned spec-appropriate spells")
  assert(manifestSet[119582] == true, "party defensive manifests should include learned charge-based spells")
  assert(manifestSet[122470] ~= true, "party defensive manifests should not advertise spells that the local spec does not know")

  local fortifyingEntry = state.runtime.engine:GetEntry("player-guid:115203")
  assert(fortifyingEntry ~= nil and fortifyingEntry.baseCd == 360, "party defensive runtime should resolve spec-specific cooldown variants for the local player")

  local brewEntry = state.runtime.engine:GetEntry("player-guid:119582")
  assert(brewEntry ~= nil and brewEntry.charges == 2, "party defensive runtime should preserve spec-specific charge counts for the local player")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

  local state = loadTracker({
    enabled = true,
    syncEnabled = true,
  }, {
    _group = true,
    player = {
      guid = "player-guid",
      name = "Player-Realm",
      classToken = "DRUID",
      specID = 105,
      knownSpells = {
        [102342] = true,
      },
      activeConfigID = 1,
      treeIDs = { 21 },
      nodesByTree = { [21] = { 121 } },
      nodeInfo = {
        [121] = {
          activeEntry = { entryID = 221 },
          activeRank = 1,
        },
      },
      entryDefinitions = {
        [221] = 321,
      },
      definitionSpells = {
        [321] = 382552,
      },
    },
  }, compactPartyFrame)

  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()

  local ironbarkEntry = state.runtime.engine:GetEntry("player-guid:102342")
  assert(ironbarkEntry ~= nil, "party defensive runtime should register Ironbark for the local player")
  assert(ironbarkEntry.baseCd == 70, "party defensive runtime should seed Ironbark with the locally reduced Restoration Druid cooldown")
end

do
  local compactPartyFrame = buildCompactPartyFrame()
  compactPartyFrame.memberUnitFrames[1].unit = "player"

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
        [48707] = true,
      },
      activeConfigID = 3,
      treeIDs = { 23 },
      nodesByTree = { [23] = { 123 } },
      nodeInfo = {
        [123] = {
          activeEntry = { entryID = 223 },
          activeRank = 1,
        },
      },
      entryDefinitions = {
        [223] = 323,
      },
      definitionSpells = {
        [323] = 205727,
      },
    },
  }, compactPartyFrame)

  state.onEvent(nil, "PLAYER_ENTERING_WORLD")
  state.flushTimers()

  local amsEntry = state.runtime.engine:GetEntry("player-guid:48707")
  assert(amsEntry ~= nil, "party defensive runtime should register Anti-Magic Shell for the local player")
  assert(amsEntry.baseCd == 40, "party defensive runtime should seed Anti-Magic Shell with the locally reduced Death Knight cooldown")
end
