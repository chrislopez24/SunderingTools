# Owner-Authoritative Sync and Nameplate CC Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden owner-authoritative sync with owner-local `CooldownViewer` metadata and enrich `NameplateCrowdControl` from existing CC sync without guessing ambiguous targets.

**Architecture:** Keep the existing `CombatTrackSync` transport and module-specific runtime stores. Add one owner-local metadata helper around `C_CooldownViewer`, teach tracker manifests and self-casts to use it where available, and add a narrow correlation layer in `NameplateCrowdControl` that upgrades local unknown CC auras to spell-specific icons only when a unique sync candidate exists.

**Tech Stack:** Lua addon runtime, Blizzard addon APIs (`C_ChatInfo`, `C_CooldownViewer`, `C_UnitAuras`, `C_Spell`), existing project test slices in Lua and Python.

---

### Task 1: Add owner-local CooldownViewer metadata helper

**Files:**
- Create: `Core/CooldownViewerMeta.lua`
- Modify: `SunderingTools.toc`
- Test: `tests/core/test_cooldown_viewer_meta.lua`
- Test: `tests/test_cooldown_viewer_meta_runtime.py`

- [ ] **Step 1: Write the failing tests**

```lua
local Meta = dofile("Core/CooldownViewerMeta.lua")

local originalCooldownViewer = C_CooldownViewer
C_CooldownViewer = {
  GetCooldownViewerCooldownInfo = function(cooldownID)
    if cooldownID == 77 then
      return {
        cooldownID = 77,
        spellID = 2139,
        overrideSpellID = 12051,
        linkedSpellIDs = { 999001 },
        charges = true,
        category = 3,
      }
    end
  end,
  GetCooldownViewerCategorySet = function(category)
    if category == 3 then
      return { 77 }
    end
    return {}
  end,
}

local info = Meta.ResolveSpellMetadata(2139)
assert(info.spellID == 2139)
assert(info.overrideSpellID == 12051)
assert(info.hasCharges == true)

local reverse = Meta.ResolveSpellMetadata(999001)
assert(reverse.spellID == 2139)

C_CooldownViewer = originalCooldownViewer
```

```python
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "Core/CooldownViewerMeta.lua").read_text(encoding="utf-8")
assert "C_CooldownViewer" in source
assert "GetCooldownViewerCooldownInfo" in source
assert "_G.SunderingToolsCooldownViewerMeta" in source
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/core/test_cooldown_viewer_meta.lua`
Expected: fail because `Core/CooldownViewerMeta.lua` does not exist yet

Run: `python3 -m pytest -q tests/test_cooldown_viewer_meta_runtime.py`
Expected: fail because runtime slice references a file that does not exist yet

- [ ] **Step 3: Write the minimal implementation**

```lua
local Meta = {}

local bySpellID = {}
local loaded = false

local function indexCooldownInfo(cooldownInfo)
  if type(cooldownInfo) ~= "table" or type(cooldownInfo.spellID) ~= "number" then
    return
  end

  local record = {
    cooldownID = cooldownInfo.cooldownID,
    spellID = cooldownInfo.spellID,
    overrideSpellID = cooldownInfo.overrideSpellID,
    linkedSpellIDs = cooldownInfo.linkedSpellIDs or {},
    hasCharges = cooldownInfo.charges == true,
    category = cooldownInfo.category,
  }

  bySpellID[record.spellID] = record
  if type(record.overrideSpellID) == "number" and record.overrideSpellID > 0 then
    bySpellID[record.overrideSpellID] = record
  end
  for _, linkedSpellID in ipairs(record.linkedSpellIDs) do
    if type(linkedSpellID) == "number" and linkedSpellID > 0 then
      bySpellID[linkedSpellID] = record
    end
  end
end

local function ensureLoaded()
  if loaded then
    return
  end
  loaded = true

  if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
    return
  end

  for category = 1, 32 do
    for _, cooldownID in ipairs(C_CooldownViewer.GetCooldownViewerCategorySet(category, true) or {}) do
      indexCooldownInfo(C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID))
    end
  end
end

function Meta.ResolveSpellMetadata(spellID)
  ensureLoaded()
  return bySpellID[spellID]
end

_G.SunderingToolsCooldownViewerMeta = Meta
return Meta
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/core/test_cooldown_viewer_meta.lua`
Expected: `ok`

Run: `python3 -m pytest -q tests/test_cooldown_viewer_meta_runtime.py`
Expected: `1 passed`

- [ ] **Step 5: Commit**

```bash
git add Core/CooldownViewerMeta.lua SunderingTools.toc tests/core/test_cooldown_viewer_meta.lua tests/test_cooldown_viewer_meta_runtime.py
git commit -m "feat: add cooldown viewer metadata helper"
```

### Task 2: Use CooldownViewer metadata in owner-local manifests and self-casts

**Files:**
- Modify: `Modules/InterruptTracker.lua`
- Modify: `Modules/CrowdControlTracker.lua`
- Modify: `Modules/PartyDefensiveTracker.lua`
- Modify: `Modules/DefensiveRaidTracker.lua`
- Test: `tests/test_interrupt_tracker_runtime_slice.py`
- Test: `tests/test_party_defensive_tracker_runtime_slice.py`
- Test: `tests/test_defensive_raid_tracker_runtime_slice.py`
- Test: `tests/test_crowd_control_runtime_slice.py`

- [ ] **Step 1: Write the failing runtime slice assertions**

```python
source = read("Modules/InterruptTracker.lua")
assert "SunderingToolsCooldownViewerMeta" in source
assert "ResolveSpellMetadata" in source
```

Repeat equivalent assertions for `CrowdControlTracker.lua`, `PartyDefensiveTracker.lua`, and `DefensiveRaidTracker.lua`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest -q tests/test_interrupt_tracker_runtime_slice.py tests/test_party_defensive_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py tests/test_crowd_control_runtime_slice.py`
Expected: fail on missing metadata helper references

- [ ] **Step 3: Write the minimal implementation**

Use the helper defensively:

```lua
local CooldownViewerMeta = assert(
  _G.SunderingToolsCooldownViewerMeta,
  "SunderingToolsCooldownViewerMeta must load before InterruptTracker.lua"
)

local function ResolveLocalMetadataSpellID(spellID)
  local metadata = CooldownViewerMeta.ResolveSpellMetadata(spellID)
  if metadata and type(metadata.overrideSpellID) == "number" and metadata.overrideSpellID > 0 then
    return metadata.overrideSpellID
  end
  return metadata and metadata.spellID or spellID
end
```

Apply the helper only for:

- owner-local manifest building
- owner-local self-cast normalization
- optional charges support enrichment

Do not use it as remote runtime truth.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest -q tests/test_interrupt_tracker_runtime_slice.py tests/test_party_defensive_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py tests/test_crowd_control_runtime_slice.py`
Expected: passing runtime slices

- [ ] **Step 5: Commit**

```bash
git add Modules/InterruptTracker.lua Modules/CrowdControlTracker.lua Modules/PartyDefensiveTracker.lua Modules/DefensiveRaidTracker.lua tests/test_interrupt_tracker_runtime_slice.py tests/test_party_defensive_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py tests/test_crowd_control_runtime_slice.py
git commit -m "feat: use cooldown viewer metadata for owner-local sync"
```

### Task 3: Enrich Nameplate CC from existing CC sync

**Files:**
- Modify: `Modules/NameplateCrowdControl.lua`
- Modify: `tests/test_nameplate_crowd_control_runtime_slice.py`
- Create: `tests/core/test_nameplate_cc_sync_enrichment.lua`

- [ ] **Step 1: Write the failing tests**

```lua
local chunk = assert(loadfile("Modules/NameplateCrowdControl.lua"))
assert(chunk ~= nil)
```

Add runtime assertions that require:

```python
source = read("Modules/NameplateCrowdControl.lua")
assert "CHAT_MSG_ADDON" in source
assert "Sync.GetPrefix()" in source
assert "CC_UNKNOWN" in source
assert "ResolveSynchronizedPayload" in source
assert "GENERIC_CC_ICON" in source
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest -q tests/test_nameplate_crowd_control_runtime_slice.py`
Expected: fail on missing sync enrichment hooks

- [ ] **Step 3: Write the minimal implementation**

Add to `NameplateCrowdControl.lua`:

```lua
local Sync = assert(
  _G.SunderingToolsCombatTrackSync,
  "SunderingToolsCombatTrackSync must load before NameplateCrowdControl.lua"
)

local GENERIC_CC_ICON = "Interface\\Icons\\Spell_Frost_ChainsOfIce"
```

Implement:

- a short-lived queue of recent sync CC events by sender
- `CC_UNKNOWN` marker for local visible auras without safe icon/spell identity
- `ResolveSynchronizedPayload(unitToken, payload)` that upgrades an unknown aura only when a single recent sync candidate fits the time window
- generic icon fallback when the aura exists but no unique sync match does
- `CHAT_MSG_ADDON` handling for `CC` messages only

Do not render target-specific sync if there is no local aura on the nameplate.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest -q tests/test_nameplate_crowd_control_runtime_slice.py`
Expected: passing runtime slice

Run: `lua tests/core/test_nameplate_cc_sync_enrichment.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```bash
git add Modules/NameplateCrowdControl.lua tests/test_nameplate_crowd_control_runtime_slice.py tests/core/test_nameplate_cc_sync_enrichment.lua
git commit -m "feat: enrich nameplate cc from owner sync"
```

### Task 4: Verify end-to-end slices and docs

**Files:**
- Modify: `docs/superpowers/specs/2026-03-31-owner-authoritative-sync-and-nameplate-cc-enrichment-design.md`

- [ ] **Step 1: Run targeted verification**

Run:

```bash
lua tests/core/test_combat_track_sync.lua
lua tests/core/test_cooldown_viewer_meta.lua
lua tests/core/test_nameplate_cc_sync_enrichment.lua
python3 -m pytest -q tests/test_cooldown_viewer_meta_runtime.py tests/test_nameplate_crowd_control_runtime_slice.py tests/test_interrupt_tracker_runtime_slice.py tests/test_party_defensive_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py tests/test_crowd_control_runtime_slice.py
```

Expected:

- Lua tests print `ok`
- Python slices pass

- [ ] **Step 2: Update spec wording if implementation deviated**

If field names, tie-breakers, or fallback semantics differ from the design doc, update the spec immediately so it matches shipped behavior.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-03-31-owner-authoritative-sync-and-nameplate-cc-enrichment-design.md
git commit -m "docs: align sync enrichment spec with implementation"
```
