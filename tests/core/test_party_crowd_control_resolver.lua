local Resolver = dofile("Core/PartyCrowdControlResolver.lua")

local resolver = Resolver.New({
  getTime = function() return 200 end,
  getCooldownForSpell = function(spellID)
    if spellID == 118 then
      return 30
    end

    if spellID == 113724 then
      return 45
    end

    return 0
  end,
})

local high = resolver:ResolveAppliedCrowdControl({
  targetUnit = "nameplate1",
  spellID = 118,
  sourceUnit = "party1",
  source = "aura",
})

assert(high ~= nil, "resolver should create a cc cooldown record for a usable aura")
assert(high.source == "aura", "resolver should preserve the source label")
assert(high.confidence == "high", "resolver should mark direct aura attribution high confidence")
assert(high.ownerUnit == "party1", "resolver should preserve the owner unit")
assert(high.startTime == 200, "resolver should start cooldowns at application time")
assert(high.endTime == 230, "resolver should derive cooldown end from base cooldown")
assert(high.baseCd == 30, "resolver should preserve the base cooldown")

local medium = resolver:ResolveAppliedCrowdControl({
  targetUnit = "nameplate2",
  ownerUnit = "party2",
  spellID = 113724,
  source = "correlated",
})

assert(medium ~= nil, "resolver should support correlation-backed cooldown records")
assert(medium.source == "correlated", "resolver should preserve correlated source labels")
assert(medium.confidence == "medium", "correlated attribution should be medium confidence")
assert(medium.ownerUnit == "party2", "correlated attribution should preserve owner unit")
assert(medium.endTime == 245, "correlated attribution should use the resolved cooldown")

local rejected = resolver:ResolveAppliedCrowdControl({
  targetUnit = "nameplate1",
  spellID = nil,
  source = "aura",
})

assert(rejected == nil, "resolver should reject unidentifiable crowd control cooldowns")

local noCooldown = resolver:ResolveAppliedCrowdControl({
  targetUnit = "nameplate1",
  spellID = 999999,
  sourceUnit = "party1",
  source = "aura",
})

assert(noCooldown == nil, "resolver should reject spells without a tracked cooldown")
