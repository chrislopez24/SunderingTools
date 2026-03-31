from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_settings_shell_matches_pedrolust_contract():
    source = read("Settings.lua")
    assert 'frame:SetSize(920, 560)' in source
    assert 'frame.headerBar:SetHeight(40)' in source
    assert 'frame.sidebar:SetWidth(192)' in source
    assert 'frame.headerTitle = CreateTextBlock(frame.headerBar, "SunderingTools"' in source
    assert 'frame.headerByline = CreateTextBlock(frame.headerBar, "|cffbbbbbbby Krich|r"' in source
    assert 'frame.headerMeta:SetText("Dungeon utility toolkit  |  v" .. ADDON_VERSION)' not in source
    assert 'frame.headerMeta:SetText("")' in source
    assert 'CreateFrame("ScrollFrame", nil, frame.contentPane, "UIPanelScrollFrameTemplate")' in source
    assert 'frame.scrollChild:SetSize(600, 1)' in source


def test_settings_helpers_support_dense_pedrolust_form_layout():
    source = read("Settings.lua")
    assert "function Helpers:CreateDividerLabel(parent, text, anchor, offsetY)" in source
    assert "function Helpers:CreateDarkButton(parent, label, width, onClick)" in source
    assert "function Helpers:CreateActionButton(parent, label, onClick, width)" in source
    assert "function Helpers:CreateSectionColumns(parent, anchor, offsetY, leftWidth, rightWidth, gap)" in source
    assert "function Helpers:CreateInlineCheckbox(parent, label, checked, onChange)" in source
    assert "function Helpers:PlaceRow(anchor, left, right, offsetY, gap)" in source
    assert "function Helpers:CreateLabeledDropdown(parent, label, options, selectedValue, width, onChange)" in source
    assert "function Helpers:CreateLabeledEditBox(parent, label, width, value, onChange)" in source
    assert "function Helpers:CreateLabeledSlider(parent, label, minValue, maxValue, step, value, onChange, width)" in source
    assert 'local holder = CreateFrame("Frame", nil, parent)' in source
    assert 'holder.checkbox = CreateFrame("CheckButton", nil, holder, "InterfaceOptionsCheckButtonTemplate")' in source
    assert "box:SetSize(self.ColumnWidth, 24)" not in source
    assert "button.Accent:SetColorTexture(unpack(Theme.accent))" in source
    assert "accent = { 0.09, 0.84, 0.95, 1.0 }" in source
    assert "buttonBg = { 0.08, 0.10, 0.12, 0.98 }" in source
    assert "buttonHighlight = { 0.11, 0.16, 0.19, 1.0 }" in source
    assert "button.Label:SetTextColor(unpack(Theme.idleText))" in source
    assert 'button.text:SetPoint("RIGHT", -10, 0)' in source
    assert 'button.text:SetJustifyH("LEFT")' in source
    assert 'holder:SetSize((width or (self.ColumnWidth - 28)) + 32, 58)' in source
    assert 'dropdown:SetPoint("TOPLEFT", -12, -18)' in source


def test_general_section_uses_dense_linear_controls():
    source = read("Settings.lua")
    assert "Show Minimap Icon" in source
    assert "Debug Mode" in source
    assert "Reset Minimap Position" in source
    assert "Reset All Settings" in source
    assert "Lock All Trackers" in source
    assert "Edit Mode Active" in source
    assert "helpers:CreateDividerLabel(content, \"Minimap\"" in source
    assert "helpers:CreateDividerLabel(content, \"Edit Mode\"" in source
    assert "helpers:CreateDividerLabel(content, \"System\"" in source
    assert 'CreateTextBlock(content, "General"' not in source
    assert 'CreateTextBlock(content, "Core addon controls."' not in source
    assert "/su opens settings." not in source


def test_minimap_button_supports_saved_angle_and_unlock_drag():
    source = read("MinimapButton.lua")
    assert "function button:UpdatePosition(angle)" in source
    assert 'button:RegisterForDrag("LeftButton")' in source
    assert "addon:IsMinimapUnlocked()" in source
    assert "addon:SetMinimapAngle(" in source
    assert 'local MINIMAP_LOGO_TEXTURE = "Interface\\\\AddOns\\\\SunderingTools\\\\assets\\\\icons\\\\logo-minimap.tga"' in source
    assert 'button.icon:SetTexture(MINIMAP_LOGO_TEXTURE)' in source
    assert 'button:SetMovable(true)' in source
    assert 'button.icon:SetPoint("CENTER", 1, 2)' in source
    assert 'button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)' in source
    assert 'button.border:SetSize(52, 52)' in source
    assert 'button.border:SetPoint("TOPLEFT")' in source


def test_bloodlust_page_keeps_reference_sections_and_actions():
    source = read("Modules/BloodlustSound.lua")
    assert 'helpers:CreateDividerLabel(panel, "State"' in source
    assert 'helpers:CreateDividerLabel(panel, "Behavior"' in source
    assert 'helpers:CreateDividerLabel(panel, "Layout"' in source
    assert 'helpers:CreateActionButton(panel, GetEditButtonLabel()' in source
    assert 'helpers:CreateActionButton(panel, "Reset Position"' in source
    assert 'helpers:CreateActionButton(panel, "Test Sound"' in source
    assert 'helpers:CreateActionButton(panel, "Stop Sound"' in source
    assert 'helpers:PlaceRow(' in source
    assert "Hide Bloodlust Icon" in source
    assert "Sound Channel" in source
    assert "Duration" in source
    assert 'durationSlider:SetPoint("TOPLEFT", soundFileInput, "BOTTOMLEFT", 0, -10)' not in source
    assert 'durationSlider:SetPoint("TOPLEFT", channelDropdown, "BOTTOMLEFT", 0, -10)' in source


def test_tracker_pages_keep_environment_and_behavior_controls():
    interrupt = read("Modules/InterruptTracker.lua")
    crowd_control = read("Modules/CrowdControlTracker.lua")
    raid_defensive = read("Modules/DefensiveRaidTracker.lua")

    for source in (interrupt, crowd_control):
        assert "Show in Dungeons" in source
        assert "Show in World" in source
        assert "Hide Out of Combat" in source
        assert "Tooltip on Hover" in source
        assert 'helpers:CreateDividerLabel(panel, "State"' in source
        assert 'helpers:CreateSectionColumns(panel, stateHint, -24)' in source
        assert 'helpers:CreateDividerLabel(behaviorColumn, "Behavior"' in source
        assert 'helpers:CreateDividerLabel(layoutColumn, "Layout"' in source
        assert 'helpers:PlaceRow(' in source
        assert "Show in Raids" not in source
        assert "Show in Arena" not in source
        assert "Enable Party Sync" not in source
        assert "Strict Sync Mode" not in source

    assert "Play Ready Sound" in interrupt
    assert "Filter Mode" in crowd_control
    assert "Show Preview When Solo" not in interrupt
    assert "Show Preview When Solo" not in crowd_control
    assert "Show Preview When Solo" not in raid_defensive


def test_party_defensive_page_exposes_attachment_and_tooltip_controls():
    source = read("Modules/PartyDefensiveTracker.lua")
    for label in (
        "State",
        "Behavior",
        "Layout",
        "Show Tooltip",
        "Maximum Icons",
        "Icon Size",
        "Icon Spacing",
        "Attach Point",
        "Relative Point",
        "Offset X",
        "Offset Y",
        "Reset Position",
    ):
        assert label in source
    assert "Show Preview When Solo" not in source
    assert "Enable Party Sync" not in source
    assert "Strict Sync Mode" not in source


def test_settings_section_switch_resets_scroll_position():
    source = read("Settings.lua")
    assert "SettingsFrame.scrollFrame:SetVerticalScroll(0)" in source
