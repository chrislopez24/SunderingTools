# Loxx-Style Interrupt And Raid Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make interrupt attribution behave like Loxx while keeping SunderingTools’ state engine, and make raid defensive bars reliably converge through sync plus local inference.

**Architecture:** `InterruptTracker` will shift from bespoke correlation state toward `CombatTrackEngine` pending-cast resolution plus periodic owner-authoritative sync rebroadcast. `DefensiveRaidTracker` will keep watcher/inference but add the same self-state rebroadcast discipline used by reliable cooldown trackers.

**Tech Stack:** Lua addon runtime, Blizzard unit events and addon comms, existing `CombatTrackEngine`, pytest runtime slices, Lua harness tests via `tests/run.lua`.

---

### Task 1: Add failing tests for interrupt correlation and resync

**Files:**
- Create: `tests/modules/test_interrupt_tracker_runtime.lua`
- Modify: `tests/run.lua`
- Test: `tests/modules/test_interrupt_tracker_runtime.lua`

- [ ] Add a Lua runtime harness for `InterruptTracker` based on the existing tracker harness pattern.
- [ ] Add tests for:
  - correlated party interrupt attribution through enemy interrupted events
  - self tie winning over party timestamps
  - ambiguous candidates being dropped
  - periodic `INT` rebroadcast while self cooldown is active
  - replaying current self interrupt state after peer `HELLO`
- [ ] Add the new runtime test file to `tests/run.lua`.
- [ ] Run the focused Lua harness and confirm these tests fail for the expected missing behavior.

### Task 2: Add failing tests for raid defensive rebroadcast reliability

**Files:**
- Modify: `tests/modules/test_defensive_raid_tracker_runtime.lua`
- Test: `tests/modules/test_defensive_raid_tracker_runtime.lua`

- [ ] Add tests proving `DefensiveRaidTracker` periodically rebroadcasts active self `DEF_STATE`.
- [ ] Add tests proving inbound `HELLO` triggers immediate replay of current self raid defensive state.
- [ ] Run the focused Lua harness and confirm the new tests fail before implementation.

### Task 3: Extend shared sync/core behavior needed by the new model

**Files:**
- Modify: `Core/CombatTrackSync.lua`
- Modify: `Core/CombatTrackEngine.lua`
- Test: `tests/core/test_combat_track_sync.lua`
- Test: `tests/core/test_combat_track_engine.lua`

- [ ] Add any missing sync decoding/encoding needed for replay-safe behavior without weakening current payload validation.
- [ ] Extend engine tests if needed to cover the exact correlation semantics used by the interrupt module.
- [ ] Keep the engine as the sole resolver of pending interrupt timestamps.

### Task 4: Migrate interrupt runtime logic to the Loxx-style model

**Files:**
- Modify: `Modules/InterruptTracker.lua`
- Test: `tests/modules/test_interrupt_tracker_runtime.lua`
- Test: `tests/test_interrupt_tracker_runtime_slice.py`
- Test: `tests/test_interrupt_tracker_bugfix.py`

- [ ] Replace module-local timestamp resolution with engine-backed pending cast correlation.
- [ ] Feed party and party-pet watcher events into the engine pending-cast queue instead of only writing `recentPartyCasts`.
- [ ] Keep self exact-cast handling and make self win ties.
- [ ] Add periodic `INT` rebroadcast for active local cooldowns.
- [ ] Preserve existing UI behavior and tooltip behavior.
- [ ] Update runtime-slice tests only where implementation details changed for good reason.

### Task 5: Harden raid defensive self-state convergence

**Files:**
- Modify: `Modules/DefensiveRaidTracker.lua`
- Test: `tests/modules/test_defensive_raid_tracker_runtime.lua`
- Test: `tests/test_defensive_raid_tracker_runtime_slice.py`

- [ ] Add periodic `DEF_STATE` rebroadcast for active self raid-defensive cooldowns.
- [ ] Replay current self raid cooldown state on peer `HELLO`.
- [ ] Keep aura inference intact and preserve sync priority over inferred entries.
- [ ] Ensure canonicalization still works for spells like `Anti-Magic Zone`.

### Task 6: Remove stale tests and dead assertions tied to the superseded behavior

**Files:**
- Modify: `tests/test_interrupt_tracker_runtime_slice.py`
- Modify: `tests/test_defensive_raid_tracker_runtime_slice.py`
- Modify: any redundant runtime-slice tests made obsolete by the new runtime coverage

- [ ] Delete or tighten assertions that only describe the old manual correlation implementation.
- [ ] Keep only tests that validate the required behavior or important packaging/wiring invariants.

### Task 7: Run verification and publish

**Files:**
- Modify: `SunderingTools.toc`
- Modify: `tests/test_packaging.py`

- [ ] Bump addon version for the release.
- [ ] Run focused Lua runtime tests for interrupts and raid defensives.
- [ ] Run `python3 -m pytest -q tests`.
- [ ] Run `tests/run.lua` in the Lua harness.
- [ ] Review `git diff` for accidental UI changes or dead-code regressions.
- [ ] Commit, push, and create a new version tag only after the verification passes.
