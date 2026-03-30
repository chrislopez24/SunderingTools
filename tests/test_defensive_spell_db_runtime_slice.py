from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_defensive_spell_db_runtime_slice():
    source = read("Core/CombatTrackSpellDB.lua")
    assert "GetDefensiveSpell" in source
    assert "GetDefensiveSpellsForClass" in source
    assert "GetRaidDefensiveSpellsForClass" in source
    assert "48707" in source
    assert "51052" in source
    assert "Aura Mastery" in source
    assert "Power Word: Barrier" in source
    assert "Rallying Cry" in source
    assert "ResolveNumericVariant" in source
