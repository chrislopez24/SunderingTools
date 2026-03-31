from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_nameplate_crowd_control_runtime_slice_loads_party_cc_watcher_from_toc():
    toc = read("SunderingTools.toc")
    watcher_source = read("Core/PartyCrowdControlAuraWatcher.lua")

    assert "Core\\PartyCrowdControlAuraWatcher.lua" in toc
    assert "_G.SunderingToolsPartyCrowdControlAuraWatcher = Watcher" in watcher_source


def test_nameplate_crowd_control_module_is_loaded_from_toc():
    toc = read("SunderingTools.toc")

    assert "Modules\\NameplateCrowdControl.lua" in toc


def test_nameplate_crowd_control_module_depends_on_party_cc_watcher():
    source = read("Modules/NameplateCrowdControl.lua")

    assert "SunderingToolsPartyCrowdControlAuraWatcher" in source
    assert "HARMFUL|CROWD_CONTROL" in source
    assert "CC_APPLIED" in source
    assert "CC_REMOVED" in source


def test_nameplate_crowd_control_settings_include_preview_hooks():
    source = read("Modules/NameplateCrowdControl.lua")

    assert "Preview Nameplate CC" in source
    assert "module:SetPreviewEnabled" in source
