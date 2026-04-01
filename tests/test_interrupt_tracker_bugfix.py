from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_trigger_cooldown_refreshes_visual_state_immediately():
    source = read("Modules/InterruptTracker.lua")

    trigger_start = source.index("local function TriggerCooldown(unit)")
    watcher_start = source.index("for i = 1, 4 do", trigger_start)
    trigger_block = source[trigger_start:watcher_start]

    assert "ApplyRuntimeCooldownEntry(applied, true)" in trigger_block


def test_trigger_cooldown_restores_ready_visual_state_when_finished():
    source = read("Modules/InterruptTracker.lua")

    helper_start = source.index("StartCooldownTicker = function(bar, data)")
    build_preview_start = source.index("local function BuildPreviewBars()")
    helper_block = source[helper_start:build_preview_start]

    assert "cooldownState[data.key] = nil" in helper_block
    assert "UpdateEngineEntryTiming(data.runtimeKey, data.source, 0, 0)" in helper_block
    assert helper_block.count("UpdateBarVisuals(bar, data)") >= 2


def test_populate_bars_restarts_cooldown_ticker_for_restored_entries():
    source = read("Modules/InterruptTracker.lua")

    populate_start = source.index("local function PopulateBars(entries)")
    update_start = source.index("-- Update party data")
    populate_block = source[populate_start:update_start]

    assert "StartCooldownTicker(bar, barData)" in populate_block


def test_trigger_cooldown_uses_shared_ticker_path():
    source = read("Modules/InterruptTracker.lua")

    trigger_start = source.index("local function TriggerCooldown(unit)")
    watcher_start = source.index("for i = 1, 4 do", trigger_start)
    trigger_block = source[trigger_start:watcher_start]

    assert "ApplyRuntimeCooldownEntry(applied, true)" in trigger_block


def test_self_cast_path_uses_event_authoritative_cooldown():
    source = read("Modules/InterruptTracker.lua")

    event_start = source.index('elseif event == "UNIT_SPELLCAST_SUCCEEDED" then')
    event_end = source.index('    elseif event == "CHAT_MSG_ADDON" then', event_start)
    event_block = source[event_start:event_end]

    assert "runtime.engine:ApplySelfCast(UnitGUID(\"player\"), canonicalSpellID, now, now + cooldown)" in event_block
    assert "HasObservedSelfCooldownStart" not in source
    assert "cooldown not started" not in event_block


def test_sync_path_requires_authoritative_or_locally_resolved_interrupt_identity():
    source = read("Modules/InterruptTracker.lua")

    assert "local function CanAcceptSyncedInterruptSpell(senderShort, unit, spellID)" in source

    sync_start = source.index("local function HandleSyncInterruptMessage(message, sender)")
    sync_end = source.index("local function UpdateAnchorVisuals(enabled)", sync_start)
    sync_block = source[sync_start:sync_end]

    assert "if not CanAcceptSyncedInterruptSpell(senderShort, unit, spellID) then" in sync_block
    assert 'addon:DebugLog("int", "ignore sync", senderShort or "?", spellID, "identity mismatch")' in sync_block


def test_sync_path_rejects_stale_ready_at_updates():
    source = read("Modules/InterruptTracker.lua")

    assert "local function ShouldApplyIncomingInterruptSync(unit, spellID, readyAt)" in source

    sync_start = source.index("local function HandleSyncInterruptMessage(message, sender)")
    sync_end = source.index("local function UpdateAnchorVisuals(enabled)", sync_start)
    sync_block = source[sync_start:sync_end]

    assert "if not ShouldApplyIncomingInterruptSync(unit, spellID, readyAt) then" in sync_block
    assert 'addon:DebugLog("int", "ignore sync", senderShort or "?", spellID, "stale readyAt")' in sync_block


def test_sync_replays_do_not_increment_interrupt_stats():
    source = read("Modules/InterruptTracker.lua")

    sync_start = source.index("local function HandleSyncInterruptMessage(message, sender)")
    sync_end = source.index("local function UpdateAnchorVisuals(enabled)", sync_start)
    sync_block = source[sync_start:sync_end]

    assert "ApplyRuntimeCooldownEntry(applied, false)" in sync_block


def test_hello_replies_are_throttled_and_do_not_reannounce_full_presence():
    source = read("Modules/InterruptTracker.lua")

    assert "lastHelloReplyAt = {}" in source
    assert "local function ReplyToHello(senderShort)" in source

    hello_start = source.index("local function HandleSyncHelloMessage(payload, sender)")
    hello_end = source.index("local function HandleSyncInterruptManifestMessage(payload, sender)", hello_start)
    hello_block = source[hello_start:hello_end]

    assert "ReplyToHello(senderShort)" in hello_block
    assert "AnnouncePresence()" not in hello_block
