# MiniCC-Style Tracking Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SunderingTools tracker internals with a MiniCC-style aura watcher and evidence-backed inference engine while preserving the current UI layer.

**Architecture:** Build a shared core for visible aura state, public event evidence, rule-based cooldown inference, and talent/spec modifiers. Then migrate party defensives, raid defensives, nameplate CC, interrupts, and bloodlust to consume that core and delete obsolete tracker logic/tests.

**Tech Stack:** WoW Lua addon runtime, Blizzard aura/spell/chat APIs, Lua harness tests executed with `lupa`, Python repo/runtime slice tests.

---

### Task 1: Land the shared watcher and evidence core

**Files:**
- Create: `Core/UnitAuraStateWatcher.lua`
- Create: `Core/FriendlyEventEvidence.lua`
- Modify: `SunderingTools.toc`
- Create: `tests/core/test_unit_aura_state_watcher.lua`
- Create: `tests/core/test_friendly_event_evidence.lua`

- [ ] Write failing Lua tests for:
  - visible `CC`, `BIG_DEFENSIVE`, `EXTERNAL_DEFENSIVE`, and `IMPORTANT` aura classification
  - secret spell/name/icon payloads being sanitized to `nil`
  - `DurationObject` preservation
  - evidence timestamps for cast, harmful aura add, unit flags, and absorb signals

- [ ] Run focused Lua harness execution for those tests and verify they fail for missing files.

- [ ] Implement `Core/UnitAuraStateWatcher.lua` as the shared watcher and `Core/FriendlyEventEvidence.lua` as the shared evidence collector.

- [ ] Update `SunderingTools.toc` so the new core loads before any modules that consume it.

- [ ] Re-run the focused Lua tests and make sure they pass.

### Task 2: Build the normalized inference engine and rule book

**Files:**
- Create: `Core/FriendlyTrackingRules.lua`
- Create: `Core/FriendlyTalentResolver.lua`
- Create: `Core/FriendlyCooldownInference.lua`
- Modify: `Core/CombatTrackSpellDB.lua`
- Create: `tests/core/test_friendly_tracking_rules.lua`
- Create: `tests/core/test_friendly_talent_resolver.lua`
- Create: `tests/core/test_friendly_cooldown_inference.lua`

- [ ] Write failing tests for:
  - rule matching by aura type and measured duration
  - evidence-gated matches (`Cast`, `Debuff`, `Shield`, `UnitFlags`)
  - talent/spec gating
  - early-cancel defensives
  - interrupt cooldown inference from cast evidence when applicable

- [ ] Run the focused Lua tests and verify they fail.

- [ ] Implement the shared rules, talent resolver, and inference engine.

- [ ] Shrink `CombatTrackSpellDB.lua` to catalog responsibilities only, removing runtime alias/index paths that the new engine supersedes.

- [ ] Re-run the focused tests and make sure they pass.

### Task 3: Migrate party and raid defensives to inference-backed runtime state

**Files:**
- Modify: `Modules/PartyDefensiveTracker.lua`
- Modify: `Modules/DefensiveRaidTracker.lua`
- Delete: `Core/PartyDefensiveAuraFallback.lua`
- Modify: `tests/modules/test_party_defensive_tracker.lua`
- Modify: `tests/modules/test_defensive_raid_tracker_runtime.lua`
- Delete or rewrite: `tests/core/test_party_defensive_aura_fallback.lua`
- Modify: `tests/test_party_defensive_tracker_runtime_slice.py`
- Modify: `tests/test_defensive_raid_tracker_runtime_slice.py`

- [ ] Write failing module tests that assert:
  - active defensives are tracked from watcher state
  - cooldown entries are emitted when the aura ends
  - secret spell payloads do not crash and simply produce no inference
  - raid defensives follow the same normalized pipeline

- [ ] Run focused Python/Lua tests and confirm they fail under the old fallback path.

- [ ] Replace the old fallback integration with the shared watcher + evidence + inference engine.

- [ ] Delete `Core/PartyDefensiveAuraFallback.lua` and remove any stale references from the TOC/tests.

- [ ] Re-run focused tests and make sure they pass.

### Task 4: Migrate nameplate CC and bar-based crowd-control tracking

**Files:**
- Modify: `Modules/NameplateCrowdControl.lua`
- Modify: `Modules/CrowdControlTracker.lua`
- Delete: `Core/PartyCrowdControlAuraWatcher.lua`
- Delete: `Core/PartyCrowdControlResolver.lua`
- Modify: `tests/modules/test_nameplate_crowd_control.lua`
- Modify: `tests/modules/test_crowd_control_tracker.lua`
- Modify: `tests/core/test_party_crowd_control_aura_watcher.lua`
- Modify: `tests/test_crowd_control_runtime_slice.py`

- [ ] Write failing tests for:
  - nameplate CC rendering directly from shared watcher state
  - no `?` fallback path for visible CC auras
  - bar-based crowd-control state using the same normalized cooldown/inference model

- [ ] Run focused tests and verify the old custom watcher/resolver path no longer satisfies them.

- [ ] Rework both modules to consume the shared watcher and delete the old CC watcher/resolver core files.

- [ ] Re-run the focused tests and make sure they pass.

### Task 5: Rebuild interrupt tracking around shared cooldown state and evidence

**Files:**
- Modify: `Modules/InterruptTracker.lua`
- Modify: `Core/CombatTrackSync.lua`
- Modify: `Core/CombatTrackEngine.lua`
- Modify: `tests/modules/test_interrupt_tracker.lua`
- Modify: `tests/test_interrupt_tracker_runtime_slice.py`

- [ ] Write failing tests for:
  - direct self and cooperative sync staying owner-authoritative
  - evidence-backed interrupt inference for grouped units when direct state is absent
  - bar state using the same normalized cooldown entry shape as defensives
  - secret-safe handling of non-local spell IDs

- [ ] Run focused tests and verify they fail under the current interrupt-specific runtime.

- [ ] Adapt `InterruptTracker.lua` to the shared inference pipeline, keeping sync as enrichment rather than as the whole design.

- [ ] Simplify `CombatTrackSync.lua` and `CombatTrackEngine.lua` only where the shared state shape requires it.

- [ ] Re-run focused tests and make sure they pass.

### Task 6: Fix Bloodlust sound by moving to the shared watcher path

**Files:**
- Modify: `Modules/BloodlustSound.lua`
- Modify: `Modules/BloodlustSoundModel.lua`
- Modify: `tests/modules/test_bloodlust_sound_runtime.lua`
- Modify: `tests/test_bloodlust_sound_runtime.py`

- [ ] Write failing tests for:
  - active bloodlust-family aura starts sound exactly once
  - login/resume with active aura behaves correctly
  - lockout and active state remain visually distinct
  - secret aura names/spell IDs do not break the tracker

- [ ] Run focused bloodlust tests and confirm the current module still misses the requested active sound behavior.

- [ ] Rework bloodlust aura detection around the shared watcher state and keep the existing frame/settings contract.

- [ ] Re-run focused tests and make sure they pass.

### Task 7: Delete obsolete logic and obsolete tests

**Files:**
- Modify or delete: stale tracker core files and tests identified during Tasks 1-6
- Modify: `tests/run.lua`
- Modify: `tests/test_lua_harness_runtime_slice.py`
- Modify: `tests/test_packaging.py`

- [ ] Remove files that are now dead because the shared watcher/inference core replaced them.

- [ ] Delete or rewrite tests that only validated those removed implementation seams.

- [ ] Keep only tests that validate shipped tracker behavior, runtime wiring, or packaging.

- [ ] Re-run the targeted packaging/harness tests and make sure they pass.

### Task 8: Full verification, repo cleanup, and release prep

**Files:**
- Modify: `SunderingTools.toc`
- Modify: `docs/superpowers/specs/2026-03-31-mini-cc-style-tracking-core-design.md`
- Modify: `docs/superpowers/plans/2026-03-31-mini-cc-style-tracking-core.md`

- [ ] Run the full test suite:
  - `PYTHONPATH=.venv-lua/lib/python3.12/site-packages python3 -m pytest -q tests`
  - Lua harness over `tests/run.lua`

- [ ] Review `git diff --stat` and remove any stale docs/tests/files that no longer belong to the final repo state requested by the user.

- [ ] Bump version only when the implementation scope is finished and verified.

- [ ] Prepare a final cleanup commit and release/tag only after the repo reflects only the current functional surface.
