local Sync = {}
local PREFIX = "SUNDERING_CT"

local function split(text, delimiter)
  local parts = {}
  local startIndex = 1

  while true do
    local nextIndex = string.find(text, delimiter, startIndex, true)
    if not nextIndex then
      parts[#parts + 1] = string.sub(text, startIndex)
      break
    end

    parts[#parts + 1] = string.sub(text, startIndex, nextIndex - 1)
    startIndex = nextIndex + 1
  end

  return parts
end

local function encodeSpellList(spells)
  local values = {}

  for _, spellID in ipairs(spells or {}) do
    values[#values + 1] = tostring(spellID)
  end

  return table.concat(values, ",")
end

local function decodeSpellList(text)
  if text == nil or text == "" then
    return {}
  end

  local spells = {}
  for _, value in ipairs(split(text, ",")) do
    spells[#spells + 1] = tonumber(value) or 0
  end

  return spells
end

function Sync.GetPrefix()
  return PREFIX
end

function Sync.RegisterPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    return C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  end

  return false
end

function Sync.Encode(messageType, payload)
  payload = payload or {}

  if messageType == "HELLO" then
    return table.concat({
      "HELLO",
      payload.classToken or "",
      tostring(payload.specID or 0),
    }, ":")
  end

  if messageType == "DEF_MANIFEST" then
    return table.concat({
      "DEF_MANIFEST",
      tostring(payload.kind or ""),
      encodeSpellList(payload.spells),
    }, ":")
  end

  if messageType == "INT_MANIFEST" or messageType == "CC_MANIFEST" then
    return table.concat({
      messageType,
      encodeSpellList(payload.spells),
    }, ":")
  end

  if messageType == "DEF_STATE" then
    return table.concat({
      "DEF_STATE",
      tostring(payload.spellID or 0),
      tostring(payload.kind or ""),
      tostring(payload.cd or 0),
      tostring(payload.charges or 0),
      tostring(payload.remaining or 0),
    }, ":")
  end

  if payload.remaining ~= nil then
    return table.concat({
      messageType or "",
      tostring(payload.spellID or 0),
      tostring(payload.cd or 0),
      tostring(payload.remaining or 0),
    }, ":")
  end

  return table.concat({
    messageType or "",
    tostring(payload.spellID or 0),
    tostring(payload.cd or 0),
  }, ":")
end

function Sync.Decode(message)
  local parts = split(message or "", ":")
  local messageType = parts[1]

  if messageType == "HELLO" then
    return messageType, {
      classToken = parts[2],
      specID = tonumber(parts[3]) or 0,
    }
  end

  if messageType == "DEF_MANIFEST" then
    local kind = parts[2]
    local spellsIndex = 3

    if #parts == 2 then
      kind = nil
      spellsIndex = 2
    elseif kind == nil or kind == "" then
      kind = nil
      spellsIndex = 2
    end

    return messageType, {
      kind = kind,
      spells = decodeSpellList(parts[spellsIndex]),
    }
  end

  if messageType == "INT_MANIFEST" or messageType == "CC_MANIFEST" then
    return messageType, {
      spells = decodeSpellList(parts[2]),
    }
  end

  if messageType == "DEF_STATE" then
    local kind = parts[3]
    local cdIndex = 4
    local chargesIndex = 5
    local timingIndex = 6
    local remaining = nil
    local readyAt = nil

    if #parts == 5 then
      kind = nil
      cdIndex = 3
      chargesIndex = 4
      timingIndex = 5
    elseif kind == nil or kind == "" then
      kind = nil
      cdIndex = 3
      chargesIndex = 4
      timingIndex = 5
    else
      remaining = tonumber(parts[timingIndex]) or 0
    end

    if kind == nil then
      readyAt = tonumber(parts[timingIndex]) or 0
    end

    return messageType, {
      spellID = tonumber(parts[2]) or 0,
      kind = kind,
      cd = tonumber(parts[cdIndex]) or 0,
      charges = tonumber(parts[chargesIndex]) or 0,
      remaining = remaining,
      readyAt = readyAt,
    }
  end

  return messageType, {
    spellID = tonumber(parts[2]) or 0,
    cd = tonumber(parts[3]) or 0,
    remaining = tonumber(parts[4]),
  }
end

function Sync.GetDefaultChannel()
  if IsInRaid and IsInRaid() then
    return "RAID"
  end

  if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) then
    return "PARTY"
  end

  if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    return "INSTANCE_CHAT"
  end

  return nil
end

function Sync.Send(messageType, payload, channel)
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
    return false
  end

  if IsInGroup and not IsInGroup() then
    return false
  end

  local encoded = Sync.Encode(messageType, payload)

  local function buildChannels()
    if channel then
      return { channel }
    end

    if IsInRaid and IsInRaid() then
      return { "RAID" }
    end

    local channels = {}
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) then
      channels[#channels + 1] = "PARTY"
    end
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
      channels[#channels + 1] = "INSTANCE_CHAT"
    end
    return channels
  end

  local function sendOnce()
    if IsInGroup and not IsInGroup() then
      return false
    end

    local channels = buildChannels()
    if not channels or #channels == 0 then
      return false
    end

    for _, resolvedChannel in ipairs(channels) do
      if C_ChatInfo.SendAddonMessage(PREFIX, encoded, resolvedChannel) then
        return true
      end
    end

    return false
  end

  local result = sendOnce()
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, sendOnce)
    C_Timer.After(0.10, sendOnce)
  end

  return result
end

_G.SunderingToolsCombatTrackSync = Sync

return Sync
