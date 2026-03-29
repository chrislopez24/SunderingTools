from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_default_slash_command_opens_settings():
    source = read("SunderingTools.lua")
    assert 'elseif msg == "config" or msg == "settings" then' in source
    assert "else\n        addon:OpenSettings()" in source
    assert "addon:ShowQuickMenu()" not in source


def test_minimap_launcher_is_native_only():
    source = read("SunderingTools.lua")
    assert "LibStub" not in source
    assert "LibDataBroker" not in source
    assert "LibDBIcon" not in source
    assert "RightButton" not in source
    assert "ShowQuickMenu" not in source


def test_general_panel_includes_help_and_reset_all():
    source = read("Settings.lua")
    assert "Reset All Settings" in source
    assert "/su opens settings." in source
    assert "/su config opens settings directly." in source
    assert "/su reset reloads with defaults." in source
    assert 'button:SetText(addon.db.global.editMode and "Lock Tracker" or "Open Edit Mode")' in source
    assert "addon:SetEditMode(not addon.db.global.editMode)" in source
    assert "addon:SetEditMode(false)" in source
    assert 'frame:SetMovable(true)' in source
    assert 'frame:RegisterForDrag("LeftButton")' in source
    assert 'frame:SetScript("OnDragStart", frame.StartMoving)' in source
    assert 'frame:SetScript("OnDragStop", function(self)' in source


def test_interrupt_tracker_panel_exposes_technical_controls():
    source = read("Modules/InterruptTracker.lua")
    for label in (
        "Maximum Bars",
        "Grow Direction",
        "Bar Spacing",
        "Bar Width",
        "Bar Height",
        "Icon Size",
        "Font Size",
        "Show Preview When Solo",
    ):
        assert label in source
    assert 'addonRef:SetModuleValue("InterruptTracker", "previewWhenSolo", value)' in source
    assert 'addonRef:SetModuleValue("InterruptTracker", "iconSize", value)' in source
    assert 'addonRef:SetModuleValue("InterruptTracker", "fontSize", value)' in source
    assert "local function UsesClassColor(moduleDB)" in source
    assert "if UsesClassColor(db) and data.class then" in source
    assert "local editModePreview = false" in source
    assert "local function ShouldShowPreview()" in source
    assert "if editModePreview then" in source
    assert "container.dragHandle = CreateFrame(\"Frame\", nil, container)" in source
    assert "container.dragHandle:SetAllPoints()" in source
    assert "container.dragHandle:RegisterForDrag(\"LeftButton\")" in source
    assert "bar.borderTop" in source
    assert "bar.borderBottom" in source
    assert "bar.borderRight" in source
    assert "bar.cooldown = CreateFrame(\"StatusBar\", nil, bar)" in source
    assert "bar.cooldownNameText = bar.cooldown:CreateFontString(nil, \"OVERLAY\", \"GameFontNormal\")" in source
    assert "bar.cooldownText = bar.cooldown:CreateFontString(nil, \"OVERLAY\", \"GameFontNormal\")" in source
    assert "bar.nameText:Hide()" in source
    assert "bar.cooldownNameText:Show()" in source
    assert "local visibleCount = math.max(1, math.min(db.maxBars, #usedBarsList))" in source

    for removed in (
        "Name Font Size",
        "Timer Font Size",
        "Show Ready Text",
        "Ready Text",
        "Use Class Color",
        "Show Icon",
        "Show Name",
        "Show Timer",
        'addonRef:SetModuleValue("InterruptTracker", "useClassColorBar", value)',
    ):
        assert removed not in source


def test_bloodlust_sound_uses_exhaustion_aura_instead_of_spellcast_success():
    source = read("Modules/BloodlustSound.lua")
    assert "UNIT_SPELLCAST_SUCCEEDED" not in source
    assert "UNIT_AURA" in source
    assert "local lastSeenExpirationTime" in source
    assert "local function CheckFreshExhaustion()" in source
    assert "if hasFreshExhaustion then" in source


def test_runtime_files_do_not_use_dofile_and_models_load_from_toc():
    toc = read("SunderingTools.toc")
    assert "Modules\\InterruptTrackerModel.lua" in toc
    assert "Modules\\BloodlustSoundModel.lua" in toc

    for path in (
        "SunderingTools.lua",
        "Modules/InterruptTracker.lua",
        "Modules/BloodlustSound.lua",
    ):
        assert "dofile(" not in read(path)
