from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_party_defensive_tracker_uses_shared_defensive_core_and_def_kind_only():
    source = read("Modules/PartyDefensiveTracker.lua")

    assert "_G.SunderingToolsPartyDefensiveTrackerModel" in source
    assert "_G.SunderingToolsCombatTrackSpellDB" in source
    assert "_G.SunderingToolsCombatTrackSync" in source
    assert "_G.SunderingToolsCombatTrackEngine" in source
    assert 'key = "PartyDefensiveTracker"' in source
    assert 'kind = "DEF"' in source
    assert "GetKnownDefensiveSpellsForClass" in source
    assert "ResolveDefensiveSpell" in source
    assert "GetRaidDefensiveSpellsForClass" not in source


def test_party_defensive_tracker_attaches_to_blizzard_compact_party_member_frames():
    source = read("Modules/PartyDefensiveTracker.lua")

    assert "CompactPartyFrame" in source
    assert "memberUnitFrames" in source
    assert "RefreshMembers" in source
    assert "SunderingToolsPartyDefensiveAttachment" in source
    assert "_ownerFrame = memberFrame" in source


def test_party_defensive_tracker_registers_sync_paths_and_preview_edit_mode():
    source = read("Modules/PartyDefensiveTracker.lua")

    assert "syncEnabled = true" in source
    assert "previewWhenSolo = true" in source
    assert 'eventFrame:RegisterEvent("CHAT_MSG_ADDON")' in source
    assert "Sync.RegisterPrefix()" in source
    assert 'Sync.Send("HELLO"' in source
    assert 'Sync.Send("DEF_MANIFEST"' in source
    assert 'Sync.Send("DEF_STATE"' in source
    assert "specID = specID" in source
    assert "Model.BuildPreviewIcons" in source
    assert "function module:SetEditMode(enabled)" in source


def test_party_defensive_tracker_registers_aura_fallback_runtime():
    toc = read("SunderingTools.toc")
    source = read("Modules/PartyDefensiveTracker.lua")

    assert "Core\\PartyDefensiveAuraFallback.lua" in toc
    assert "_G.SunderingToolsPartyDefensiveAuraFallback" in source
    assert "module.applyDefensiveFallback = ApplyDefensiveFallback" in source


def test_party_defensive_tracker_ignores_non_defensive_or_raid_defensive_sync_entries():
    source = read("Modules/PartyDefensiveTracker.lua")

    assert 'trackedSpell.kind == "DEF"' in source
    assert 'payload.kind ~= "DEF"' in source
    assert "runtime.engine:GetEntriesByKind(\"DEF\")" in source


def test_party_defensive_tracker_does_not_artificially_exclude_raid_context_updates():
    source = read("Modules/PartyDefensiveTracker.lua")

    assert "CompactPartyFrame.memberUnitFrames" in source
    assert "return db.previewWhenSolo and not IsInGroup()" in source
    assert "return db.previewWhenSolo and not IsInGroup() and not IsInRaid()" not in source


def test_party_defensive_tracker_gates_sync_broadcasts_and_filters_inbound_senders():
    source = read("Modules/PartyDefensiveTracker.lua")

    assert "if not db or not db.enabled or db.syncEnabled == false then" in source
    assert "IsTrackedSender(userKey)" in source
    assert "GetOrCreatePartyUser(userKey" in source


def test_party_defensive_tracker_supports_strict_sync_mode_and_remaining_payloads():
    source = read("Modules/PartyDefensiveTracker.lua")

    assert "strictSyncMode = false" in source
    assert "local function IsStrictSyncMode()" in source
    assert "payload.remaining" in source
    assert 'remaining = trackedSpell.cd' in source


def test_party_defensive_tracker_retries_late_compact_party_frame_attachment():
    source = read("Modules/PartyDefensiveTracker.lua")

    assert "TryHookCompactPartyFrameLater()" in source
    assert "HookCompactPartyFrame()" in source
    assert "UpdateAttachments()" in source
