local SpellDB = dofile("Core/CombatTrackSpellDB.lua")

local function findSpell(entries, spellID)
  for _, entry in ipairs(entries) do
    if entry.spellID == spellID then
      return entry
    end
  end

  return nil
end

local ams = SpellDB.GetDefensiveSpell(48707)
assert(ams ~= nil, "Anti-Magic Shell should be registered as a defensive spell")
assert(ams.kind == "DEF", "personal defensives should use DEF kind")
assert(ams.auraSpellID == 48707, "Anti-Magic Shell should expose its visible aura spell")

local trackedAms = SpellDB.GetTrackedSpell(48707)
assert(trackedAms ~= nil and trackedAms.kind == "DEF", "tracked spell lookup should include defensive entries")

local amsWithCooldownReduction = SpellDB.ResolveLocalDefensiveSpell(48707, 252, function(spellID)
  return spellID == 205727
end)
assert(amsWithCooldownReduction ~= nil, "local defensive resolution should keep Anti-Magic Shell addressable")
assert(amsWithCooldownReduction.cd == 40, "local defensive resolution should apply known talent cooldown reductions for Anti-Magic Shell")

local amz = SpellDB.GetDefensiveSpell(51052)
assert(amz ~= nil, "Anti-Magic Zone should be registered as a defensive spell")
assert(amz.kind == "RAID_DEF", "Anti-Magic Zone should be registered as a raid defensive")
assert(SpellDB.GetDefensiveSpell(145629) ~= nil, "Anti-Magic Zone should also resolve through its visible aura spell")
assert(SpellDB.GetDefensiveSpell(145629).spellID == 51052, "Anti-Magic Zone aura aliases should normalize back to the canonical cast spell")

local dkSpells = SpellDB.GetDefensiveSpellsForClass("DEATHKNIGHT")
assert(#dkSpells >= 9, "death knight party-frame defensives should import the OmniCD defensive catalog")
assert(findSpell(dkSpells, 48707) ~= nil, "death knight defensives should include Anti-Magic Shell")
assert(findSpell(dkSpells, 48792) ~= nil, "death knight defensives should include Icebound Fortitude")
assert(findSpell(dkSpells, 55233) ~= nil, "death knight defensives should include Vampiric Blood")
assert(findSpell(dkSpells, 51052) == nil, "party-frame defensive lists should not include raid defensives")
assert(findSpell(dkSpells, 194679) ~= nil, "death knight defensives should include Rune Tap from OmniCD")
assert(SpellDB.GetDefensiveSpell(114556) ~= nil, "the global defensive DB should still retain passive/proc defensives")
assert(findSpell(dkSpells, 114556) == nil, "passive/proc defensives should stay out of default class manifests until they are trackable")

local dkRaidSpells = SpellDB.GetRaidDefensiveSpellsForClass("DEATHKNIGHT")
assert(#dkRaidSpells == 1, "death knight raid defensives should stay in the raid-only helper")
assert(findSpell(dkRaidSpells, 51052) ~= nil, "raid defensive lists should include Anti-Magic Zone")

local amzWithAssimilation = SpellDB.ResolveLocalDefensiveSpell(51052, 252, function(spellID)
  return spellID == 374383
end)
assert(amzWithAssimilation ~= nil, "local defensive resolution should keep Anti-Magic Zone addressable")
assert(amzWithAssimilation.cd == 180, "local defensive resolution should apply known talent cooldown reductions for Anti-Magic Zone")

local ironbarkWithStonebark = SpellDB.ResolveLocalDefensiveSpell(102342, 105, function(spellID)
  return spellID == 382552
end)
assert(ironbarkWithStonebark ~= nil, "local defensive resolution should keep Ironbark addressable")
assert(ironbarkWithStonebark.cd == 70, "local defensive resolution should apply Stonebark-style cooldown reductions for Ironbark")

local druidSpells = SpellDB.GetDefensiveSpellsForClass("DRUID")
local barkskin = findSpell(druidSpells, 22812)
assert(barkskin ~= nil, "druid defensives should include Barkskin")
assert(barkskin.cd == 60, "table-valued cooldowns should resolve to their default/base cooldown")
assert(type(barkskin.cdBySpec) == "table" and barkskin.cdBySpec[104] == 45, "spec-specific cooldown metadata should be preserved")
assert(findSpell(druidSpells, 102342) ~= nil, "druid defensives should include Ironbark")
assert(SpellDB.ResolveDefensiveSpell(22812, 104).cd == 45, "resolving a defensive for a known spec should apply spec-specific cooldowns")

local paladinSpells = SpellDB.GetDefensiveSpellsForClass("PALADIN")
assert(findSpell(paladinSpells, 6940) ~= nil, "paladin defensives should include Blessing of Sacrifice")
assert(findSpell(paladinSpells, 1022) ~= nil, "paladin defensives should include Blessing of Protection")
assert(findSpell(paladinSpells, 204018) ~= nil, "paladin defensives should include Blessing of Spellwarding")

local paladinRaidSpells = SpellDB.GetRaidDefensiveSpellsForClass("PALADIN")
assert(findSpell(paladinRaidSpells, 31821) ~= nil, "paladin raid defensives should include Aura Mastery")

local auraMasteryWithUnwaveringSpirit = SpellDB.ResolveLocalDefensiveSpell(31821, 65, function(spellID)
  return spellID == 392911
end)
assert(auraMasteryWithUnwaveringSpirit ~= nil, "local defensive resolution should keep Aura Mastery addressable")
assert(auraMasteryWithUnwaveringSpirit.cd == 150, "local defensive resolution should apply common Holy Paladin cooldown reductions to Aura Mastery")

local priestRaidSpells = SpellDB.GetRaidDefensiveSpellsForClass("PRIEST")
assert(findSpell(priestRaidSpells, 62618) ~= nil, "priest raid defensives should include Power Word: Barrier")
assert(findSpell(priestRaidSpells, 64843) ~= nil, "priest raid defensives should include Divine Hymn")

local warriorSpells = SpellDB.GetDefensiveSpellsForClass("WARRIOR")
local shieldBlock = findSpell(warriorSpells, 2565)
assert(shieldBlock ~= nil, "warrior defensives should include Shield Block")
assert(shieldBlock.charges == 1, "table-valued charges should resolve to a base charge count")
assert(type(shieldBlock.chargesBySpec) == "table" and shieldBlock.chargesBySpec[73] == 2, "spec-specific charge metadata should be preserved")
assert(SpellDB.ResolveDefensiveSpell(2565, 73).charges == 2, "resolving a defensive for a known spec should apply spec-specific charges")

local warriorRaidSpells = SpellDB.GetRaidDefensiveSpellsForClass("WARRIOR")
assert(findSpell(warriorRaidSpells, 97462) ~= nil, "warrior raid defensives should include Rallying Cry")

local rogueSpells = SpellDB.GetDefensiveSpellsForClass("ROGUE")
assert(SpellDB.GetDefensiveSpell(31230) ~= nil, "rogue passive defensives should remain addressable in the DB")
assert(findSpell(rogueSpells, 31230) == nil, "rogue passive/proc defensives should be suppressed from default manifests")

local monkKnownSpells = SpellDB.GetKnownDefensiveSpellsForClass("MONK", 268, { 115203, 119582 })
assert(findSpell(monkKnownSpells, 115203) ~= nil, "known defensive helpers should preserve learned Monk defensives")
assert(findSpell(monkKnownSpells, 119582) ~= nil, "known defensive helpers should preserve learned Brewmaster defensives")
assert(findSpell(monkKnownSpells, 122470) == nil, "known defensive helpers should not advertise spec-mismatched Monk defensives")

do
  local secretSpellID = {}
  local originalIsSecretValue = _G.issecretvalue
  _G.issecretvalue = function(value)
    return value == secretSpellID
  end

  local ok, result = pcall(SpellDB.GetDefensiveSpell, secretSpellID)
  assert(ok, "secret spell ids should not error when resolving defensive aliases")
  assert(result == nil, "secret spell ids should resolve to nil defensive entries")

  _G.issecretvalue = originalIsSecretValue
end
