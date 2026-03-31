local Watcher = dofile("Core/PartyCrowdControlAuraWatcher.lua")

local events = {}
local watcher = Watcher.New({
  getTime = function() return 100 end,
  isSecretValue = function(value)
    return value == "__SECRET__" or value == "__SECRET_CC__"
  end,
  isCrowdControl = function(aura)
    if aura.spellId == 118 then
      return true
    end

    if aura.spellId == "__SECRET__" then
      return "__SECRET_CC__"
    end

    return false
  end,
})

watcher:RegisterCallback(function(event, payload)
  events[#events + 1] = { event = event, payload = payload }
end)

watcher:ProcessAuraSnapshot("nameplate1", {
  {
    auraInstanceID = 9,
    spellId = 118,
    sourceUnit = "party1",
    expirationTime = 108,
  },
})

assert(#events == 1, "cc watcher should emit one apply event")
assert(events[1].event == "CC_APPLIED", "cc watcher should emit apply event")
assert(events[1].payload.unitToken == "nameplate1", "cc watcher should preserve target unit")
assert(events[1].payload.spellID == 118, "cc watcher should preserve usable spell ids")
assert(events[1].payload.remaining == 8, "cc watcher should derive remaining duration from expiration time")

watcher:ProcessAuraSnapshot("nameplate1", {
  {
    auraInstanceID = 10,
    spellId = "__SECRET__",
    sourceUnit = "__SECRET__",
    expirationTime = 104,
  },
})

assert(events[2].payload.spellID == nil, "secret spell ids should not be exposed")
assert(events[2].payload.sourceUnit == nil, "secret source units should not be exposed")
assert(events[2].payload.isCrowdControl == true, "classified crowd control should survive secret identity loss")
