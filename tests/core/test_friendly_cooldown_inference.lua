local Inference = dofile("Core/FriendlyCooldownInference.lua")

local now = 100
local events = {}
local inference = Inference.New({
  getTime = function()
    return now
  end,
  buildEvidenceSet = function()
    return { Cast = true }
  end,
  buildCastSnapshot = function()
    return { party1 = now }
  end,
  resolveEntry = function(spellID)
    if spellID == 48707 then
      return { spellID = 48707, cd = 60, kind = "DEF" }
    end
    return nil
  end,
  matchRule = function(_, tracked)
    if tracked.AuraTypes and tracked.AuraTypes.EXTERNAL_DEFENSIVE then
      return { spellID = 33206, cd = 180, kind = "DEF" }
    end
    return nil
  end,
})

inference:RegisterCallback(function(event, payload)
  events[#events + 1] = { event = event, payload = payload }
end)

inference:ProcessSnapshot("party1", {
  {
    AuraInstanceID = 11,
    SpellId = 48707,
    AuraTypes = { BIG_DEFENSIVE = true },
  },
}, {
  classToken = "DEATHKNIGHT",
  specID = 252,
})

now = 105
inference:ProcessSnapshot("party1", {}, {
  classToken = "DEATHKNIGHT",
  specID = 252,
})

assert(#events == 1, "inference should emit cooldowns when a tracked aura disappears")
assert(events[1].event == "COOLDOWN_INFERRED", "inference should emit normalized cooldown events")
assert(events[1].payload.resolved.spellID == 48707, "inference should prefer direct spell resolution when spell ids are visible")
assert(events[1].payload.readyAt == 160, "inference should compute readyAt from start time and resolved cooldown")

events = {}
now = 200
inference:ProcessSnapshot("party2", {
  {
    AuraInstanceID = 22,
    SpellId = nil,
    AuraTypes = { EXTERNAL_DEFENSIVE = true },
  },
}, {
  classToken = "PRIEST",
  specID = 256,
})
now = 204
inference:ProcessSnapshot("party2", {}, {
  classToken = "PRIEST",
  specID = 256,
})

assert(#events == 1, "inference should fall back to rule matching when spell ids are unavailable")
assert(events[1].payload.resolved.spellID == 33206, "rule-matched cooldowns should surface the canonical spell id")

print("ok")
