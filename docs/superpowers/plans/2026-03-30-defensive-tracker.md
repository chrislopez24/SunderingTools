# Defensive Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build sync-first party defensive tracking with attached party-frame icons plus a standalone raid-defensive tracker.

**Architecture:** Extend the shared combat tracking engine and sync protocol with defensive-specific metadata, add a defensive spell catalog seeded from OmniCD, then build two presentation layers: an owner-attached party-frame surface for normal defensives and a standalone tracker for raid defensives. Use local self cooldown state as truth, sync as the primary remote signal, and visible auras/public casts only as lower-confidence fallbacks.

**Tech Stack:** WoW Lua addon modules, Blizzard unit-frame APIs, addon comms, Python source-slice tests, existing Lua unit-style tests.

---

### Task 1: Defensive catalog and sync payloads

**Files:**
- Modify: `Core/CombatTrackSpellDB.lua`
- Modify: `Core/CombatTrackSync.lua`
- Modify: `Core/CombatTrackEngine.lua`
- Create: `tests/core/test_defensive_spell_db.lua`
- Create: `tests/core/test_defensive_sync.lua`
- Create: `tests/test_defensive_spell_db_runtime_slice.py`

- [ ] **Step 1: Write the failing tests**

```lua
local SpellDB = dofile("Core/CombatTrackSpellDB.lua")

local ams = SpellDB.GetDefensiveSpell(48707)
assert(ams ~= nil, "Anti-Magic Shell should be registered as a defensive spell")
assert(ams.kind == "DEF", "personal defensives should use DEF kind")
assert(ams.auraSpellID == 48707, "AMS should expose its visible aura spell")

local amz = SpellDB.GetDefensiveSpell(51052)
assert(amz ~= nil and amz.kind == "RAID_DEF", "AMZ should be registered as a raid defensive")

local dkSpells = SpellDB.GetDefensiveSpellsForClass("DEATHKNIGHT")
assert(#dkSpells >= 3, "death knights should expose multiple party-frame defensives")
```

```lua
local Sync = dofile("Core/CombatTrackSync.lua")

local encodedManifest = Sync.Encode("DEF_MANIFEST", {
  spells = { 48707, 48792, 55233 },
})
local kind, payload = Sync.Decode(encodedManifest)
assert(kind == "DEF_MANIFEST", "manifest message type should round-trip")
assert(payload.spells[1] == 48707 and payload.spells[3] == 55233, "manifest spell ids should survive encoding")

local encodedState = Sync.Encode("DEF_STATE", {
  spellID = 48707,
  cd = 60,
  charges = 1,
  readyAt = 123.5,
})
local stateType, statePayload = Sync.Decode(encodedState)
assert(stateType == "DEF_STATE", "state message type should round-trip")
assert(statePayload.charges == 1, "defensive state should include charges")
assert(statePayload.readyAt == 123.5, "defensive state should include readyAt")
```

```python
def test_defensive_spell_db_runtime_slice():
    source = read("Core/CombatTrackSpellDB.lua")
    assert "GetDefensiveSpell" in source
    assert "GetDefensiveSpellsForClass" in source
    assert "48707" in source
    assert "51052" in source
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rtk test "lua tests/core/test_defensive_spell_db.lua"`
Expected: FAIL because defensive spell helpers do not exist yet

Run: `rtk test "lua tests/core/test_defensive_sync.lua"`
Expected: FAIL because defensive sync payloads do not exist yet

Run: `rtk pytest tests/test_defensive_spell_db_runtime_slice.py -q`
Expected: FAIL because the source does not contain the defensive API yet

- [ ] **Step 3: Write minimal implementation**

```lua
-- Core/CombatTrackSpellDB.lua
local defensiveSpells = {}
local defensiveByClass = {}

local function RegisterDefensiveSpell(spellID, data)
  local entry = RegisterTrackedSpell(spellID, data.name, data.kind, data)
  defensiveSpells[spellID] = entry
  defensiveByClass[data.classToken] = defensiveByClass[data.classToken] or {}
  defensiveByClass[data.classToken][#defensiveByClass[data.classToken] + 1] = entry
  return entry
end

function SpellDB.GetDefensiveSpell(spellID)
  return defensiveSpells[trackedSpellAliases[spellID] or spellID]
end

function SpellDB.GetDefensiveSpellsForClass(classToken)
  local entries = defensiveByClass[classToken] or {}
  local copy = {}
  for index, entry in ipairs(entries) do
    copy[index] = entry
  end
  return copy
end
```

```lua
-- Core/CombatTrackSync.lua
if messageType == "DEF_MANIFEST" then
  return table.concat({
    "DEF_MANIFEST",
    table.concat(payload.spells or {}, ","),
  }, ":")
end

if messageType == "DEF_STATE" then
  return table.concat({
    "DEF_STATE",
    tostring(payload.spellID or 0),
    tostring(payload.cd or 0),
    tostring(payload.charges or 0),
    tostring(payload.readyAt or 0),
  }, ":")
end
```

```lua
-- Core/CombatTrackEngine.lua
function Engine:ApplySyncState(playerGUID, spellID, fields)
  fields = fields or {}
  return self:UpsertEntry({
    key = resolveKey(playerGUID, spellID),
    playerGUID = playerGUID,
    spellID = spellID,
    source = "sync",
    startTime = fields.startTime,
    readyAt = fields.readyAt,
    charges = fields.charges,
    kind = fields.kind,
  })
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `rtk test "lua tests/core/test_defensive_spell_db.lua"`
Expected: PASS

Run: `rtk test "lua tests/core/test_defensive_sync.lua"`
Expected: PASS

Run: `rtk pytest tests/test_defensive_spell_db_runtime_slice.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Core/CombatTrackSpellDB.lua Core/CombatTrackSync.lua Core/CombatTrackEngine.lua tests/core/test_defensive_spell_db.lua tests/core/test_defensive_sync.lua tests/test_defensive_spell_db_runtime_slice.py
rtk git commit -m "feat: add defensive spell catalog and sync payloads"
```

### Task 2: Standalone raid defensive tracker

**Files:**
- Create: `Modules/DefensiveRaidTrackerModel.lua`
- Create: `Modules/DefensiveRaidTracker.lua`
- Modify: `SunderingTools.toc`
- Modify: `tests/test_packaging.py`
- Create: `tests/test_defensive_raid_tracker_runtime_slice.py`
- Create: `tests/modules/test_defensive_raid_tracker.lua`

- [ ] **Step 1: Write the failing tests**

```python
def test_defensive_raid_tracker_is_packaged():
    toc = read("SunderingTools.toc")
    assert "Modules\\DefensiveRaidTrackerModel.lua" in toc
    assert "Modules\\DefensiveRaidTracker.lua" in toc

def test_defensive_raid_tracker_runtime_slice():
    source = read("Modules/DefensiveRaidTracker.lua")
    assert 'key = "DefensiveRaidTracker"' in source
    assert '"RAID_DEF"' in source
    assert "Sync.GetPrefix()" in source
```

```lua
local Model = dofile("Modules/DefensiveRaidTrackerModel.lua")
local bars = Model.BuildPreviewBars()
assert(#bars > 0, "raid defensive tracker should expose preview bars")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rtk pytest tests/test_defensive_raid_tracker_runtime_slice.py -q`
Expected: FAIL because the module files are not present

Run: `rtk test "lua tests/modules/test_defensive_raid_tracker.lua"`
Expected: FAIL because the model file does not exist yet

- [ ] **Step 3: Write minimal implementation**

```lua
-- Modules/DefensiveRaidTrackerModel.lua
local Model = {}

function Model.GetDefaultPosition()
  return 0, -120
end

function Model.BuildPreviewBars()
  return {
    { key = "amz", name = "AMZ", spellID = 51052, cd = 120, previewRemaining = 32, previewText = "32" },
    { key = "barrier", name = "Barrier", spellID = 62618, cd = 180, previewRemaining = 0, previewText = "Ready" },
  }
end

_G.SunderingToolsDefensiveRaidTrackerModel = Model
return Model
```

```lua
-- Modules/DefensiveRaidTracker.lua
local module = {
  key = "DefensiveRaidTracker",
  label = "Raid Defensive Tracker",
  description = "Track raid defensives, sync party data, and adjust layout.",
  order = 30,
  defaults = { enabled = true, syncEnabled = true, previewWhenSolo = true },
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `rtk pytest tests/test_defensive_raid_tracker_runtime_slice.py -q`
Expected: PASS

Run: `rtk test "lua tests/modules/test_defensive_raid_tracker.lua"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Modules/DefensiveRaidTrackerModel.lua Modules/DefensiveRaidTracker.lua SunderingTools.toc tests/test_packaging.py tests/test_defensive_raid_tracker_runtime_slice.py tests/modules/test_defensive_raid_tracker.lua
rtk git commit -m "feat: add raid defensive tracker"
```

### Task 3: Party-frame attached defensive icons

**Files:**
- Create: `Modules/PartyDefensiveTrackerModel.lua`
- Create: `Modules/PartyDefensiveTracker.lua`
- Modify: `SunderingTools.toc`
- Modify: `SunderingTools.lua`
- Create: `tests/test_party_defensive_tracker_runtime_slice.py`
- Create: `tests/modules/test_party_defensive_tracker.lua`

- [ ] **Step 1: Write the failing tests**

```python
def test_party_defensive_tracker_runtime_slice():
    source = read("Modules/PartyDefensiveTracker.lua")
    assert 'key = "PartyDefensiveTracker"' in source
    assert "CompactPartyFrame" in source or "CompactUnitFrame" in source
    assert "DEF_MANIFEST" in source
    assert "DEF_STATE" in source
```

```lua
local Model = dofile("Modules/PartyDefensiveTrackerModel.lua")
local entries = Model.BuildPreviewIcons()
assert(#entries > 0, "party defensive tracker should build preview icons")
assert(entries[1].spellID ~= nil, "preview icons should carry spell ids")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rtk pytest tests/test_party_defensive_tracker_runtime_slice.py -q`
Expected: FAIL because the module does not exist yet

Run: `rtk test "lua tests/modules/test_party_defensive_tracker.lua"`
Expected: FAIL because the model file does not exist yet

- [ ] **Step 3: Write minimal implementation**

```lua
-- Modules/PartyDefensiveTrackerModel.lua
local Model = {}

function Model.BuildPreviewIcons()
  return {
    { key = "dk-ams", spellID = 48707, ready = false, remaining = 18 },
    { key = "dk-ibf", spellID = 48792, ready = true, remaining = 0 },
  }
end

_G.SunderingToolsPartyDefensiveTrackerModel = Model
return Model
```

```lua
-- Modules/PartyDefensiveTracker.lua
local module = {
  key = "PartyDefensiveTracker",
  label = "Party Defensive Tracker",
  description = "Attach party defensive cooldown icons to Blizzard party frames.",
  order = 25,
  defaults = { enabled = true, syncEnabled = true, iconSize = 18, maxIcons = 4 },
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `rtk pytest tests/test_party_defensive_tracker_runtime_slice.py -q`
Expected: PASS

Run: `rtk test "lua tests/modules/test_party_defensive_tracker.lua"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Modules/PartyDefensiveTrackerModel.lua Modules/PartyDefensiveTracker.lua SunderingTools.toc SunderingTools.lua tests/test_party_defensive_tracker_runtime_slice.py tests/modules/test_party_defensive_tracker.lua
rtk git commit -m "feat: add party defensive frame attachments"
```

### Task 4: End-to-end integration and regression verification

**Files:**
- Modify: `tests/test_packaging.py`
- Modify: `tests/core/test_settings_model.lua`
- Modify: `tests/core/test_sunderingtools_support.lua`
- Modify: any module files touched by previous tasks as needed

- [ ] **Step 1: Write the failing integration tests**

```python
def test_packaging_includes_defensive_modules():
    toc = read("SunderingTools.toc")
    assert "Modules\\PartyDefensiveTracker.lua" in toc
    assert "Modules\\DefensiveRaidTracker.lua" in toc
```

```lua
local SettingsModel = dofile("Core/SettingsModel.lua")
local sections = SettingsModel.BuildSections({
  { key = "PartyDefensiveTracker", label = "Party Defensive Tracker", description = "Attach party defensive cooldown icons to Blizzard party frames.", order = 25 },
  { key = "DefensiveRaidTracker", label = "Raid Defensive Tracker", description = "Track raid defensives, sync party data, and adjust layout.", order = 30 },
})
assert(sections[2].key == "PartyDefensiveTracker", "party defensive tracker should sort before raid defensive tracker")
assert(sections[3].key == "DefensiveRaidTracker", "raid defensive tracker should sort after party defensive tracker")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rtk pytest tests/test_packaging.py -q`
Expected: FAIL until the TOC and tests include the new modules

Run: `rtk test "lua tests/core/test_settings_model.lua"`
Expected: FAIL until module ordering and descriptions are updated

- [ ] **Step 3: Implement the integration glue**

```lua
-- SunderingTools.toc
Modules\DefensiveRaidTrackerModel.lua
Modules\DefensiveRaidTracker.lua
Modules\PartyDefensiveTrackerModel.lua
Modules\PartyDefensiveTracker.lua
```

```lua
-- SunderingTools.lua
local editModePriority = {
  "InterruptTracker",
  "CrowdControlTracker",
  "PartyDefensiveTracker",
  "DefensiveRaidTracker",
  "BloodlustSound",
}
```

- [ ] **Step 4: Run the focused test suite**

Run: `rtk test "lua tests/core/test_combat_track_engine.lua"`
Expected: PASS

Run: `rtk test "lua tests/core/test_combat_track_sync.lua"`
Expected: PASS

Run: `rtk pytest tests/test_packaging.py tests/test_party_defensive_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py tests/test_defensive_spell_db_runtime_slice.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add SunderingTools.toc SunderingTools.lua tests/test_packaging.py tests/core/test_settings_model.lua tests/core/test_sunderingtools_support.lua
rtk git commit -m "feat: integrate defensive trackers"
```
