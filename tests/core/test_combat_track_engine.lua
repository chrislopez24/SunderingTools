local Engine = dofile("Core/CombatTrackEngine.lua")

local engine = Engine.New()

local expected = engine:RegisterExpectedEntry({
  key = "mage-guid:2139",
  playerGUID = "mage-guid",
  playerName = "Mage",
  classToken = "MAGE",
  unitToken = "party1",
  spellID = 2139,
  kind = "INT",
  baseCd = 24,
})

assert(expected.source == "auto", "expected entries should default to auto confidence")
assert(expected.playerGUID == "mage-guid", "expected entries should preserve identity metadata")

local kinds = engine:GetEntriesByKind("INT")
assert(#kinds == 1 and kinds[1].key == "mage-guid:2139", "GetEntriesByKind should filter the tracked list")

engine:RegisterExpectedEntry({
  key = "shaman-guid:51514",
  playerGUID = "shaman-guid",
  playerName = "Shaman",
  classToken = "SHAMAN",
  unitToken = "party2",
  spellID = 51514,
  kind = "CC",
  baseCd = 30,
  essential = true,
})

local ccEntries = engine:GetEntriesByKind("CC")
assert(#ccEntries == 1 and ccEntries[1].spellID == 51514, "GetEntriesByKind should return only matching kinds")

engine:ApplyCorrelatedCast("mage-guid", 2139, 100, 124)
local entry = engine:GetEntry("mage-guid:2139")
assert(entry.source == "correlated", "correlated casts should upgrade auto entries")
assert(entry.startTime == 100 and entry.readyAt == 124, "correlated casts should stamp cooldown timing")

engine:RegisterExpectedEntry({
  key = "mage-guid:2139",
  playerGUID = "mage-guid",
  playerName = "Mage Renamed",
  classToken = "MAGE",
  unitToken = "party1",
  spellID = 2139,
  kind = "INT",
  baseCd = 24,
})

entry = engine:GetEntry("mage-guid:2139")
assert(entry.playerName == "Mage Renamed", "expected entry registration should upsert metadata")
assert(entry.source == "correlated", "expected entry registration should not downgrade confirmed state")

engine:ApplySyncCast("mage-guid", 2139, 101, 125)
entry = engine:GetEntry("mage-guid:2139")
assert(entry.source == "sync", "sync casts should override correlated state")
assert(entry.startTime == 101 and entry.readyAt == 125, "sync casts should update timing state")

engine:ApplyCorrelatedCast("mage-guid", 2139, 102, 126)
entry = engine:GetEntry("mage-guid:2139")
assert(entry.source == "sync", "lower-confidence casts should not override sync state")
assert(entry.startTime == 101 and entry.readyAt == 125, "lower-confidence casts should not change timing state")

engine:ApplySelfCast("mage-guid", 2139, 103, 127)
entry = engine:GetEntry("mage-guid:2139")
assert(entry.source == "self", "self casts should override sync state")
assert(entry.startTime == 103 and entry.readyAt == 127, "self casts should update timing state")

local warrior = engine:RegisterExpectedEntry({
  key = "warrior-guid:6552",
  playerGUID = "warrior-guid",
  playerName = "Warrior",
  classToken = "WARRIOR",
  unitToken = "party3",
  spellID = 6552,
  kind = "INT",
  baseCd = 15,
})

assert(warrior.source == "auto", "new expected entries should remain auto until observed")
engine:RecordPartyCast("party1", 200)
engine:RecordPartyCast("party3", 200.3)
local resolved = engine:ResolveInterruptWindow(200.32, 0.5)
assert(resolved ~= nil, "a clean single-candidate window should resolve")
assert(resolved.key == "warrior-guid:6552", "resolved windows should pick the closest legal candidate")
assert(resolved.source == "correlated", "clean best matches should become correlated casts")
assert(resolved.startTime == 200.32 and resolved.readyAt == 215.32, "resolved windows should apply cooldown timing from the interrupt event")

engine:RecordPartyCast("party1", 250)
engine:RecordPartyCast("party3", 250.03)
local ambiguousHistorical = engine:ResolveInterruptWindow(250.05, 0.5)
assert(ambiguousHistorical == nil, "ambiguous close candidates should be dropped even when one entry has prior timing history")
assert(engine:GetEntry("mage-guid:2139").source == "self", "ambiguity refusal should not disturb stronger existing state")
assert(engine:GetEntry("warrior-guid:6552").startTime == 200.32 and engine:GetEntry("warrior-guid:6552").readyAt == 215.32, "ambiguity refusal should not advance a historically correlated cooldown")

local rogue = engine:RegisterExpectedEntry({
  key = "rogue-guid:1766",
  playerGUID = "rogue-guid",
  playerName = "Rogue",
  classToken = "ROGUE",
  unitToken = "party4",
  spellID = 1766,
  kind = "INT",
  baseCd = 15,
})

assert(rogue.source == "auto", "fresh expected entries should remain auto until observed")
local paladin = engine:RegisterExpectedEntry({
  key = "paladin-guid:96231",
  playerGUID = "paladin-guid",
  playerName = "Paladin",
  classToken = "PALADIN",
  unitToken = "party5",
  spellID = 96231,
  kind = "INT",
  baseCd = 15,
})

assert(paladin.source == "auto", "additional expected entries should remain auto until observed")
engine:RecordPartyCast("party5", 300)
engine:RecordPartyCast("party4", 300.04)
assert(engine:ResolveInterruptWindow(300.05, 0.5) == nil, "ambiguous closest-candidate windows should refuse resolution")
assert(engine:GetEntry("rogue-guid:1766").source == "auto", "ambiguous windows should not advance cooldown state")
assert(engine:GetEntry("paladin-guid:96231").source == "auto", "ambiguous windows should leave all fresh candidates unconfirmed")
assert(engine:ResolveInterruptWindow(300.51, 0.5) == nil, "ambiguous candidates should be consumed so they cannot resolve on a later event")
assert(engine:GetEntry("rogue-guid:1766").source == "auto", "consumed ambiguous candidates should leave later state unchanged")
assert(engine:GetEntry("paladin-guid:96231").source == "auto", "consumed ambiguous candidates should not be recycled into a later match")

local druid = engine:RegisterExpectedEntry({
  key = "druid-guid:106839",
  playerGUID = "druid-guid",
  playerName = "Druid",
  classToken = "DRUID",
  unitToken = "party6",
  spellID = 106839,
  kind = "INT",
  baseCd = 15,
})

assert(druid.source == "auto", "new units should register as auto before correlation")
engine:RecordPartyCast("party6", 400)
local firstCorrelation = engine:ResolveInterruptWindow(400.1, 0.5)
assert(firstCorrelation ~= nil and firstCorrelation.key == "druid-guid:106839", "unit-only watchers should resolve through the expected interrupt entry")
assert(firstCorrelation.startTime == 400.1 and firstCorrelation.readyAt == 415.1, "first correlation should start the cooldown once")

engine:RecordPartyCast("party6", 400.12)
local duplicateCorrelation = engine:ResolveInterruptWindow(400.18, 0.5)
assert(duplicateCorrelation == nil, "duplicate correlations inside the suppression window should be ignored")

local druidEntry = engine:GetEntry("druid-guid:106839")
assert(druidEntry.source == "correlated", "duplicate suppression should preserve the confirmed correlated state")
assert(druidEntry.startTime == 400.1 and druidEntry.readyAt == 415.1, "duplicate suppression should not advance cooldown timing twice")

local demonHunter = engine:RegisterExpectedEntry({
  key = "dh-guid:183752",
  playerGUID = "dh-guid",
  playerName = "DH",
  classToken = "DEMONHUNTER",
  unitToken = "party7",
  spellID = 183752,
  kind = "INT",
  cd = 15,
})

assert(demonHunter.source == "auto", "cd-shaped entries should still register as auto expectations")
engine:ApplySyncCast("dh-guid", 183752, 500, nil)
local demonHunterEntry = engine:GetEntry("dh-guid:183752")
assert(demonHunterEntry.source == "sync", "direct casts should still honor precedence for cd-shaped entries")
assert(demonHunterEntry.startTime == 500 and demonHunterEntry.readyAt == 515, "cd-shaped entries should derive readyAt when baseCd is absent")

local monk = engine:RegisterExpectedEntry({
  key = "monk-guid:116705",
  playerGUID = "monk-guid",
  playerName = "Monk",
  classToken = "MONK",
  unitToken = "party8",
  spellID = 116705,
  kind = "INT",
  cd = 15,
})

assert(monk.source == "auto", "additional cd-shaped expectations should register cleanly")
engine:RecordPartyCast("party8", 600)
local nilObservedCorrelation = engine:ResolveInterruptWindow(nil, 0.5)
assert(nilObservedCorrelation ~= nil and nilObservedCorrelation.key == "monk-guid:116705", "nil observedAt should still allow a clean single-candidate correlation")
assert(nilObservedCorrelation.startTime == 600 and nilObservedCorrelation.readyAt == 615, "nil observedAt should fall back to the watcher timestamp for cooldown timing")

local tieMage = engine:RegisterExpectedEntry({
  key = "tie-mage-guid:2139",
  playerGUID = "tie-mage-guid",
  playerName = "TieMage",
  classToken = "MAGE",
  unitToken = "party9",
  spellID = 2139,
  kind = "INT",
  baseCd = 24,
})

assert(tieMage.source == "auto", "self-correlation suppression setup should start from auto state")
engine:RecordPartyCast("party9", 700.04)
local selfSuppressed = engine:ResolveInterruptWindow(700.05, {
  windowSize = 0.5,
  selfObservedAt = 700.04,
  selfWinsTies = true,
  consumeSuppressed = true,
})
assert(selfSuppressed == nil, "self casts should suppress party correlation when they tie for the closest Kryos window")
assert(engine:GetEntry("tie-mage-guid:2139").source == "auto", "self suppression should leave the party entry unconfirmed")
assert(engine:ResolveInterruptWindow(700.2, 0.5) == nil, "self-suppressed candidates should be consumed and not resolve on a later event")
