local Fallback = dofile("Core/PartyDefensiveAuraFallback.lua")

local events = {}
local fallback = Fallback.New({
  getTime = function() return 300 end,
  resolveSpell = function(spellID)
    if spellID == 48707 then
      return { spellID = 48707, kind = "DEF", cd = 60, classToken = "DEATHKNIGHT" }
    end

    return nil
  end,
})

fallback:RegisterCallback(function(payload)
  events[#events + 1] = payload
end)

fallback:ProcessAuraRemoved("party1", {
  spellID = 48707,
  source = "aura",
  startTime = 290,
  endTime = 300,
})

assert(#events == 1, "defensive fallback should emit a cooldown record when a tracked defensive ends")
assert(events[1].spellID == 48707, "defensive fallback should preserve spell id")
assert(events[1].baseCd == 60, "defensive fallback should derive cooldown from spell db")
assert(events[1].startTime == 300, "defensive fallback cooldown should start from aura end time")
assert(events[1].readyAt == 360, "defensive fallback cooldown should extend to cooldown completion")
