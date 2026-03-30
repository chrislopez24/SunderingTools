from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_crowd_control_timer_format_matches_reference_rounding():
    source = read("Modules/CrowdControlTrackerModel.lua")

    assert 'return string.format("%.0fs", remaining)' in source
    assert 'math.floor(remaining)' not in source
    assert 'string.format("%.1f", remaining)' not in source
