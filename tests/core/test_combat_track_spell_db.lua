local SpellDB = dofile("Core/CombatTrackSpellDB.lua")

local intEntry = SpellDB.GetInterruptForClass("MAGE")
assert(intEntry.spellID == 2139, "mage interrupt should resolve to Counterspell")
assert(intEntry.kind == "INT", "interrupt entries should be tagged as INT")
assert(intEntry.cd == 24, "mage class interrupt should match Kryos at 24 seconds")

local specEntry = SpellDB.GetInterruptForSpec(264)
assert(specEntry.spellID == 57994, "restoration shaman should resolve to Wind Shear")
assert(specEntry.role == "HEALER", "spec interrupt metadata should preserve role")
assert(specEntry.cd == 30, "spec interrupt metadata should preserve cooldown")

local windShear = SpellDB.GetTrackedSpell(57994)
assert(windShear.kind == "INT", "Wind Shear should be tracked as an interrupt")
assert(windShear.cd == nil, "tracked interrupt entries should not expose a collapsed cooldown when specs differ")
assert(type(windShear.variants) == "table", "spec-varying interrupts should expose explicit variants")
assert(windShear.variants[262].cd == 12, "elemental Wind Shear should preserve its cooldown variant")
assert(windShear.variants[263].cd == 12, "enhancement Wind Shear should preserve its cooldown variant")
assert(windShear.variants[264].cd == 30, "restoration Wind Shear should preserve its cooldown variant")

local quell = SpellDB.GetTrackedSpell(351338)
assert(quell.kind == "INT", "Quell should be tracked as an interrupt")
assert(quell.cd == nil, "tracked interrupt entries should not expose a collapsed cooldown when variants differ")
assert(type(quell.variants) == "table", "Quell should expose explicit cooldown variants")
assert(quell.variants[1467].cd == 20, "devastation Quell should preserve its cooldown variant")
assert(quell.variants[1473].cd == 18, "augmentation Quell should preserve its cooldown variant")

assert(SpellDB.ResolveTrackedSpellID(97493) == 47528, "Mind Freeze event spell IDs should resolve to the tracked interrupt spell")
local mindFreezeAlias = SpellDB.GetTrackedSpell(97493)
assert(mindFreezeAlias.spellID == 47528, "interrupt alias lookups should return the canonical tracked spell")

local demoLockInterrupt = SpellDB.GetInterruptForSpec(266)
assert(demoLockInterrupt.cd == 24, "demo warlock interrupt should match Kryos at 24 seconds")

local augInterrupt = SpellDB.GetInterruptForSpec(1473)
assert(augInterrupt.cd == 18, "augmentation evoker interrupt should match Kryos at 18 seconds")

local priestInterrupt = SpellDB.GetInterruptForClass("PRIEST")
assert(priestInterrupt == nil, "priest should not auto-register an interrupt by class")

local healerPaladinInterrupt, healerPaladinSpecID, healerPaladinReason = SpellDB.ResolveInterruptByContext(nil, "PALADIN", "HEALER", nil)
assert(healerPaladinInterrupt == nil, "holy paladin should be omitted from class-based interrupt auto-registration")
assert(healerPaladinSpecID == 0, "suppressed healer registrations should not resolve a fallback spec")
assert(healerPaladinReason == "HEALER_SUPPRESSED", "holy paladin suppression should explain the Kryos-style omission")

local restoShamanInterrupt, restoShamanSpecID = SpellDB.ResolveInterruptByContext(nil, "SHAMAN", "HEALER", nil)
assert(restoShamanInterrupt.spellID == 57994, "restoration shaman should keep Wind Shear when spec is unknown")
assert(restoShamanSpecID == 264, "restoration shaman fallback should resolve to the healer variant")
assert(restoShamanInterrupt.cd == 30, "restoration shaman fallback should preserve the healer cooldown")

local mistweaverInterrupt, mistweaverSpecID, mistweaverReason = SpellDB.ResolveInterruptByContext(nil, "MONK", "HEALER", 0)
assert(mistweaverInterrupt == nil, "mistweaver monk should be omitted from class-based interrupt auto-registration")
assert(mistweaverSpecID == 0, "mistweaver suppression should not resolve an interrupt spec")
assert(mistweaverReason == "HEALER_SUPPRESSED", "mistweaver suppression should follow the healer omission rule")

local shadowPriestInterrupt, shadowPriestSpecID = SpellDB.ResolveInterruptByContext(258, "PRIEST", "DAMAGER", nil)
assert(shadowPriestInterrupt.spellID == 15487, "known interrupt specs should still resolve even for omitted classes")
assert(shadowPriestSpecID == 258, "known interrupt specs should preserve the exact priest spec")

local autoRestoShamanInterrupt, autoRestoShamanSpecID = SpellDB.ResolveAutoInterruptByContext(264, "SHAMAN", "HEALER", nil)
assert(autoRestoShamanInterrupt.spellID == 57994, "auto resolution should keep restoration shaman Wind Shear")
assert(autoRestoShamanInterrupt.cd == 30, "auto resolution should keep the Kryos resto shaman cooldown")
assert(autoRestoShamanSpecID == 264, "auto resolution should resolve restoration shaman to the healer variant")

local autoShadowPriestInterrupt, autoShadowPriestSpecID, autoShadowPriestReason = SpellDB.ResolveAutoInterruptByContext(258, "PRIEST", "DAMAGER", nil)
assert(autoShadowPriestInterrupt == nil, "auto resolution should omit priest to match Kryos class auto-registration")
assert(autoShadowPriestSpecID == 0, "auto priest omission should not expose a fallback spec")
assert(autoShadowPriestReason == "CLASS_OMITTED", "auto priest omission should explain the Kryos parity rule")

local autoSurvivalInterrupt, autoSurvivalSpecID = SpellDB.ResolveAutoInterruptByContext(255, "HUNTER", "DAMAGER", nil)
assert(autoSurvivalInterrupt.spellID == 147362, "auto resolution should use the Kryos hunter primary interrupt")
assert(autoSurvivalInterrupt.cd == 24, "auto resolution should keep the Kryos hunter primary cooldown")
assert(autoSurvivalSpecID == 253, "auto resolution should use the class primary fallback spec for hunter")

local ccSpell = SpellDB.GetTrackedSpell(51514)
assert(ccSpell.kind == "CC", "Hex should be tracked as CC")
assert(ccSpell.name == "Hex", "CC lookup should expose spell name")
assert(ccSpell.essential == true, "Hex should be part of the M+ essentials view")

assert(SpellDB.GetTrackedSpell(118) == nil, "zero-cooldown Polymorph should not be tracked in the cooldown DB")
assert(SpellDB.GetTrackedSpell(5782) == nil, "zero-cooldown Fear should not be tracked in the cooldown DB")
assert(SpellDB.GetTrackedSpell(360806) == nil, "zero-cooldown Sleep Walk should not be tracked in the cooldown DB")

local warriorPrimaryCC = SpellDB.GetPrimaryCrowdControlForClass("WARRIOR")
assert(warriorPrimaryCC.spellID == 5246, "warrior primary CC should stay on Intimidating Shout")
assert(warriorPrimaryCC.cd == 75, "warrior primary CC cooldown should match the latest Kryos data")

local evokerPrimaryCC = SpellDB.GetPrimaryCrowdControlForClass("EVOKER")
assert(evokerPrimaryCC.spellID == 370665, "evoker primary CC should fall back to the first cooldown-based spell when no essential is marked")
assert(evokerPrimaryCC.essential ~= true, "evoker fallback CC should prove primary selection works without an essential flag")

local disableSpell = SpellDB.GetTrackedSpell(116095)
assert(disableSpell == nil, "Disable should no longer be tracked as crowd control when matching the latest Kryos data")

local huntSpell = SpellDB.GetTrackedSpell(370965)
assert(huntSpell and huntSpell.kind == "CC", "The Hunt should now be tracked as crowd control to match the latest Kryos data")
assert(huntSpell.cd == 90, "The Hunt should preserve the latest Kryos cooldown")

local ccList = SpellDB.GetCrowdControlForClass("PALADIN", "DAMAGER")
assert(#ccList >= 2, "paladin should expose a broad CC list")
assert(ccList[1].kind == "CC", "class CC lists should contain CC entries only")

local allSpells = SpellDB.FilterCrowdControl("ALL")
local essentials = SpellDB.FilterCrowdControl("ESSENTIALS")

assert(#allSpells > #essentials, "all CC should be wider than essentials")

for _, spell in ipairs(essentials) do
  assert(spell.essential == true, "essential filter should only return essential spells")
  assert((spell.cd or 0) > 0, "essential filter should only return cooldown-based crowd control spells")
end
