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
