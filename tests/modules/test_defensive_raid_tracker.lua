local SpellDB = dofile("Core/CombatTrackSpellDB.lua")
local Model = dofile("Modules/DefensiveRaidTrackerModel.lua")

local posX, posY = Model.GetDefaultPosition()
assert(posX == 0 and posY == -260, "raid defensive tracker should use its own default anchor")

local preview = Model.BuildPreviewBars()
assert(#preview >= 3, "raid defensive tracker should expose at least three preview bars")

for _, entry in ipairs(preview) do
  assert(entry.kind == "RAID_DEF", "preview bars should be raid defensives")
  assert(entry.spellID ~= nil, "preview bars should keep spell ids for icon rendering")
end

local text, rounded = Model.FormatTimerText(31.6)
assert(text == "32s", "raid defensive timers should round to the nearest whole second")
assert(rounded == 32, "rounded timer cache should match the rendered timer text")

local dkEntries = Model.GetAvailableSpells("DEATHKNIGHT")
local spellDBEntries = SpellDB.GetRaidDefensiveSpellsForClass("DEATHKNIGHT")
assert(#dkEntries >= 1, "death knights should expose raid defensive entries")
assert(dkEntries[1].kind == "RAID_DEF", "available entries should come from the raid defensive catalog")
assert(#dkEntries == #spellDBEntries, "model should expose the full raid defensive catalog for the class")
assert(dkEntries[1].spellID == spellDBEntries[1].spellID, "model should preserve raid defensive spell ids from the shared catalog")
assert(dkEntries[1].name == spellDBEntries[1].name, "model should preserve raid defensive names from the shared catalog")
assert(dkEntries[1].cd == spellDBEntries[1].cd, "model should preserve raid defensive cooldowns from the shared catalog")
