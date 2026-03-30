local Sync = dofile("Core/CombatTrackSync.lua")
local Engine = dofile("Core/CombatTrackEngine.lua")

local encodedManifest = Sync.Encode("DEF_MANIFEST", {
  kind = "DEF",
  spells = { 48707, 48792, 55233 },
})
assert(encodedManifest == "DEF_MANIFEST:DEF:48707,48792,55233", "defensive manifest payloads should encode kind-tagged compact spell lists")

local manifestType, manifestPayload = Sync.Decode(encodedManifest)
assert(manifestType == "DEF_MANIFEST", "manifest message type should round-trip")
assert(manifestPayload.kind == "DEF", "manifest payload should preserve kind")
assert(#manifestPayload.spells == 3, "manifest payload should decode the full spell list")
assert(manifestPayload.spells[1] == 48707, "manifest payload should preserve the first spell")
assert(manifestPayload.spells[3] == 55233, "manifest payload should preserve the last spell")

local legacyManifestType, legacyManifestPayload = Sync.Decode("DEF_MANIFEST:48707,48792,55233")
assert(legacyManifestType == "DEF_MANIFEST", "legacy manifest should still decode as DEF_MANIFEST")
assert(legacyManifestPayload.kind == nil, "legacy manifest should not invent a kind")
assert(#legacyManifestPayload.spells == 3, "legacy manifest should still decode the full spell list")

local encodedState = Sync.Encode("DEF_STATE", {
  spellID = 48707,
  kind = "DEF",
  cd = 60,
  charges = 1,
  remaining = 17.25,
})
assert(encodedState == "DEF_STATE:48707:DEF:60:1:17.25", "defensive state payloads should encode kind, cooldown, charges, and remaining time")

local stateType, statePayload = Sync.Decode(encodedState)
assert(stateType == "DEF_STATE", "state message type should round-trip")
assert(statePayload.spellID == 48707, "state payload should preserve spell ID")
assert(statePayload.kind == "DEF", "state payload should preserve kind")
assert(statePayload.cd == 60, "state payload should preserve cooldown")
assert(statePayload.charges == 1, "state payload should preserve charges")
assert(statePayload.remaining == 17.25, "state payload should preserve remaining")
assert(statePayload.readyAt == nil or statePayload.readyAt == 0, "state payload should not invent readyAt for strict timing payloads")

local legacyStateType, legacyStatePayload = Sync.Decode("DEF_STATE:48707:60:1:123.5")
assert(legacyStateType == "DEF_STATE", "legacy defensive state should still decode as DEF_STATE")
assert(legacyStatePayload.spellID == 48707, "legacy defensive state should preserve spell ID")
assert(legacyStatePayload.kind == nil, "legacy defensive state should not invent a kind from the cooldown slot")
assert(legacyStatePayload.cd == 60, "legacy defensive state should parse cooldown from the third field")
assert(legacyStatePayload.charges == 1, "legacy defensive state should parse charges from the fourth field")
assert(legacyStatePayload.readyAt == 123.5, "legacy defensive state should parse readyAt from the fifth field")

local engine = Engine.New()
engine:RegisterExpectedEntry({
  key = "dk-guid:48707",
  playerGUID = "dk-guid",
  playerName = "Death Knight",
  classToken = "DEATHKNIGHT",
  unitToken = "party1",
  spellID = 48707,
  kind = "DEF",
  baseCd = 60,
})

local syncEntry = engine:ApplySyncState("dk-guid", 48707, statePayload)

assert(syncEntry ~= nil, "defensive sync state should upsert an engine entry")
assert(syncEntry.source == "sync", "defensive sync state should use sync priority")
assert(syncEntry.kind == "DEF", "defensive sync state should preserve kind")
assert(syncEntry.cd == 60, "defensive sync state should preserve cooldown")
assert(syncEntry.charges == 1, "defensive sync state should preserve charges")
assert(syncEntry.readyAt == nil, "remaining-only sync state should not set readyAt without an observed time")

local updatedSyncEntry = engine:ApplySyncState("dk-guid", 48707, {
  kind = "DEF",
  cd = 75,
  charges = 1,
})

assert(updatedSyncEntry.baseCd == 75, "defensive sync state should update the stored cooldown used for later timing derivation")

local derivedSyncCast = engine:ApplySyncCast("dk-guid", 48707, 200, nil)
assert(derivedSyncCast.readyAt == 275, "later sync timing should derive from the synced cooldown instead of stale catalog data")

local rebuiltSyncEntry = engine:ApplySyncState("dk-guid", 48707, {
  kind = "DEF",
  cd = 75,
  charges = 1,
  remaining = 20,
  observedAt = 300,
})
assert(rebuiltSyncEntry.startTime == 245, "remaining-based sync state should rebuild startTime from observedAt and cooldown")
assert(rebuiltSyncEntry.readyAt == 320, "remaining-based sync state should rebuild readyAt from observedAt")

local malformedStateType, malformedStatePayload = Sync.Decode("DEF_STATE:48707:DEF:not-a-number:2:0")
assert(malformedStateType == "DEF_STATE", "malformed defensive state should still decode as DEF_STATE")
assert(malformedStatePayload.kind == "DEF", "malformed defensive state should still preserve kind")
assert(malformedStatePayload.cd == 0, "malformed defensive cooldowns should decode to 0 before engine validation")

local guardedEngine = Engine.New()
guardedEngine:RegisterExpectedEntry({
  key = "guard-guid:48707",
  playerGUID = "guard-guid",
  playerName = "Guard",
  classToken = "DEATHKNIGHT",
  unitToken = "party2",
  spellID = 48707,
  kind = "DEF",
  baseCd = 60,
})

local guardedEntry = guardedEngine:ApplySyncState("guard-guid", 48707, malformedStatePayload)
assert(guardedEntry.kind == "DEF", "guarded sync state should still preserve the decoded kind")
assert(guardedEntry.baseCd == 60, "non-positive synced cooldowns should not overwrite an existing cooldown")
assert(guardedEntry.cd == nil, "non-positive synced cooldowns should not write a cooldown override")

local guardedCast = guardedEngine:ApplySyncCast("guard-guid", 48707, 300, nil)
assert(guardedCast.readyAt == 360, "later timing should continue using the existing cooldown after a malformed sync override")
