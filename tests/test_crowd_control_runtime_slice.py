from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_crowd_control_tracker_uses_shared_combat_track_core():
    source = read("Modules/CrowdControlTracker.lua")

    assert "_G.SunderingToolsCombatTrackSpellDB" in source
    assert "_G.SunderingToolsCombatTrackSync" in source
    assert "_G.SunderingToolsCombatTrackEngine" in source
    assert "_G.SunderingToolsPartyCrowdControlResolver" in source
    assert "engine = Engine.New()" in source
    assert 'kind = "CC"' in source


def test_crowd_control_tracker_registers_kryos_style_self_party_and_sync_paths():
    source = read("Modules/CrowdControlTracker.lua")
    model_source = read("Modules/CrowdControlTrackerModel.lua")

    assert "GetPrimaryCrowdControlForClass" in source
    assert "GetCrowdControlForClass" in model_source
    assert "IsSpellKnown" in source
    assert 'RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)' in source
    assert 'RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", petUnit)' in source
    assert 'Sync.Send("CC"' in source
    assert 'messageType ~= "CC"' in source


def test_crowd_control_tracker_uses_aura_detection_for_party_fallback_without_sync():
    source = read("Modules/CrowdControlTracker.lua")

    assert 'RegisterUnitEvent("UNIT_AURA", au)' in source
    assert "C_UnitAuras.GetAuraDataByIndex" in source
    assert "HasSecretRestrictions" in source
    assert "ResolveAppliedCrowdControl" in source
    assert "runtime.recentPartyCasts[shortName] = GetTime()" in source


def test_crowd_control_tracker_supports_dungeon_world_visibility_controls():
    source = read("Modules/CrowdControlTracker.lua")
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


def test_crowd_control_tracker_keeps_solo_self_visibility_and_filter_mode_rendering():
    source = read("Modules/CrowdControlTracker.lua")

    assert "ShouldDisplaySoloSelfBar()" in source
    assert "BuildRuntimeUnitsForDisplay()" in source
    assert "Model.FilterTrackedEntries" in source
    assert 'PopulateBars(BuildRuntimeBarEntries())' in source


def test_crowd_control_tracker_settings_shell_exposes_filter_mode_controls():
    source = read("Modules/CrowdControlTracker.lua")

    assert '"Crowd Control Tracker"' in source
    assert '"Enable Crowd Control Tracker"' in source
    assert '"Open Edit Mode"' in source
    assert '"Lock Tracker"' in source
    assert '"Reset Position"' in source
    assert 'addonRef.db.global.activeEditModule == "CrowdControlTracker"' in source
    assert '"Filter Mode"' in source
    assert '"Show Header"' in source
    assert '"Show in Raids"' not in source
    assert '"Show in Arena"' not in source
    assert '"Enable Party Sync"' not in source
    assert '"Strict Sync Mode"' not in source
    assert 'filterModes = { "ESSENTIALS", "ALL" }' in source


def test_crowd_control_tracker_pre_registers_remote_members_without_addon_presence():
    source = read("Modules/CrowdControlTracker.lua")

    assert "partyAddonUsers = {}" in source
    assert "partyManifests = {}" in source
    assert 'runtime.partyAddonUsers[senderShort] = true' in source

    refresh_start = source.index("local function RefreshRuntimeCrowdControlRegistration()")
    refresh_end = source.index("local function UpdateAnchorVisuals(enabled)", refresh_start)
    refresh_block = source[refresh_start:refresh_end]
    watcher_start = source.index("local function CanRecordWatcherTimestamp(ownerUnit)")
    watcher_end = source.index("local function HandlePartyWatcher(ownerUnit)", watcher_start)
    watcher_block = source[watcher_start:watcher_end]
    aura_start = source.index("local function DetectCrowdControlAuras(unit)")
    aura_end = source.index("local ccAuraUnits =", aura_start)
    aura_block = source[aura_start:aura_end]

    assert 'RegisterRuntimeCrowdControl("player", nil, nil, {' in refresh_block
    assert 'Sync.Send("CC_MANIFEST"' in source
    assert "IsStrictSyncMode" not in source
    assert 'RegisterRuntimeCrowdControl(unit, nil, nil, {' in refresh_block
    assert "runtime.partyAddonUsers[shortName]" not in watcher_block
    assert "runtime.partyAddonUsers[sourceShortName]" not in aura_block


def test_crowd_control_tracker_supports_optional_tracker_header():
    source = read("Modules/CrowdControlTracker.lua")
    shared = read("Core/TrackerSettings.lua")

    assert "showHeader = true" in shared
    assert "local function GetHeaderHeight()" in source
    assert "container.header" in source
    assert "RefreshHeaderLayout()" in source


def test_crowd_control_tracker_uses_single_tracker_ticker_instead_of_per_bar_onupdate():
    source = read("Modules/CrowdControlTracker.lua")

    ticker_start = source.index("local trackerTicker = nil")
    ticker_end = source.index("local function PopulateBars(entries)", ticker_start)
    ticker_block = source[ticker_start:ticker_end]

    assert "local function RefreshActiveCooldownBars()" in source
    assert "local function StartTrackerTicker()" in source
    assert 'trackerTicker = C_Timer.NewTicker(1, function()' in source
    assert 'bar:SetScript("OnUpdate", function(self)' not in ticker_block
    assert 'bar:SetScript("OnUpdate", nil)' not in ticker_block


def test_crowd_control_tracker_keeps_bar_configuration_out_of_visual_refresh_path():
    source = read("Modules/CrowdControlTracker.lua")

    visual_start = source.index("UpdateBarVisuals = function(bar, data)")
    visual_end = source.index("local function SortBars()", visual_start)
    visual_block = source[visual_start:visual_end]

    assert "ConfigureBar(bar)" not in visual_block


def test_crowd_control_tracker_caches_spell_textures_for_bar_refresh():
    source = read("Modules/CrowdControlTracker.lua")

    assert "local spellTextureCache = {}" in source
    assert "local function GetCachedSpellTexture(spellID)" in source
    assert "spellTextureCache[spellID]" in source
    assert "bar.icon:SetTexture(GetCachedSpellTexture(data.spellID))" in source


def test_crowd_control_tracker_relayout_only_repositions_bars_when_slot_changes():
    source = read("Modules/CrowdControlTracker.lua")

    relayout_start = source.index("ReLayout = function()")
    relayout_end = source.index("CreateContainer = function()", relayout_start)
    relayout_block = source[relayout_start:relayout_end]

    assert "bar._lastLayoutIndex" in relayout_block
    assert "bar._lastGrowKey" in relayout_block
    assert "if bar._lastLayoutIndex ~= i or bar._lastGrowKey ~= growKey then" in relayout_block


def test_crowd_control_tracker_coalesces_visual_refreshes_instead_of_rebuilding_per_event():
    source = read("Modules/CrowdControlTracker.lua")

    apply_start = source.index("local function ApplyRuntimeCooldownEntry(entry)")
    apply_end = source.index("local function BuildPreviewBars()", apply_start)
    apply_block = source[apply_start:apply_end]

    assert "local function MarkTrackerDirty()" in source
    assert "local function FlushDirtyTracker()" in source
    assert "runtime.needsVisualRefresh = true" in source
    assert "MarkTrackerDirty()" in apply_block
    assert "UpdatePartyData()" not in apply_block


def test_crowd_control_tracker_keeps_party_sync_paths_while_engine_kind_lookup_is_optimized():
    tracker_source = read("Modules/CrowdControlTracker.lua")
    engine_source = read("Core/CombatTrackEngine.lua")

    kind_start = engine_source.index("function Engine:GetEntriesByKind(kind)")
    kind_end = engine_source.index("function Engine:GetBestEntryForPlayer", kind_start)
    kind_block = engine_source[kind_start:kind_end]

    assert "for _, entry in pairs(self.entries) do" in kind_block
    assert "self:GetEntries()" not in kind_block

    assert 'Sync.Send("CC"' in tracker_source
    assert 'Sync.Send("CC_MANIFEST"' in tracker_source
    assert "HandleSyncCrowdControlMessage" in tracker_source
    assert ":ApplySyncState(" in tracker_source


def test_crowd_control_tracker_supports_manifest_and_remaining_based_replay():
    source = read("Modules/CrowdControlTracker.lua")

    assert "payload.remaining" in source
    assert "HasManifestSpell(senderShort, spellID)" in source
