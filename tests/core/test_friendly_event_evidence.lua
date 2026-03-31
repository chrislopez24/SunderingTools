local Evidence = dofile("Core/FriendlyEventEvidence.lua")

local now = 100

_G.C_UnitAuras = {
  IsAuraFilteredOutByInstanceID = function(_, auraInstanceID, filter)
    if filter == "HARMFUL" then
      return auraInstanceID ~= 55
    end
    return true
  end,
}

local evidence = Evidence.New({
  getTime = function()
    return now
  end,
  castWindow = 0.2,
  evidenceWindow = 0.2,
})

evidence:RecordSpellcastSucceeded("party1", 100.0)
evidence:RecordAuraUpdate("party1", {
  addedAuras = {
    { auraInstanceID = 55 },
  },
}, 100.05)
evidence:RecordAbsorbChanged("party1", 100.1)
evidence:RecordUnitFlags("party1", false, 100.15)

local set = evidence:BuildEvidenceSet("party1", 100.16)
assert(set.Cast == true, "evidence builder should preserve recent cast evidence")
assert(set.Debuff == true, "evidence builder should preserve recent harmful-aura evidence")
assert(set.Shield == true, "evidence builder should preserve recent absorb evidence")
assert(set.UnitFlags == true, "evidence builder should preserve recent unit-flags evidence")

evidence:RecordUnitFlags("party1", true, 100.17)
local feignSet = evidence:BuildEvidenceSet("party1", 100.18)
assert(feignSet.FeignDeath == true, "feign-death transitions should be tracked as separate evidence")
assert(feignSet.UnitFlags == nil, "feign-death evidence should suppress plain unit-flags evidence")

local snapshot = evidence:BuildCastSnapshot()
assert(snapshot.party1 == 100.0, "cast snapshot should include recent cast timestamps")

evidence:Reset()
assert(evidence:BuildEvidenceSet("party1", 100.2) == nil, "reset should clear all evidence state")

print("ok")
