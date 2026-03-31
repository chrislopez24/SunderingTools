# Tracking And Settings Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver reliable interrupt, CC, and defensive tracking for Mythic+ and world play while simplifying SunderingTools settings to a smaller, cleaner, more automatic model.

**Architecture:** Replace fragile tracker-local detection with dedicated watcher/resolver/fallback runtime units, borrow stronger logic from Kryos, LoxxInterruptTracker, MiniCC, and OmniCD where they are superior, and consolidate settings so shared bar trackers use one structural settings model while keeping user-facing tracker presentations distinct.

**Tech Stack:** WoW Lua addon modules, Blizzard aura/chat APIs, local reference addons one directory above the repo, Lua unit/runtime tests, Python runtime-slice tests, git worktree workflow.

---

## Reference Sources

- `../KryosDungeonTool v2.14.5/KryosDungeonTool/UI/InterruptTab.lua`
- `../LoxxInterruptTracker/LoxxInterruptTracker.lua`
- `../MiniCC/Core/UnitAuraWatcher.lua`
- `../MiniCC/Modules/FriendlyCooldownTrackerModule.lua`
- `../OmniCD/` as supporting reference when runtime/state architecture needs a tie-breaker

## User-Facing Rules

- Keep tracker presentation recognizable.
- Keep `InterruptTracker`, `CrowdControlTracker`, `PartyDefensiveTracker`, and `DefensiveRaidTracker` as separate visible modules.
- Support only `Dungeon` and `World` in visible tracker settings.
- Remove visible `Raid`, `Arena`, `sync`, and `strict sync` toggles.
- Keep `Debug Mode` visible.
- Give `NameplateCrowdControl` its own settings with preview.

## File Structure

- Create: `Core/PartyCrowdControlAuraWatcher.lua`
  Purpose: secret-safe watcher with lifecycle cleanup, diffing, and external classification hooks.
- Create: `Core/PartyCrowdControlResolver.lua`
  Purpose: cooldown attribution/confidence layer for CC runtime state.
- Create: `Core/PartyDefensiveAuraFallback.lua`
  Purpose: aura-driven defensive fallback state.
- Create: `Core/TrackerSettings.lua`
  Purpose: shared helpers/defaults for bar-based tracker settings.
- Create: `Modules/NameplateCrowdControl.lua`
  Purpose: active CC on nameplates with preview/settings.
- Modify: `Modules/CrowdControlTracker.lua`
- Modify: `Modules/InterruptTracker.lua`
- Modify: `Modules/PartyDefensiveTracker.lua`
- Modify: `Modules/DefensiveRaidTracker.lua`
- Modify: `Core/CombatTrackEngine.lua`
- Modify: `Core/CombatTrackSpellDB.lua`
- Modify: `Settings.lua`
- Modify: `SunderingTools.lua`
- Modify: `SunderingTools.toc`
- Modify: touched tests under `tests/core/`, `tests/modules/`, and runtime-slice Python tests
- Modify: `README.md` if the user-visible tracker/settings model needs updated description

### Task 1: Harden And Finish The Party CC Aura Watcher

**Files:**
- Modify: `Core/PartyCrowdControlAuraWatcher.lua`
- Modify: `tests/core/test_party_crowd_control_aura_watcher.lua`
- Modify: `tests/test_nameplate_crowd_control_runtime_slice.py` only if needed

- [ ] **Step 1: Write failing watcher regression tests**

Add cases for:

- secret `expirationTime` should not error and should redact remaining to `0`
- unchanged snapshot should not emit noisy `CC_UPDATED`
- empty snapshot should emit `CC_REMOVED`
- explicit cleanup/removal API for recycled unit tokens

- [ ] **Step 2: Run watcher tests to verify they fail**

Run: `rtk test "./.tools/lua/bin/lua tests/core/test_party_crowd_control_aura_watcher.lua"`
Expected: FAIL on the newly added regression assertions

- [ ] **Step 3: Implement minimal watcher hardening**

Required changes:

- sanitize `expirationTime` before arithmetic
- emit `CC_UPDATED` only when a tracked payload actually changed
- add lifecycle cleanup API for unit token recycling
- preserve current secret-safe classification behavior

- [ ] **Step 4: Run focused verification**

Run: `rtk test "./.tools/lua/bin/lua tests/core/test_party_crowd_control_aura_watcher.lua"`
Expected: PASS

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_nameplate_crowd_control_runtime_slice.py -q'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Core/PartyCrowdControlAuraWatcher.lua tests/core/test_party_crowd_control_aura_watcher.lua tests/test_nameplate_crowd_control_runtime_slice.py
rtk git commit -m "fix: harden party cc aura watcher"
```

### Task 2: Add CC Resolver And Rebuild CrowdControlTracker Around It

**Files:**
- Create: `Core/PartyCrowdControlResolver.lua`
- Modify: `Modules/CrowdControlTracker.lua`
- Modify: `Core/CombatTrackEngine.lua`
- Modify: `Core/CombatTrackSpellDB.lua`
- Create: `tests/core/test_party_crowd_control_resolver.lua`
- Modify: `tests/modules/test_crowd_control_tracker.lua`
- Modify: `tests/test_crowd_control_runtime_slice.py`

- [ ] **Step 1: Write failing tests**

Cover:

- direct aura attribution creates application-time cooldown state
- restricted-mode correlation falls back to class-primary CC with medium confidence
- resolver rejects unknown/unusable events
- `CrowdControlTracker` depends on the resolver and no longer owns low-level CC aura policy directly

- [ ] **Step 2: Run failing tests**

Run: `rtk test "./.tools/lua/bin/lua tests/core/test_party_crowd_control_resolver.lua"`
Expected: FAIL because resolver file does not exist yet

Run: `rtk test "./.tools/lua/bin/lua tests/modules/test_crowd_control_tracker.lua"`
Expected: FAIL because tracker does not reference resolver/watcher runtime yet

- [ ] **Step 3: Implement resolver-backed CC runtime**

Requirements:

- borrow best attribution heuristics from Kryos/Loxx
- prefer direct aura/filter evidence
- fall back to timestamp correlation only when needed
- preserve confidence/source on runtime entries
- keep cooldown bars as the primary visible CC tracker

- [ ] **Step 4: Run focused verification**

Run: `rtk test "./.tools/lua/bin/lua tests/core/test_party_crowd_control_resolver.lua"`
Expected: PASS

Run: `rtk test "./.tools/lua/bin/lua tests/modules/test_crowd_control_tracker.lua"`
Expected: PASS

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_crowd_control_runtime_slice.py -q'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Core/PartyCrowdControlResolver.lua Modules/CrowdControlTracker.lua Core/CombatTrackEngine.lua Core/CombatTrackSpellDB.lua tests/core/test_party_crowd_control_resolver.lua tests/modules/test_crowd_control_tracker.lua tests/test_crowd_control_runtime_slice.py
rtk git commit -m "refactor: resolve crowd control cooldowns from normalized runtime events"
```

### Task 3: Add Nameplate Crowd Control With Settings And Preview

**Files:**
- Create: `Modules/NameplateCrowdControl.lua`
- Modify: `Settings.lua`
- Modify: `SunderingTools.toc`
- Create: `tests/modules/test_nameplate_crowd_control.lua`
- Modify: `tests/test_nameplate_crowd_control_runtime_slice.py`

- [ ] **Step 1: Write failing tests**

Cover:

- module loads from TOC
- module depends on `PartyCrowdControlAuraWatcher`
- settings shell includes visible controls and preview hooks
- nameplate active-state runtime uses watcher events and cleanup

- [ ] **Step 2: Run failing tests**

Run: `rtk test "./.tools/lua/bin/lua tests/modules/test_nameplate_crowd_control.lua"`
Expected: FAIL because module/settings wiring is incomplete

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_nameplate_crowd_control_runtime_slice.py -q'`
Expected: FAIL because runtime-slice assertions are not satisfied yet

- [ ] **Step 3: Implement module**

Requirements:

- active CC appears on nameplates while the aura exists
- settings are explicit and previewable
- nameplate layer remains secondary to CC cooldown bars
- implementation uses Blizzard-safe filters and watcher cleanup semantics

- [ ] **Step 4: Run focused verification**

Run: `rtk test "./.tools/lua/bin/lua tests/modules/test_nameplate_crowd_control.lua"`
Expected: PASS

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_nameplate_crowd_control_runtime_slice.py -q'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Modules/NameplateCrowdControl.lua Settings.lua SunderingTools.toc tests/modules/test_nameplate_crowd_control.lua tests/test_nameplate_crowd_control_runtime_slice.py
rtk git commit -m "feat: add active crowd control nameplates"
```

### Task 4: Add Party Defensive Aura Fallback And MiniCC-Style Attachments

**Files:**
- Create: `Core/PartyDefensiveAuraFallback.lua`
- Modify: `Modules/PartyDefensiveTracker.lua`
- Modify: `Core/CombatTrackSpellDB.lua`
- Modify: `tests/modules/test_party_defensive_tracker.lua`
- Modify: `tests/test_party_defensive_tracker_runtime_slice.py`

- [ ] **Step 1: Write failing tests**

Cover:

- aura removal produces defensive cooldown fallback state
- sync entries still win over fallback
- attached party icons accept fallback state and render without changing visible tracker style
- MiniCC-like attachment assumptions remain satisfied

- [ ] **Step 2: Run failing tests**

Run: `rtk test "./.tools/lua/bin/lua tests/modules/test_party_defensive_tracker.lua"`
Expected: FAIL

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_party_defensive_tracker_runtime_slice.py -q'`
Expected: FAIL

- [ ] **Step 3: Implement fallback-backed party defensives**

Requirements:

- sync-primary, aura-fallback-second
- MiniCC-style attachment parity where technically possible
- no new user-facing sync toggles

- [ ] **Step 4: Run focused verification**

Run: `rtk test "./.tools/lua/bin/lua tests/modules/test_party_defensive_tracker.lua"`
Expected: PASS

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_party_defensive_tracker_runtime_slice.py -q'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Core/PartyDefensiveAuraFallback.lua Modules/PartyDefensiveTracker.lua Core/CombatTrackSpellDB.lua tests/modules/test_party_defensive_tracker.lua tests/test_party_defensive_tracker_runtime_slice.py
rtk git commit -m "feat: add party defensive aura fallback"
```

### Task 5: Rework Interrupt Runtime Using The Strongest Reference Logic

**Files:**
- Modify: `Modules/InterruptTracker.lua`
- Modify: `Core/CombatTrackEngine.lua`
- Modify: `Core/CombatTrackSpellDB.lua`
- Modify: `tests/test_interrupt_tracker_runtime_slice.py`
- Modify: relevant Lua interrupt tests if needed

- [ ] **Step 1: Write failing interrupt-focused regression assertions**

Cover:

- stronger restricted-mode attribution path
- Loxx/Kryos-style correlation behavior where current SunderingTools logic is weaker
- no visible UI regression in the existing interrupt tracker

- [ ] **Step 2: Run failing tests**

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_interrupt_tracker_runtime_slice.py -q'`
Expected: FAIL on the new assertions

- [ ] **Step 3: Implement stronger interrupt logic**

Requirements:

- copy better logic from Loxx/Kryos where superior
- keep SunderingTools interrupt bars/presentation
- preserve sync/state architecture compatibility

- [ ] **Step 4: Run focused verification**

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_interrupt_tracker_runtime_slice.py tests/test_hybrid_interrupt_cc.py -q'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Modules/InterruptTracker.lua Core/CombatTrackEngine.lua Core/CombatTrackSpellDB.lua tests/test_interrupt_tracker_runtime_slice.py tests/test_hybrid_interrupt_cc.py
rtk git commit -m "refactor: strengthen interrupt runtime attribution"
```

### Task 6: Consolidate Tracker Settings And Remove Obsolete Controls

**Files:**
- Create: `Core/TrackerSettings.lua`
- Modify: `Modules/InterruptTracker.lua`
- Modify: `Modules/CrowdControlTracker.lua`
- Modify: `Modules/PartyDefensiveTracker.lua`
- Modify: `Modules/DefensiveRaidTracker.lua`
- Modify: `Settings.lua`
- Modify: `SunderingTools.lua`
- Modify: runtime-slice tests that assert settings text/options

- [ ] **Step 1: Write failing settings/runtime-slice assertions**

Cover:

- `Raid` and `Arena` options removed from visible settings
- visible sync/strict-sync toggles removed
- only `Dungeon` and `World` context controls remain where relevant
- interrupt and CC bars share one structural settings model
- debug mode stays visible

- [ ] **Step 2: Run failing tests**

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_interrupt_tracker_runtime_slice.py tests/test_crowd_control_runtime_slice.py tests/test_party_defensive_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py -q'`
Expected: FAIL on settings assertions

- [ ] **Step 3: Implement settings cleanup**

Requirements:

- remove dead saved-variable fields and UI controls
- migrate active defaults to the new smaller model
- keep layout controls and preview behavior
- keep `DefensiveRaidTracker` and `PartyDefensiveTracker` separate in presentation

- [ ] **Step 4: Run focused verification**

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_interrupt_tracker_runtime_slice.py tests/test_crowd_control_runtime_slice.py tests/test_party_defensive_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py -q'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rtk git add Core/TrackerSettings.lua Modules/InterruptTracker.lua Modules/CrowdControlTracker.lua Modules/PartyDefensiveTracker.lua Modules/DefensiveRaidTracker.lua Settings.lua SunderingTools.lua tests
rtk git commit -m "refactor: consolidate tracker settings"
```

### Task 7: Final Regression Verification, Merge, Push, And Version

**Files:**
- Modify: `README.md` if needed
- Modify: `SunderingTools.toc` version only if release workflow requires it

- [ ] **Step 1: Run focused Lua verification**

Run: `rtk summary "./.tools/lua/bin/lua tests/run.lua"`
Expected: focused Lua harness passes

- [ ] **Step 2: Run focused Python verification**

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests/test_hybrid_interrupt_cc.py tests/test_interrupt_tracker_runtime_slice.py tests/test_crowd_control_runtime_slice.py tests/test_nameplate_crowd_control_runtime_slice.py tests/test_party_defensive_tracker_runtime_slice.py tests/test_defensive_raid_tracker_runtime_slice.py -q'`
Expected: PASS

- [ ] **Step 3: Run broader regression verification**

Run: `rtk proxy bash -lc '. /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/.venv-lua/bin/activate && pytest tests -q'`
Expected: PASS, or if a subset is intentionally excluded, document exact exclusions before release

- [ ] **Step 4: Merge worktree branch into `main`**

```bash
rtk git checkout main
rtk git merge --no-ff feature/party-cc-defensive-tracking
```

- [ ] **Step 5: Push and create version**

Determine next version from repo/tag history, then:

```bash
rtk git push origin main
rtk git tag vNEXT
rtk git push origin vNEXT
```

Document the exact chosen version in the final report.
