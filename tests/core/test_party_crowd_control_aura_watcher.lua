local Watcher = dofile("Core/PartyCrowdControlAuraWatcher.lua")

local function newHarness(now)
  local events = {}
  local watcher = Watcher.New({
    getTime = function() return now or 100 end,
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

  return watcher, events
end

do
  local watcher, events = newHarness(100)

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
end

do
  local watcher, events = newHarness(100)
  local ok, err = pcall(function()
    watcher:ProcessAuraSnapshot("nameplate1", {
      {
        auraInstanceID = 11,
        spellId = "__SECRET__",
        sourceUnit = "__SECRET__",
        expirationTime = "__SECRET__",
      },
    })
  end)

  assert(ok, "secret expiration time should not error: " .. tostring(err))
  assert(#events == 1, "secret expiration snapshot should still emit apply event")
  assert(events[1].payload.remaining == 0, "secret expiration time should degrade to zero remaining")
  assert(events[1].payload.isCrowdControl == true, "secret classification should remain true")
end

do
  local watcher, events = newHarness(100)
  local snapshot = {
    {
      auraInstanceID = 12,
      spellId = 118,
      sourceUnit = "party1",
      expirationTime = 108,
    },
  }

  watcher:ProcessAuraSnapshot("nameplate1", snapshot)
  watcher:ProcessAuraSnapshot("nameplate1", snapshot)

  assert(#events == 1, "unchanged snapshot should not emit noisy cc updates")
end

do
  local watcher, events = newHarness(100)

  watcher:ProcessAuraSnapshot("nameplate1", {
    {
      auraInstanceID = 13,
      spellId = 118,
      sourceUnit = "party1",
      expirationTime = 108,
    },
  })
  watcher:ProcessAuraSnapshot("nameplate1", {})

  assert(#events == 2, "empty snapshot should emit removal for tracked cc")
  assert(events[2].event == "CC_REMOVED", "empty snapshot should emit cc removed")
  assert(events[2].payload.auraInstanceID == 13, "removed event should preserve aura instance id")
end

do
  local watcher, events = newHarness(100)

  watcher:ProcessAuraSnapshot("nameplate1", {
    {
      auraInstanceID = 14,
      spellId = 118,
      sourceUnit = "party1",
      expirationTime = 108,
    },
  })

  assert(type(watcher.RemoveUnit) == "function", "watcher should expose explicit unit cleanup")
  watcher:RemoveUnit("nameplate1")

  assert(#events == 2, "explicit cleanup should emit removal for recycled unit tokens")
  assert(events[2].event == "CC_REMOVED", "explicit cleanup should emit cc removed")
  assert(events[2].payload.auraInstanceID == 14, "cleanup removal should preserve aura instance id")
end
