from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_nameplate_crowd_control_runtime_slice_loads_unit_aura_state_watcher_from_toc():
    toc = read("SunderingTools.toc")
    watcher_source = read("Core/UnitAuraStateWatcher.lua")

    assert "Core\\UnitAuraStateWatcher.lua" in toc
    assert "_G.SunderingToolsUnitAuraStateWatcher = WatcherModule" in watcher_source


def test_nameplate_crowd_control_module_is_loaded_from_toc():
    toc = read("SunderingTools.toc")

    assert "Modules\\NameplateCrowdControl.lua" in toc


def test_nameplate_crowd_control_module_depends_on_unit_aura_state_watcher():
    source = read("Modules/NameplateCrowdControl.lua")

    assert "SunderingToolsUnitAuraStateWatcher" in source
    assert "SunderingToolsCombatTrackSync" in source
    assert "HARMFUL|CROWD_CONTROL" in source
    assert "runtime.watchers" in source
    assert "watcher:GetCcState()" in source
    assert "payload.icon" in source
    assert "frame.icon:SetTexture(ResolvePayloadIcon(payload))" in source


def test_nameplate_crowd_control_settings_include_preview_hooks():
    source = read("Modules/NameplateCrowdControl.lua")

    assert "Preview Nameplate CC" in source
    assert "module:SetPreviewEnabled" in source


def test_nameplate_crowd_control_skips_payloads_without_displayable_icon():
    source = read("Modules/NameplateCrowdControl.lua")

    assert "local FALLBACK_ICON = \"Interface\\\\Icons\\\\INV_Misc_QuestionMark\"" in source
    assert "local function HasDisplayablePayload(payload)" in source
    assert "if not frame or not payload or not HasDisplayablePayload(payload) then" in source


def test_nameplate_crowd_control_supports_sync_enrichment_for_unknown_cc_auras():
    source = read("Modules/NameplateCrowdControl.lua")

    assert 'eventFrame:RegisterEvent("CHAT_MSG_ADDON")' in source
    assert 'eventFrame:RegisterEvent("UNIT_AURA")' in source
    assert "Sync.GetPrefix()" in source
    assert "local GENERIC_CC_ICON" in source
    assert 'correlationState = "CC_UNKNOWN"' in source
    assert "ResolveSynchronizedPayload(unitToken, payload)" in source
    assert "ResolveSourceShortName(payload.sourceUnit)" in source
    assert "syncEvent.senderShort == sourceShort" in source
