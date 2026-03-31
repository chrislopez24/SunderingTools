from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_nameplate_crowd_control_runtime_slice_loads_party_cc_watcher_from_toc():
    toc = read("SunderingTools.toc")
    watcher_source = read("Core/PartyCrowdControlAuraWatcher.lua")

    assert "Core\\PartyCrowdControlAuraWatcher.lua" in toc
    assert "_G.SunderingToolsPartyCrowdControlAuraWatcher = Watcher" in watcher_source
