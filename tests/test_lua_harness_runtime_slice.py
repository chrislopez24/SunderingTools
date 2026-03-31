from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_lua_harness_includes_defensive_tests():
    source = read("tests/run.lua")
    assert 'dofile("tests/core/test_defensive_spell_db.lua")' in source
    assert 'dofile("tests/core/test_defensive_sync.lua")' in source
    assert 'dofile("tests/core/test_cooldown_viewer_meta.lua")' in source
