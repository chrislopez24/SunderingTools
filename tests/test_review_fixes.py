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
    assert "Show Minimap Icon" in source
    assert "Debug Mode" in source
    assert "Unlock Minimap Drag" in source
    assert "Lock Minimap Drag" in source
    assert "Reset Minimap Position" in source
    assert "Lock All Trackers" in source
    assert "Edit Mode Active" in source
    assert 'CreateTextBlock(content, "General"' not in source
    assert "/su opens settings." not in source
    assert "GetGlobalEditModeLabel(addon)" in source
    assert "addon:SetEditMode(not addon.db.global.editMode)" in source
    assert "addon:SetEditMode(false)" in source
    assert 'frame:SetMovable(true)' in source
    assert 'frame.headerBar:RegisterForDrag("LeftButton")' in source
    assert 'frame.headerBar:SetScript("OnDragStart", function()' in source
    assert 'frame.headerBar:SetScript("OnDragStop", function()' in source


def test_general_panel_edit_mode_button_avoids_initializer_scope_bug():
    source = read("Settings.lua")
    assert 'button:SetScript("OnClick", function(self)' in source
    assert 'local button = helpers:CreateButton(content, "", function(self)' not in source


def test_settings_helpers_include_edit_box_for_bloodlust_sound():
    settings = read("Settings.lua")
    bloodlust = read("Modules/BloodlustSound.lua")
    assert 'function Helpers:CreateEditBox(parent, label, width, value, onChange)' in settings
    assert 'function Helpers:CreateLabeledEditBox(parent, label, width, value, onChange)' in settings
    assert 'helpers:CreateLabeledEditBox(panel, "Sound File", helpers.WideControlWidth, moduleDB.soundFile or "", function(value)' in bloodlust


def test_interrupt_tracker_panel_exposes_technical_controls():
    source = read("Modules/InterruptTracker.lua")
    for label in (
        "State",
        "Behavior",
        "Layout",
        "Maximum Bars",
        "Grow Direction",
        "Bar Spacing",
        "Bar Width",
        "Bar Height",
        "Icon Size",
        "Font Size",
        "Enable Party Sync",
    ):
        assert label in source
    assert 'addonRef:SetModuleValue("InterruptTracker", "iconSize", value)' in source
    assert 'addonRef:SetModuleValue("InterruptTracker", "fontSize", value)' in source
    assert 'addonRef.db.global.activeEditModule == "InterruptTracker"' in source
    assert "local function UsesClassColor(moduleDB)" in source
    assert "if UsesClassColor(db) and data.class then" in source
    assert "local editModePreview = false" in source
    assert "local function ShouldShowPreview()" in source
    assert "if editModePreview then" in source
    assert "_G.SunderingToolsTrackerFrame" in source
    assert "TrackerFrame.CreateContainerShell" in source
    assert "TrackerFrame.UpdateEditModeVisuals" in source
    assert "FramePositioning.SaveAbsolutePosition(container, db)" in source
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


def test_bloodlust_sound_uses_active_bloodlust_aura_instead_of_exhaustion_cooldown():
    source = read("Modules/BloodlustSound.lua")
    assert "UNIT_SPELLCAST_SUCCEEDED" not in source
    assert "UNIT_AURA" in source
    assert "PLAYER_REGEN_DISABLED" in source
    assert "PLAYER_REGEN_ENABLED" in source
    assert "local function ShouldShowReadyState()" in source
    assert "InCombatLockdown()" in source
    assert "local lastSeenExpirationTime" in source
    assert "local function FindActiveTriggerAura()" in source
    assert 'C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")' in source
    assert 'local normalizedName = NormalizeName(aura.name)' in source
    assert "local function CheckFreshBloodlust()" in source
    assert "local function CheckActiveBloodlust()" in source
    assert "if hasFreshBloodlust then" in source
    assert "if hasBloodlust then" in source
    assert "CheckFreshExhaustion" not in source
    assert "CheckExhaustion" not in source


def test_bloodlust_sound_supports_icon_style_dropdown_and_custom_path():
    source = read("Modules/BloodlustSound.lua")
    assert 'iconStyle = "BL_ICON"' in source
    assert 'customIconPath = ""' in source
    assert '"BL Icon Style"' in source
    assert '"BL Icon"' in source
    assert '"Pedro"' in source
    assert '"Custom"' in source
    assert '"Custom Icon Path"' in source
    assert "assets\\\\art\\\\pedro.tga" in source
    assert "if moduleDB.iconStyle == \"CUSTOM\" then" in source
    assert "addonRef:RefreshSettings()" in source
    assert '"Duration"' in source


def test_bloodlust_sound_animates_pedro_sprite_sheet():
    source = read("Modules/BloodlustSound.lua")
    assert "local PEDRO_ATLAS_COLS = 4" in source
    assert "local PEDRO_ATLAS_ROWS = 8" in source
    assert "local PEDRO_USED_WIDTH = 770" in source
    assert "local PEDRO_USED_HEIGHT = 1536" in source
    assert "local PEDRO_FRAME_COUNT = 32" in source
    assert "local PEDRO_FPS = 6" in source
    assert "frame.icon:SetTexCoord(" in source
    assert 'if (db and db.iconStyle or "BL_ICON") == "PEDRO" then' in source
    assert "frame.bg = frame:CreateTexture" not in source


def test_crowd_control_and_sundering_shell_use_consistent_setting_state_labels():
    cc_source = read("Modules/CrowdControlTracker.lua")
    shell_source = read("SunderingTools.lua")

    for label in (
        "State",
        "Behavior",
        "Layout",
        "Enable Party Sync",
        "M+ Essentials",
        "All CC",
    ):
        assert label in cc_source

    assert 'addonRef.db.global.activeEditModule == "CrowdControlTracker"' in cc_source
    assert "activeEditModule = nil" in shell_source
    assert "self.db.global.activeEditModule = self.db.global.editMode and activeKey or nil" in shell_source
    assert "Track crowd control, choose the filter, and adjust layout." in cc_source
    assert "Show Preview When Solo" not in cc_source


def test_general_edit_mode_uses_global_all_state_and_bloodlust_supports_shared_edit_flow():
    shell_source = read("SunderingTools.lua")
    settings_source = read("Settings.lua")
    bloodlust_source = read("Modules/BloodlustSound.lua")

    assert 'activeKey = moduleKey or "ALL"' in shell_source
    assert "Interrupt Tracker" in settings_source
    assert "Crowd Control Tracker" in settings_source
    assert "Bloodlust Sound" in settings_source
    assert "function module:SetEditMode(enabled)" in bloodlust_source
    assert "frame.editLabel" in bloodlust_source
    assert "frame:SetMouseClickEnabled(false)" not in bloodlust_source
    assert "Sound alerts, icon behavior, and placement." in bloodlust_source
    assert 'helpers:CreateDividerLabel(panel, "State"' in bloodlust_source
    assert 'helpers:CreateActionButton(panel, GetEditButtonLabel()' in bloodlust_source


def test_party_defensive_tracker_exposes_full_attachment_settings():
    source = read("Modules/PartyDefensiveTracker.lua")
    for setting in (
        'addonRef:SetModuleValue("PartyDefensiveTracker", "showTooltip", value)',
        'addonRef:SetModuleValue("PartyDefensiveTracker", "maxIcons", value)',
        'addonRef:SetModuleValue("PartyDefensiveTracker", "iconSize", value)',
        'addonRef:SetModuleValue("PartyDefensiveTracker", "iconSpacing", value)',
        'addonRef:SetModuleValue("PartyDefensiveTracker", "attachPoint", value)',
        'addonRef:SetModuleValue("PartyDefensiveTracker", "relativePoint", value)',
        'addonRef:SetModuleValue("PartyDefensiveTracker", "offsetX", value)',
        'addonRef:SetModuleValue("PartyDefensiveTracker", "offsetY", value)',
    ):
        assert setting in source

    assert 'helpers:CreateActionButton(panel, "Reset Position"' in source
    assert 'helpers:CreateDividerLabel(panel, "State"' in source
    assert 'helpers:CreateDividerLabel(behaviorColumn, "Behavior"' in source
    assert 'helpers:CreateDividerLabel(layoutColumn, "Layout"' in source


def test_interrupt_and_raid_tracker_settings_drop_preview_toggle_from_ui():
    interrupt = read("Modules/InterruptTracker.lua")
    raid = read("Modules/DefensiveRaidTracker.lua")

    assert "Show Preview When Solo" not in interrupt
    assert "Show Preview When Solo" not in raid


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


def test_defensive_trackers_do_not_spam_debug_logs_for_untracked_self_casts():
    party_defensive = read("Modules/PartyDefensiveTracker.lua")
    raid_defensive = read("Modules/DefensiveRaidTracker.lua")

    assert 'addon:DebugLog("pdef", "self cast ignored", spellID)' not in party_defensive
    assert 'addon:DebugLog("rdef", "self cast ignored", spellID)' not in raid_defensive
