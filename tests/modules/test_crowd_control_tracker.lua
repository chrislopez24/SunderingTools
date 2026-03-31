_G.SunderingToolsCombatTrackSpellDB = dofile("Core/CombatTrackSpellDB.lua")
local Model = dofile("Modules/CrowdControlTrackerModel.lua")

local posX, posY = Model.GetDefaultPosition()
assert(posX == 220 and posY == -200, "crowd control tracker should have a separate default anchor")
assert(Model.GetDefaultFilterMode() == "ESSENTIALS", "crowd control tracker should default to essentials")
assert(Model.NormalizeFilterMode(nil) == "ESSENTIALS", "nil filters should normalize to essentials")
assert(Model.NormalizeFilterMode("all") == "ALL", "filter normalization should be case-insensitive")

local preview = Model.BuildPreviewBars()
assert(#preview >= 3, "preview should expose at least three sample CC bars")

assert(Model.FormatTimerText(11.6) == "12s", "crowd control timers should round to the nearest whole second like the reference tracker")
assert(Model.FormatTimerText(5.4) == "5s", "crowd control timers should use whole-second display for parity")

local essentials = Model.FilterTrackedEntries(preview, "ESSENTIALS")
local allEntries = Model.FilterTrackedEntries(preview, "ALL")

assert(#allEntries == #preview, "all filter should preserve all CC preview entries")
assert(#essentials < #allEntries, "essentials filter should narrow the preview set")

for _, entry in ipairs(essentials) do
  assert(entry.kind == "CC", "crowd control tracker should only keep CC entries")
  assert(entry.essential == true, "essentials filter should keep essential entries only")
end

local selfEntries = Model.GetEligibleCrowdControlEntries("MAGE", {
  includeAllKnown = true,
  isSpellKnown = function(spellID)
    return spellID == 118 or spellID == 113724
  end,
})

assert(#selfEntries == 1, "self registration should only include cooldown-based mage CC spells")
assert(selfEntries[1].spellID == 113724, "self registration should keep known cooldown-based mage CC spells")

local partyEntries = Model.GetEligibleCrowdControlEntries("MAGE", {
  includeAllKnown = false,
})

assert(#partyEntries == 1, "party auto-registration should use the primary class CC only")
assert(partyEntries[1].spellID == 113724, "party auto-registration should use the primary cooldown-based class CC")

local sorted = Model.SortBars({
  { key = "ready-paladin", name = "Paladin", spellID = 853, cd = 60, startTime = 0 },
  { key = "cooling-shaman", name = "Shaman", spellID = 51514, cd = 30, startTime = 90 },
  { key = "cooling-mage", name = "Mage", spellID = 113724, cd = 45, startTime = 80 },
}, 100)

assert(sorted[1].key == "cooling-mage", "longer remaining CC cooldowns should sort first like Kryos")
assert(sorted[2].key == "cooling-shaman", "shorter active cooldowns should sort after longer ones")
assert(sorted[3].key == "ready-paladin", "ready CC entries should sort after active cooldowns")

local trackerSource = readfile and readfile("Modules/CrowdControlTracker.lua") or nil
assert(
  trackerSource == nil or trackerSource:find("SunderingToolsPartyCrowdControlResolver", 1, true),
  "crowd control tracker should depend on the resolver"
)
assert(
  trackerSource == nil or trackerSource:find("ResolveAppliedCrowdControl", 1, true),
  "crowd control tracker should resolve normalized crowd control observations"
)
