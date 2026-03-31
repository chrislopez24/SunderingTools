_G.SunderingToolsCombatTrackSpellDB = dofile("Core/CombatTrackSpellDB.lua")
local Rules = dofile("Core/FriendlyTrackingRules.lua")

local ams = Rules.ResolveDefensive(48707, 252)
assert(ams ~= nil, "rules should resolve direct defensive entries")
assert(ams.spellID == 48707, "rules should preserve the canonical defensive spell id")
assert(type(ams.cd) == "number" and ams.cd > 0, "rules should preserve cooldown data")

local matched = Rules.MatchDefensive({
  classToken = "PALADIN",
  specID = 65,
}, {
  AuraTypes = { EXTERNAL_DEFENSIVE = true },
  SpellId = 1022,
}, 8.0)
assert(matched ~= nil, "rules should match external defensive auras")
assert(matched.spellID == 1022, "rules should resolve Blessing of Protection from direct aura spell ids")

local interrupt = Rules.ResolveInterrupt(6552, 71, "WARRIOR")
assert(interrupt ~= nil and interrupt.spellID == 6552, "rules should resolve class/spec interrupts")

print("ok")
