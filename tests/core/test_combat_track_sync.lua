local Sync = dofile("Core/CombatTrackSync.lua")

local helloEncoded = Sync.Encode("HELLO", {
  classToken = "MAGE",
  specID = 63,
})
assert(helloEncoded == "HELLO:MAGE:63", "hello payloads should include the announced spec id for defensive variant resolution")

local helloType, helloPayload = Sync.Decode(helloEncoded)
assert(helloType == "HELLO", "sync decode should preserve hello message type")
assert(helloPayload.classToken == "MAGE", "sync decode should preserve the announced class token")
assert(helloPayload.specID == 63, "sync decode should preserve the announced spec id")

local manifestEncoded = Sync.Encode("DEF_MANIFEST", {
  kind = "RAID_DEF",
  spells = { 51052, 196718 },
})
assert(manifestEncoded == "DEF_MANIFEST:RAID_DEF:51052,196718", "defensive manifests should encode their tracking kind")

local manifestType, manifestPayload = Sync.Decode(manifestEncoded)
assert(manifestType == "DEF_MANIFEST", "manifest decode should preserve message type")
assert(manifestPayload.kind == "RAID_DEF", "manifest decode should preserve the tracking kind")
assert(manifestPayload.spells[1] == 51052 and manifestPayload.spells[2] == 196718, "manifest decode should preserve spell ids")

local interruptManifestEncoded = Sync.Encode("INT_MANIFEST", {
  spells = { 6552 },
})
assert(interruptManifestEncoded == "INT_MANIFEST:6552", "interrupt manifests should encode the owned interrupt spell list")

local interruptManifestType, interruptManifestPayload = Sync.Decode(interruptManifestEncoded)
assert(interruptManifestType == "INT_MANIFEST", "interrupt manifest decode should preserve message type")
assert(interruptManifestPayload.spells[1] == 6552, "interrupt manifest decode should preserve spell ids")

local ccManifestEncoded = Sync.Encode("CC_MANIFEST", {
  spells = { 113724, 31661 },
})
assert(ccManifestEncoded == "CC_MANIFEST:113724,31661", "crowd control manifests should encode tracked spell lists")

local ccManifestType, ccManifestPayload = Sync.Decode(ccManifestEncoded)
assert(ccManifestType == "CC_MANIFEST", "crowd control manifest decode should preserve message type")
assert(ccManifestPayload.spells[1] == 113724 and ccManifestPayload.spells[2] == 31661, "crowd control manifest decode should preserve spell ids")

local encoded = Sync.Encode("INT", {
  spellID = 1766,
  cd = 15,
  remaining = 8,
})

local messageType, payload = Sync.Decode(encoded)
assert(encoded == "INT:1766:15:8", "interrupt payloads should include remaining time when available")
assert(messageType == "INT", "sync decode should preserve message type")
assert(payload.spellID == 1766, "sync decode should preserve spell ID")
assert(payload.cd == 15, "sync decode should preserve cooldown")
assert(payload.remaining == 8, "sync decode should preserve remaining time when available")

local registeredPrefix
local originalChatInfo = C_ChatInfo
local originalPartyCategoryInstance = LE_PARTY_CATEGORY_INSTANCE
local originalPartyCategoryHome = LE_PARTY_CATEGORY_HOME
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(prefix)
    registeredPrefix = prefix
    return true
  end,
}

assert(Sync.RegisterPrefix() == true, "sync prefix registration should return the API result")
assert(registeredPrefix == Sync.GetPrefix(), "sync should register the expected addon prefix")

local originalIsInGroup = IsInGroup
local originalIsInRaid = IsInRaid
local originalIsInInstance = IsInInstance
LE_PARTY_CATEGORY_INSTANCE = 1
LE_PARTY_CATEGORY_HOME = 2

IsInGroup = function(category)
  return category == nil or category == LE_PARTY_CATEGORY_INSTANCE
end
IsInRaid = function()
  return false
end
IsInInstance = function()
  return true
end
assert(Sync.GetDefaultChannel() == "INSTANCE_CHAT", "instance groups should use the instance addon channel")

IsInRaid = function()
  return true
end
IsInInstance = function()
  return true
end
assert(Sync.GetDefaultChannel() == "RAID", "raids should use the raid addon channel")

IsInRaid = function()
  return false
end
IsInInstance = function()
  return false
end
IsInGroup = function(category)
  return category == nil or category == LE_PARTY_CATEGORY_HOME
end
assert(Sync.GetDefaultChannel() == "PARTY", "party should be the default addon channel")

IsInGroup = function(category)
  return category == nil or category == LE_PARTY_CATEGORY_HOME or category == LE_PARTY_CATEGORY_INSTANCE
end
assert(Sync.GetDefaultChannel() == "PARTY", "home party should win when both home and instance categories report true")

local sendCalls = {}
local delayedCalls = {}
local originalTimer = C_Timer
C_Timer = {
  After = function(delay, callback)
    delayedCalls[#delayedCalls + 1] = delay
    callback()
  end,
}
C_ChatInfo = {
  SendAddonMessage = function(prefix, message, channel)
    if channel == "PARTY" then
      return false
    end
    sendCalls[#sendCalls + 1] = {
      prefix = prefix,
      message = message,
      channel = channel,
    }
    return true
  end,
}

IsInGroup = function(category)
  return false
end
assert(Sync.Send("INT", {
  spellID = 1766,
  cd = 15,
}) == false, "sync should not try to broadcast outside a group")

IsInGroup = function(category)
  return category == nil or category == LE_PARTY_CATEGORY_HOME or category == LE_PARTY_CATEGORY_INSTANCE
end
assert(Sync.Send("CC", {
  spellID = 51514,
  cd = 30,
}) == true, "sync send should return the chat API result")

assert(#sendCalls == 3, "sync send should issue the Kryos-style reliable triple broadcast on the fallback channel")
assert(delayedCalls[1] == 0.05 and delayedCalls[2] == 0.10, "sync send should schedule the staggered retry delays")
assert(sendCalls[1].prefix == Sync.GetPrefix(), "sync send should use the combat tracking prefix")
assert(sendCalls[1].channel == "INSTANCE_CHAT", "sync send should fall back to the instance channel if party broadcast fails")

local sentType, sentPayload = Sync.Decode(sendCalls[1].message)
assert(sentType == "CC", "sync send should encode the provided message type")
assert(sentPayload.spellID == 51514, "sync send should encode the spell ID")
assert(sentPayload.cd == 30, "sync send should encode the cooldown")

C_ChatInfo = originalChatInfo
C_Timer = originalTimer
IsInGroup = originalIsInGroup
IsInRaid = originalIsInRaid
IsInInstance = originalIsInInstance
LE_PARTY_CATEGORY_INSTANCE = originalPartyCategoryInstance
LE_PARTY_CATEGORY_HOME = originalPartyCategoryHome
