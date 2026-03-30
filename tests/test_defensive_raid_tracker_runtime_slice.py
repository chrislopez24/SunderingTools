from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_defensive_raid_tracker_uses_shared_combat_track_core_and_raid_def_kind():
    source = read("Modules/DefensiveRaidTracker.lua")

    assert '_G.SunderingToolsDefensiveRaidTrackerModel' in source
    assert "_G.SunderingToolsCombatTrackSpellDB" in source
    assert "_G.SunderingToolsCombatTrackSync" in source
    assert "_G.SunderingToolsCombatTrackEngine" in source
    assert 'key = "DefensiveRaidTracker"' in source
    assert 'kind = "RAID_DEF"' in source
    assert "GetKnownRaidDefensiveSpellsForClass" in source
    assert "ResolveDefensiveSpell" in source


def test_defensive_raid_tracker_registers_sync_and_addon_message_hooks():
    source = read("Modules/DefensiveRaidTracker.lua")

    assert "syncEnabled = true" in source
    assert 'eventFrame:RegisterEvent("CHAT_MSG_ADDON")' in source
    assert "Sync.RegisterPrefix()" in source
    assert 'Sync.Send("HELLO"' in source
    assert "specID = specID" in source
    assert "Sync.Decode(message)" in source


def test_defensive_raid_tracker_supports_preview_and_runtime_bar_population():
    source = read("Modules/DefensiveRaidTracker.lua")

    assert "Model.BuildPreviewBars()" in source
    assert "PopulateBars(BuildPreviewBars())" in source
    assert "PopulateBars(BuildRuntimeBarEntries())" in source
    assert "previewWhenSolo = true" in source


def test_defensive_raid_tracker_inbound_sync_is_guarded_by_module_settings():
    source = read("Modules/DefensiveRaidTracker.lua")

    assert "if not db or not db.enabled or db.syncEnabled == false then" in source


def test_defensive_raid_tracker_prunes_and_reconciles_runtime_sync_state():
    source = read("Modules/DefensiveRaidTracker.lua")

    assert "runtime.engine:RemoveEntry(" in source
    assert "PruneRuntimeState = function()" in source
    assert "ReconcilePartyUser = function(" in source


def test_defensive_raid_tracker_only_registers_remote_members_from_sync_manifests():
    source = read("Modules/DefensiveRaidTracker.lua")

    roster_start = source.index("local function RefreshRuntimeRoster()")
    roster_end = source.index("local function SendCurrentSelfState()", roster_start)
    roster_block = source[roster_start:roster_end]

    assert 'if unit == "player" then' in roster_block
    assert "GetLocalOwnedRaidDefensives(classToken)" in roster_block
    assert "elseif previousUser and type(previousUser.spellIDs) == \"table\" and #previousUser.spellIDs > 0 then" in roster_block
    assert "SpellDB.GetKnownRaidDefensiveSpellsForClass" in roster_block


def test_defensive_raid_tracker_supports_strict_sync_mode_and_remaining_payloads():
    source = read("Modules/DefensiveRaidTracker.lua")

    assert "strictSyncMode = false" in source
    assert "local function IsStrictSyncMode()" in source
    assert "payload.remaining" in source
    assert 'remaining = trackedSpell.cd' in source
