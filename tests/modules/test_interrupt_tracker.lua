local SpellDB = dofile("Core/CombatTrackSpellDB.lua")
local Model = dofile("Modules/InterruptTrackerModel.lua")

local sorted = Model.SortBars({
  { key = "dps-cooling", role = "DAMAGER", specID = 72, cd = 15, startTime = 90 },
  { key = "tank-ready", role = "TANK", specID = 73, cd = 15, startTime = 0 },
  { key = "healer-ready", role = "HEALER", specID = 264, cd = 30, startTime = 0 },
}, 100)

assert(sorted[1].key == "tank-ready", "ready tank should sort first")
assert(sorted[2].key == "healer-ready", "ready healer should sort after tank")
assert(sorted[3].key == "dps-cooling", "cooling bar should sort after ready bars")

local preview = Model.BuildPreviewBars()
assert(#preview >= 3, "preview should expose at least three sample bars")

local wholeSecondsText, wholeSecondsValue = Model.FormatTimerText(11.6)
assert(wholeSecondsText == "12s", "interrupt timers should round to the nearest whole second like the reference tracker")
assert(wholeSecondsValue == 12, "interrupt timer cache value should match the rendered whole-second text")

local subSixText, subSixValue = Model.FormatTimerText(5.4)
assert(subSixText == "5s", "interrupt timers should stay on whole-second display under six seconds for parity")
assert(subSixValue == 5, "interrupt sub-six timer cache should match the rendered text")

local interrupt, specID = Model.GetInterruptData(0, "MAGE")
assert(specID == 62, "class fallback should resolve to the default mage interrupt spec")
assert(interrupt.spellID == 2139, "class fallback should use counterspell data")
assert(interrupt == SpellDB.GetInterruptForSpec(specID), "interrupt metadata should come from the shared spell database")
