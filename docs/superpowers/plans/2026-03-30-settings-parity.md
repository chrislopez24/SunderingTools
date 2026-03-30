# Settings Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the settings parity gaps so persisted settings are exposed in the UI and changing them applies correct runtime behavior.

**Architecture:** This stays within the current module-owned settings pattern. The work is concentrated in `PartyDefensiveTracker` for live attachment behavior and in `BloodlustSound` for surfacing its persisted duration setting, with regression coverage anchored in Lua runtime tests and lightweight static UI tests.

**Tech Stack:** Lua addon runtime, Python assertion tests, existing WoW frame stubs in `tests/modules`

---

### Task 1: Reproduce Missing Settings Coverage

**Files:**
- Modify: `tests/modules/test_party_defensive_tracker.lua`
- Modify: `tests/test_settings_ui_redesign.py`
- Modify: `tests/test_review_fixes.py`

- [ ] **Step 1: Write failing tests for Party Defensive settings parity**
- [ ] **Step 2: Run the targeted tests and confirm they fail for the expected reasons**
- [ ] **Step 3: Add failing static assertions for missing Bloodlust duration and Party Defensive controls**
- [ ] **Step 4: Re-run the targeted tests and confirm they still fail for the new gaps**

### Task 2: Implement Party Defensive UI/Runtime Parity

**Files:**
- Modify: `Modules/PartyDefensiveTracker.lua`
- Test: `tests/modules/test_party_defensive_tracker.lua`

- [ ] **Step 1: Expand `buildSettings(...)` to expose all persisted Party Defensive controls**
- [ ] **Step 2: Re-anchor and re-layout existing attachments when settings change**
- [ ] **Step 3: Add tooltip handlers that honor `showTooltip`**
- [ ] **Step 4: Run the Party Defensive Lua tests and confirm they pass**

### Task 3: Implement Bloodlust Duration Control

**Files:**
- Modify: `Modules/BloodlustSound.lua`
- Test: `tests/test_settings_ui_redesign.py`
- Test: `tests/test_review_fixes.py`

- [ ] **Step 1: Add a duration control to the Bloodlust settings page**
- [ ] **Step 2: Keep the setting wired to the existing runtime semantics**
- [ ] **Step 3: Run the Bloodlust/static settings tests and confirm they pass**

### Task 4: Regression Verification

**Files:**
- Verify only

- [ ] **Step 1: Run the targeted settings/runtime test subset**
- [ ] **Step 2: Run the broader review/settings regression tests that cover the touched modules**
- [ ] **Step 3: Inspect diffs and summarize any residual risk**
