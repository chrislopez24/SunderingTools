# SunderingTools Debug Mode, CC DB Cleanup, and Project Organization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cheap global debug mode, prune zero-cooldown CC entries while refining `essential`, reorganize assets into clearer folders, and ship the addon as version `0.0.1`.

**Architecture:** The addon shell owns a single debug logging helper keyed off `db.global.debugMode`, the crowd control spell DB remains the single tracker-facing source of CC metadata but only for cooldown-based entries, and asset moves are handled as a path-preserving repo cleanup with updated references in Lua, tests, and packaging metadata.

**Tech Stack:** Lua addon code, Python text-based tests, GitHub Actions BigWigs packager.

---

## File Structure

- Modify: `SunderingTools.lua`
  - Add `debugMode` global default and the shared debug logger.
- Modify: `Settings.lua`
  - Add the `Debug Mode` control in the `General` page.
- Modify: `Core/CombatTrackSpellDB.lua`
  - Filter out `cd <= 0` crowd control entries and redefine `essential` curation.
- Modify: `Modules/InterruptTracker.lua`
  - Update ready sound asset paths and add event-driven debug traces where useful.
- Modify: `Modules/CrowdControlTracker.lua`
  - Add event-driven debug traces where useful and rely on the cleaned CC DB.
- Modify: `Modules/BloodlustSound.lua`
  - Update moved texture paths if needed.
- Modify: `MinimapButton.lua`
  - Update moved texture paths if needed.
- Modify: `SunderingTools.toc`
  - Set addon version to `0.0.1` and keep packaging references stable.
- Create/Move: `assets/icons/logo-minimap.tga`
- Create/Move: `assets/art/pedro.tga`
- Possibly keep: `sounds/ready.mp3`, `sounds/ready2.mp3`
- Modify: `tests/core/test_sunderingtools_support.lua`
  - Cover `debugMode` default and logger-safe initialization.
- Modify: `tests/core/test_combat_track_spell_db.lua`
  - Cover zero-cooldown CC pruning, `essential` semantics, and primary CC fallback.
- Modify: `tests/test_settings_ui_redesign.py`
  - Assert the settings UI exposes the debug toggle.
- Modify: `tests/test_bloodlust_icon_assets.py`
  - Assert moved asset paths exist.
- Modify: `tests/test_interrupt_ready_sound_assets.py`
  - Keep sound asset assertions aligned with final layout.
- Modify: `tests/test_review_fixes.py`
  - Update hard-coded path expectations as needed.

### Task 1: Lock the expected behavior in tests

**Files:**
- Modify: `tests/core/test_sunderingtools_support.lua`
- Modify: `tests/core/test_combat_track_spell_db.lua`
- Modify: `tests/test_settings_ui_redesign.py`
- Modify: `tests/test_bloodlust_icon_assets.py`
- Modify: `tests/test_review_fixes.py`

- [ ] **Step 1: Write the failing Lua test for the new global debug default**

```lua
local addon = loadAddon()
addon:BuildDefaults()
local defaults = addon:BuildDefaults()
assert(defaults.global.debugMode == false, "debug mode should default to false")
```

- [ ] **Step 2: Run the Lua test to verify it fails**

Run: `rtk proxy bash -lc 'cd /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools && lua tests/core/test_sunderingtools_support.lua'`
Expected: FAIL because `debugMode` is not present yet.

- [ ] **Step 3: Write the failing spell DB tests**

```lua
assert(SpellDB.GetTrackedSpell(118) == nil, "zero-cooldown polymorph should not be tracked")
assert(SpellDB.GetTrackedSpell(5782) == nil, "zero-cooldown fear should not be tracked")

local evokerPrimary = SpellDB.GetPrimaryCrowdControlForClass("EVOKER")
assert(evokerPrimary.spellID == 370665, "evoker primary CC should fall back to the first cooldown-based spell")

for _, spell in ipairs(SpellDB.FilterCrowdControl("ESSENTIALS")) do
  assert((spell.cd or 0) > 0, "essential CC entries must have a real cooldown")
end
```

- [ ] **Step 4: Run the spell DB test to verify it fails**

Run: `rtk proxy bash -lc 'cd /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools && lua tests/core/test_combat_track_spell_db.lua'`
Expected: FAIL because zero-cooldown CC entries are still tracked and current essentials include zero-cooldown spells.

- [ ] **Step 5: Write the failing textual/UI tests**

```python
assert 'Debug Mode' in source
assert 'debugMode' in source
assert (ROOT / "assets" / "art" / "pedro.tga").exists()
assert (ROOT / "assets" / "icons" / "logo-minimap.tga").exists()
```

- [ ] **Step 6: Run the targeted Python tests to verify they fail**

Run: `rtk pytest /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_settings_ui_redesign.py /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_bloodlust_icon_assets.py /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_review_fixes.py`
Expected: FAIL on the missing debug toggle and old asset paths.

### Task 2: Implement the cheap global debug mode

**Files:**
- Modify: `SunderingTools.lua`
- Modify: `Settings.lua`
- Test: `tests/core/test_sunderingtools_support.lua`
- Test: `tests/test_settings_ui_redesign.py`

- [ ] **Step 1: Add the minimal debug default and logger in the addon shell**

```lua
global = {
  minimap = {
    hide = false,
    angle = 135,
    unlocked = false,
  },
  debugMode = false,
  editMode = false,
  activeEditModule = nil,
}

function addon:IsDebugEnabled()
  return self.db and self.db.global and self.db.global.debugMode == true
end

function addon:SetDebugEnabled(enabled)
  if not (self.db and self.db.global) then
    return
  end
  self.db.global.debugMode = enabled and true or false
end

function addon:DebugLog(scope, ...)
  if not self:IsDebugEnabled() then
    return
  end

  local parts = {}
  for index = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(index, ...))
  end
  print(string.format("|cff5fd7ffSunderingTools[%s]|r %s", tostring(scope or "debug"), table.concat(parts, " ")))
end
```

- [ ] **Step 2: Add the minimal settings toggle**

```lua
local debugBox = helpers:CreateInlineCheckbox(content, "Debug Mode", addon:IsDebugEnabled(), function(checked)
  addon:SetDebugEnabled(checked)
end)
debugBox:SetPoint("TOPLEFT", systemBody, "BOTTOMLEFT", 0, -12)
```

- [ ] **Step 3: Add low-cost event-driven traces only**

```lua
addon:DebugLog("init", "player login complete")
addon:DebugLog("sync", "sent interrupt", canonicalSpellID, cooldown)
addon:DebugLog("cc", "registered self cast", spellID, trackedSpell.cd)
```

- [ ] **Step 4: Run the targeted Lua and Python tests**

Run: `rtk proxy bash -lc 'cd /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools && lua tests/core/test_sunderingtools_support.lua && pytest tests/test_settings_ui_redesign.py -q'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SunderingTools.lua Settings.lua tests/core/test_sunderingtools_support.lua tests/test_settings_ui_redesign.py
git commit -m "feat: add global debug mode"
```

### Task 3: Clean the CC spell DB and preserve tracker compatibility

**Files:**
- Modify: `Core/CombatTrackSpellDB.lua`
- Modify: `Modules/CrowdControlTracker.lua`
- Modify: `Modules/CrowdControlTrackerModel.lua`
- Test: `tests/core/test_combat_track_spell_db.lua`
- Test: `tests/modules/test_crowd_control_tracker.lua`

- [ ] **Step 1: Filter zero-cooldown CC entries during registration**

```lua
local function RegisterCrowdControl(classToken, spellID, name, cd, essential)
  if type(cd) ~= "number" or cd <= 0 then
    return nil
  end

  local entry = RegisterTrackedSpell(spellID, name, "CC", {
    cd = cd,
    essential = essential == true,
    classToken = classToken,
  })
```

- [ ] **Step 2: Make primary CC fallback deterministic**

```lua
if entry.essential and not primaryCrowdControlByClass[classToken] then
  primaryCrowdControlByClass[classToken] = entry
elseif not primaryCrowdControlByClass[classToken] then
  primaryCrowdControlByClass[classToken] = entry
end
```

- [ ] **Step 3: Re-curate essentials so they are cooldown-based tactical defaults**

```lua
EVOKER = {
  { spellID = 370665, cd = 30, name = "Oppressing Roar", essential = true },
  { spellID = 358385, cd = 30, name = "Landslide" },
}
```

- [ ] **Step 4: Keep model behavior aligned with the new DB semantics**

```lua
local primary = SpellDB.GetPrimaryCrowdControlForClass(classToken)
if not primary then
  return {}
end
return { primary }
```

- [ ] **Step 5: Run the targeted CC tests**

Run: `rtk proxy bash -lc 'cd /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools && lua tests/core/test_combat_track_spell_db.lua && lua tests/modules/test_crowd_control_tracker.lua && pytest tests/test_crowd_control_runtime_slice.py -q'`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Core/CombatTrackSpellDB.lua Modules/CrowdControlTracker.lua Modules/CrowdControlTrackerModel.lua tests/core/test_combat_track_spell_db.lua tests/modules/test_crowd_control_tracker.lua tests/test_crowd_control_runtime_slice.py
git commit -m "fix: trim crowd control tracker spell db"
```

### Task 4: Reorganize assets and package metadata

**Files:**
- Modify: `MinimapButton.lua`
- Modify: `Modules/BloodlustSound.lua`
- Modify: `Modules/InterruptTracker.lua`
- Modify: `SunderingTools.toc`
- Move: `logo-minimap.tga -> assets/icons/logo-minimap.tga`
- Move: `pedro.tga -> assets/art/pedro.tga`
- Test: `tests/test_bloodlust_icon_assets.py`
- Test: `tests/test_interrupt_ready_sound_assets.py`
- Test: `tests/test_review_fixes.py`

- [ ] **Step 1: Move the visual assets into clearer folders**

```bash
mkdir -p assets/icons assets/art
mv logo-minimap.tga assets/icons/logo-minimap.tga
mv pedro.tga assets/art/pedro.tga
```

- [ ] **Step 2: Update Lua references**

```lua
local MINIMAP_LOGO_TEXTURE = "Interface\\AddOns\\SunderingTools\\assets\\icons\\logo-minimap.tga"
local BL_ICON_PEDRO = "Interface\\AddOns\\SunderingTools\\assets\\art\\pedro.tga"
```

- [ ] **Step 3: Version the addon for first public release**

```toc
## Version: 0.0.1
```

- [ ] **Step 4: Run the targeted asset and packaging tests**

Run: `rtk pytest /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_bloodlust_icon_assets.py /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_interrupt_ready_sound_assets.py /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_review_fixes.py /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_packaging.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add assets MinimapButton.lua Modules/BloodlustSound.lua Modules/InterruptTracker.lua SunderingTools.toc tests/test_bloodlust_icon_assets.py tests/test_interrupt_ready_sound_assets.py tests/test_review_fixes.py tests/test_packaging.py
git commit -m "chore: organize assets for first public release"
```

### Task 5: Final verification and publication

**Files:**
- Modify: repository metadata as needed for remote publication

- [ ] **Step 1: Run the full local verification suite**

Run: `rtk proxy bash -lc 'cd /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools && lua tests/run.lua && pytest tests -q'`
Expected: PASS with no failing tests.

- [ ] **Step 2: Review the final diff and git state**

Run: `rtk git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools status --short`
Expected: only intended files remain modified before the final publish commit.

- [ ] **Step 3: Create the final publish commit**

```bash
git add docs/superpowers/specs/2026-03-30-debug-mode-cc-db-and-project-organization-design.md docs/superpowers/plans/2026-03-30-debug-mode-cc-db-and-project-organization.md
git commit -m "feat: ship sunderingtools v0.0.1"
```

- [ ] **Step 4: Create or update the public GitHub remote and push**

Run: `rtk proxy bash -lc 'cd /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools && gh repo create chrislopez24/SunderingTools --public --source=. --remote=origin --push'`
Expected: repo created under `chrislopez24` and `main` pushed.

- [ ] **Step 5: Push the release tag and confirm the workflow starts**

Run: `rtk proxy bash -lc 'cd /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools && git tag v0.0.1 && git push origin v0.0.1 && gh run list --limit 5'`
Expected: tag push succeeds and the `Release` workflow appears in the recent runs list.
