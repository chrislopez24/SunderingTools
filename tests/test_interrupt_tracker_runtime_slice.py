from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_interrupt_tracker_uses_shared_combat_track_core():
    source = read("Modules/InterruptTracker.lua")

    assert "_G.SunderingToolsCombatTrackSpellDB" in source
    assert "_G.SunderingToolsCombatTrackSync" in source
    assert "_G.SunderingToolsCombatTrackEngine" in source
    assert "partyUsers = {}" in source
    assert "runtime.engine:UpsertEntry({" in source
    assert 'kind = "INT"' in source


def test_interrupt_tracker_registers_addon_messages_and_manifest_sync_paths():
    source = read("Modules/InterruptTracker.lua")

    assert 'eventFrame:RegisterEvent("CHAT_MSG_ADDON")' in source
    assert "Sync.RegisterPrefix()" in source
    assert 'Sync.Send("HELLO"' in source
    assert 'Sync.Send("INT"' in source
    assert "Sync.Decode(message)" in source


def test_interrupt_tracker_uses_exact_self_detection_and_engine_priority_paths():
    source = read("Modules/InterruptTracker.lua")

    event_start = source.index('elseif event == "UNIT_SPELLCAST_SUCCEEDED" then')
    event_end = source.index('    elseif event == "CHAT_MSG_ADDON" then', event_start)
    self_block = source[event_start:event_end]

    assert "ApplySelfInterrupt(interruptEntry)" in self_block
    assert 'RegisterRuntimeInterrupt("player", canonicalSpellID, nil, {' in self_block
    assert ":ApplySelfCast(" in self_block
    assert 'Sync.Send("INT"' in self_block


def test_interrupt_tracker_self_cast_enriches_applied_metadata_before_render_update():
    source = read("Modules/InterruptTracker.lua")

    event_start = source.index('elseif event == "UNIT_SPELLCAST_SUCCEEDED" then')
    event_end = source.index('    elseif event == "CHAT_MSG_ADDON" then', event_start)
    self_block = source[event_start:event_end]

    assert 'applied.playerName = ShortName(UnitName("player"))' in self_block
    assert 'applied.classToken = select(2, UnitClass("player"))' in self_block
    assert 'applied.unitToken = "player"' in self_block


def test_interrupt_tracker_self_cast_canonicalizes_event_spell_ids():
    source = read("Modules/InterruptTracker.lua")

    event_start = source.index('elseif event == "UNIT_SPELLCAST_SUCCEEDED" then')
    event_end = source.index('    elseif event == "CHAT_MSG_ADDON" then', event_start)
    self_block = source[event_start:event_end]

    assert 'local canonicalSpellID = SpellDB.ResolveTrackedSpellID(spellID)' in self_block
    assert "registeredEntry.spellID ~= canonicalSpellID" in self_block
    assert ':ApplySelfCast(UnitGUID("player"), canonicalSpellID, now, now + cooldown)' in self_block


def test_interrupt_tracker_forward_declared_helpers_are_assigned_not_shadowed():
    source = read("Modules/InterruptTracker.lua")

    assert "local UpdateBarVisuals" in source
    assert "local ReLayout" in source
    assert "UpdateBarVisuals = function(bar, data)" in source
    assert "ReLayout = function()" in source
    assert "local function UpdateBarVisuals(bar, data)" not in source
    assert "local function ReLayout()" not in source


def test_interrupt_tracker_auto_registration_uses_kryos_style_auto_interrupt_resolution():
    source = read("Modules/InterruptTracker.lua")

    assert "SpellDB.ResolveAutoInterruptByContext" in source
    assert "return SpellDB.ResolveAutoInterruptByContext(specID, classToken, role, powerType)" in source


def test_interrupt_tracker_timer_format_matches_reference_rounding():
    source = read("Modules/InterruptTrackerModel.lua")

    assert 'return string.format("%.0fs", remaining), math.floor(remaining + 0.5)' in source
    assert 'math.floor(remaining)' not in source
    assert 'string.format("%.1f", remaining)' not in source


def test_interrupt_tracker_settings_shell_matches_tracker_controls():
    source = read("Modules/InterruptTracker.lua")

    assert '"Enable Interrupt Tracker"' in source
    assert '"Open Edit Mode"' in source
    assert '"Lock Tracker"' in source
    assert '"Reset Position"' in source
    assert 'addonRef.db.global.activeEditModule == "InterruptTracker"' in source
    assert '"Show Header"' in source
    assert '"Play Ready Sound"' in source
    assert '"Ready Sound"' in source
    assert '"Sound Channel"' in source
    assert '"Show in Raids"' not in source
    assert '"Show in Arena"' not in source
    assert '"Enable Party Sync"' not in source
    assert '"Strict Sync Mode"' not in source
    assert "OmniCD-style" not in source


def test_interrupt_tracker_registers_party_and_pet_watchers_without_party_spell_ids():
    source = read("Modules/InterruptTracker.lua")

    assert 'RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)' in source
    assert 'RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", petUnit)' in source
    assert "HandlePartyWatcher(unit)" in source
    assert "CanRecordWatcherTimestamp(ownerUnit)" in source
    assert "runtime.recentPartyCasts[shortName] = GetTime()" in source

    event_start = source.index('elseif event == "UNIT_SPELLCAST_SUCCEEDED" then')
    event_end = source.index('    elseif event == "CHAT_MSG_ADDON" then', event_start)
    event_block = source[event_start:event_end]

    assert 'if unit ~= "player" then return end' in event_block


def test_interrupt_tracker_emits_debug_logs_for_party_cast_and_correlation_paths():
    source = read("Modules/InterruptTracker.lua")

    assert 'addon:DebugLog("int", "party cast", shortName)' in source
    assert 'addon:DebugLog("int", "corr", bestName, "delta", string.format("%.3f", bestDelta))' in source
    assert 'addon:DebugLog("int", "corr", "self", "delta", string.format("%.3f", selfDelta))' in source
    assert 'addon:DebugLog("int", "corr", "miss")' in source


def test_interrupt_tracker_handles_hello_presence_and_kryos_style_solo_self_visibility():
    source = read("Modules/InterruptTracker.lua")

    assert 'messageType == "HELLO"' in source
    assert "HandleSyncHelloMessage" in source
    assert "AnnouncePresence" in source
    assert "ShouldDisplaySoloSelfBar()" in source
    assert "BuildRuntimeUnitsForDisplay()" in source
    assert 'PopulateBars(BuildRuntimeBarEntries())' in source


def test_interrupt_tracker_supports_dungeon_world_visibility_controls():
    source = read("Modules/InterruptTracker.lua")
    shared = read("Core/TrackerSettings.lua")

    for key in (
        "showInDungeon",
        "showInWorld",
        "hideOutOfCombat",
        "showReady",
        "tooltipOnHover",
    ):
        assert key in source

    assert "TrackerSettings.IsBarContextAllowed(db)" in source
    assert "GetInstanceInfo()" in shared
    assert "InCombatLockdown()" in source
    assert 'bar:SetScript("OnEnter", function(self)' in source
    assert 'bar:SetScript("OnLeave", function() GameTooltip:Hide() end)' in source


def test_interrupt_tracker_supports_manifest_replay_and_remaining_based_sync():
    source = read("Modules/InterruptTracker.lua")

    assert 'Sync.Send("INT_MANIFEST"' in source
    assert "payload.remaining" in source
    assert "HasManifestSpell(senderShort, spellID)" in source


def test_interrupt_tracker_registers_kryos_style_enemy_watchers_for_interrupt_correlation():
    source = read("Modules/InterruptTracker.lua")

    assert "enemyWatcherFrame:RegisterUnitEvent(" in source
    assert '"target", "focus"' in source
    for unit in ("boss1", "boss2", "boss3", "boss4", "boss5"):
        assert f'"{unit}"' in source

    assert 'local npUnit = "nameplate" .. i' in source
    assert 'RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", npUnit)' in source
    assert "runtime.lastCorrName = bestName" in source
    assert "runtime.lastSelfInterruptTime > 0" in source


def test_interrupt_tracker_treats_short_enemy_channel_stops_as_interrupt_correlation_events():
    source = read("Modules/InterruptTracker.lua")

    assert "enemyWatcherFrame:RegisterUnitEvent(" in source
    assert '"UNIT_SPELLCAST_CHANNEL_START"' in source
    assert '"UNIT_SPELLCAST_CHANNEL_STOP"' in source
    assert 'RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", npUnit)' in source
    assert 'RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", npUnit)' in source
    assert "local CHANNEL_MIN_DURATION" in source
    assert "HandleEnemyChannelStart(unit)" in source
    assert "HandleEnemyChannelStop(unit)" in source


def test_interrupt_tracker_ready_sound_support_is_optional_lsm_with_local_fallbacks():
    source = read("Modules/InterruptTracker.lua")

    assert 'LibStub and LibStub("LibSharedMedia-3.0", true)' in source
    assert "ready.mp3" in source
    assert "ready2.mp3" in source
    assert "function module:GetReadySoundOptions()" in source
    assert "PlayReadySound = function(soundPath, channel)" not in source
    assert "local function PlayReadySound(soundPath, channel)" in source


def test_interrupt_tracker_ready_sound_only_triggers_for_local_interrupt_ready_transition():
    source = read("Modules/InterruptTracker.lua")
    ticker_start = source.index("StartCooldownTicker = function(bar, data)")
    ticker_end = source.index("local function ShouldDisplaySoloSelfBar()", ticker_start)
    ticker_block = source[ticker_start:ticker_end]

    assert 'if data.unit == "player" and db.readySoundEnabled then' in ticker_block
    assert "PlayReadySound(" in ticker_block
    assert "editModePreview" in ticker_block


def test_interrupt_tracker_supports_optional_tracker_header():
    source = read("Modules/InterruptTracker.lua")
    shared = read("Core/TrackerSettings.lua")

    assert "showHeader = true" in shared
    assert "local function GetHeaderHeight()" in source
    assert "container.header" in source
    assert "RefreshHeaderLayout()" in source


def test_interrupt_tracker_resets_runtime_engine_and_cooldown_state_when_world_context_changes():
    source = read("Modules/InterruptTracker.lua")

    world_start = source.index('    elseif event == "PLAYER_ENTERING_WORLD" then')
    world_end = source.index('    elseif event == "CHALLENGE_MODE_START" then', world_start)
    world_block = source[world_start:world_end]

    challenge_start = world_end
    challenge_end = source.index('    elseif event == "GROUP_ROSTER_UPDATE" then', challenge_start)
    challenge_block = source[challenge_start:challenge_end]

    assert "runtime.engine:Reset()" in world_block
    assert "wipe(cooldownState)" in world_block
    assert "runtime.engine:Reset()" in challenge_block
    assert "wipe(cooldownState)" in challenge_block


def test_interrupt_tracker_uses_single_tracker_ticker_instead_of_per_bar_onupdate():
    source = read("Modules/InterruptTracker.lua")

    ticker_start = source.index("local trackerTicker = nil")
    ticker_end = source.index("local function ShouldDisplaySoloSelfBar()", ticker_start)
    ticker_block = source[ticker_start:ticker_end]

    assert "local function RefreshActiveCooldownBars()" in source
    assert "local function StartTrackerTicker()" in source
    assert 'trackerTicker = C_Timer.NewTicker(1, function()' in source
    assert 'bar:SetScript("OnUpdate", function(self)' not in ticker_block
    assert 'bar:SetScript("OnUpdate", nil)' not in ticker_block


def test_interrupt_tracker_keeps_bar_configuration_out_of_visual_refresh_path():
    source = read("Modules/InterruptTracker.lua")

    visual_start = source.index("UpdateBarVisuals = function(bar, data)")
    visual_end = source.index("-- Sort bars: ready bars first, cooling bars by remaining time", visual_start)
    visual_block = source[visual_start:visual_end]

    assert "ConfigureBar(bar)" not in visual_block


def test_interrupt_tracker_caches_spell_textures_for_bar_refresh():
    source = read("Modules/InterruptTracker.lua")

    assert "local spellTextureCache = {}" in source
    assert "local function GetCachedSpellTexture(spellID)" in source
    assert "spellTextureCache[spellID]" in source
    assert "bar.icon:SetTexture(GetCachedSpellTexture(data.spellID))" in source


def test_interrupt_tracker_relayout_only_repositions_bars_when_slot_changes():
    source = read("Modules/InterruptTracker.lua")

    relayout_start = source.index("ReLayout = function()")
    relayout_end = source.index("-- Create main container", relayout_start)
    relayout_block = source[relayout_start:relayout_end]

    assert "bar._lastLayoutIndex" in relayout_block
    assert "bar._lastGrowKey" in relayout_block
    assert "if bar._lastLayoutIndex ~= i or bar._lastGrowKey ~= growKey then" in relayout_block
