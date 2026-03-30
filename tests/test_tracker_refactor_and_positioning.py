from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_toc_loads_shared_tracker_core_before_modules():
    toc = read("SunderingTools.toc")

    assert "Core\\FramePositioning.lua" in toc
    assert "Core\\TrackerFrame.lua" in toc
    assert toc.index("Core\\FramePositioning.lua") < toc.index("Modules\\InterruptTracker.lua")
    assert toc.index("Core\\TrackerFrame.lua") < toc.index("Modules\\CrowdControlTracker.lua")


def test_trackers_use_shared_positioning_and_no_longer_save_getpoint_offsets():
    interrupt = read("Modules/InterruptTracker.lua")
    crowd_control = read("Modules/CrowdControlTracker.lua")

    for source in (interrupt, crowd_control):
        assert "FramePositioning.SaveAbsolutePosition" in source
        assert "FramePositioning.ApplySavedPosition" in source
        assert 'local _, _, _, x, y = container:GetPoint()' not in source
        assert 'container:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)' not in source


def test_trackers_use_shared_container_shell_helper():
    interrupt = read("Modules/InterruptTracker.lua")
    crowd_control = read("Modules/CrowdControlTracker.lua")

    for source in (interrupt, crowd_control):
        assert "_G.SunderingToolsTrackerFrame" in source
        assert "TrackerFrame.CreateContainerShell" in source
        assert "TrackerFrame.UpdateEditModeVisuals" in source


def test_shared_positioning_supports_absolute_restore_and_legacy_center_fallback():
    source = read("Core/FramePositioning.lua")

    assert 'if moduleDB.positionMode == "ABSOLUTE_TOPLEFT"' in source
    assert 'frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", moduleDB.posX, moduleDB.posY)' in source
    assert 'frame:SetPoint("CENTER", UIParent, "CENTER", moduleDB.posX, moduleDB.posY)' in source
    assert 'moduleDB.positionMode = "ABSOLUTE_TOPLEFT"' in source
    assert 'moduleDB.positionMode = "CENTER_OFFSET"' in source


def test_models_no_longer_use_dofile_fallback_loading():
    assert "dofile(" not in read("Modules/InterruptTrackerModel.lua")
    assert "dofile(" not in read("Modules/CrowdControlTrackerModel.lua")


def test_cleanup_removes_empty_cc_test_and_stop_methods():
    source = read("Modules/CrowdControlTracker.lua")

    assert "function module:Test(_moduleDB)" not in source
    assert "function module:Stop()" not in source


def test_bloodlust_uses_shared_positioning_helper_for_consistent_drag_saves():
    source = read("Modules/BloodlustSound.lua")

    assert "FramePositioning.SaveAbsolutePosition" in source
    assert "FramePositioning.ApplySavedPosition" in source
    assert 'local _, _, _, x, y = self:GetPoint()' not in source
