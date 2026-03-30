from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_toc_registers_hybrid_tracking_files():
    toc = read("SunderingTools.toc")
    assert "Core\\CombatTrackSpellDB.lua" in toc
    assert "Core\\CombatTrackSync.lua" in toc
    assert "Core\\CombatTrackEngine.lua" in toc
    assert "Modules\\CrowdControlTrackerModel.lua" in toc
    assert "Modules\\CrowdControlTracker.lua" in toc


def test_hybrid_tracking_files_exist():
    for path in (
        "Core/CombatTrackSpellDB.lua",
        "Core/CombatTrackSync.lua",
        "Core/CombatTrackEngine.lua",
        "Modules/CrowdControlTrackerModel.lua",
        "Modules/CrowdControlTracker.lua",
    ):
        assert (ROOT / path).exists()


def test_crowd_control_module_shell_exists():
    source = read("Modules/CrowdControlTracker.lua")
    assert 'key = "CrowdControlTracker"' in source
    assert 'label = "Crowd Control Tracker"' in source


def test_spell_db_matches_latest_kryos_cc_deltas():
    source = read("Core/CombatTrackSpellDB.lua")

    assert '{ spellID = 5246, cd = 75, name = "Intimidating Shout", essential = true }' in source
    assert '{ spellID = 370965, cd = 90, name = "The Hunt" }' in source
    assert '{ spellID = 116095, cd = 0, name = "Disable" }' not in source


def test_sync_channel_selection_matches_kryos_group_logic():
    source = read("Core/CombatTrackSync.lua")

    assert 'if IsInRaid and IsInRaid() then' in source
    assert 'if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then' in source
    assert 'if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) then' in source
    assert 'return nil' in source
