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
    }
  end

  return messageType, {
    spellID = tonumber(parts[2]) or 0,
    cd = tonumber(parts[3]) or 0,
  }
end

function Sync.GetDefaultChannel()
  if IsInRaid and IsInRaid() then
    return "RAID"
  end

  if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    return "INSTANCE_CHAT"
  end

  if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) then
    return "PARTY"
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
  local resolvedChannel = channel or Sync.GetDefaultChannel()
  if not resolvedChannel then
    return false
  end

  local send = function()
    if IsInGroup and not IsInGroup() then
      return false
    end

    return C_ChatInfo.SendAddonMessage(PREFIX, encoded, resolvedChannel)
  end

  local result = send()
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, send)
    C_Timer.After(0.10, send)
  end

  return result
end

_G.SunderingToolsCombatTrackSync = Sync

return Sync
