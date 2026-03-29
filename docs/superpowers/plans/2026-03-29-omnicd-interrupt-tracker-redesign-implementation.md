# OmniCD Interrupt Tracker Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `SunderingTools` interrupt tracker UI so it visually matches OmniCD-style interrupt bars while preserving the current interrupt tracking logic.

**Architecture:** Keep runtime tracking logic in `Modules/InterruptTracker.lua`, but replace the bar composition and settings surface with a narrower, OmniCD-like visual model. Use static Python regression tests to lock the intended settings/UI contract, then update the Lua runtime and preview data to satisfy that contract.

**Tech Stack:** WoW Lua, static Python tests with `pytest`, git

---

### Task 1: Lock the new tracker contract with failing tests

**Files:**
- Modify: `tests/test_review_fixes.py`

- [ ] **Step 1: Write the failing test**

```python
def test_interrupt_tracker_panel_matches_omnicd_style_controls():
    source = read("Modules/InterruptTracker.lua")
    for label in (
        "Show Preview When Solo",
        "Icon Size",
        "Font Size",
    ):
        assert label in source

    for removed in (
        "Ready Text",
        "Show Ready Text",
        "Use Class Color",
        "Name Font Size",
        "Timer Font Size",
    ):
        assert removed not in source

    assert "bar.borderTop" in source
    assert "bar.borderBottom" in source
    assert "bar.borderRight" in source
    assert "bar.cooldown" in source
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest -q /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_review_fixes.py`
Expected: FAIL because the old tracker UI still exposes removed controls and lacks the new bar structure.

- [ ] **Step 3: Commit the red test when working incrementally**

```bash
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools add tests/test_review_fixes.py
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools commit -m "test: lock omnicd tracker ui contract"
```

### Task 2: Refactor preview data for the new visual model

**Files:**
- Modify: `Modules/InterruptTrackerModel.lua`
- Test: `tests/modules/test_interrupt_tracker.lua`

- [ ] **Step 1: Write the failing preview expectation**

```lua
local preview = Model.BuildPreviewBars()
assert(preview[1].spellID, "preview rows should include spell icons")
assert(preview[1].class, "preview rows should include class color data")
assert(preview[2].previewRemaining, "preview rows should include cooldown state")
```

- [ ] **Step 2: Run the test harness to verify the expectation fails or is incomplete**

Run: `python3 -m pytest -q /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests`
Expected: Existing static coverage is insufficient until the runtime file is updated to consume the richer preview data.

- [ ] **Step 3: Update preview rows to carry the data the new bar renderer needs**

```lua
{
  key = "melee",
  name = "MeleeKick",
  class = "ROGUE",
  role = "DAMAGER",
  spellID = 1766,
  cd = 15,
  previewRemaining = 7.4,
}
```

- [ ] **Step 4: Run tests after the preview data update**

Run: `python3 -m pytest -q /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests`
Expected: test suite remains green or returns to green once downstream runtime changes are complete.

- [ ] **Step 5: Commit**

```bash
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools add Modules/InterruptTrackerModel.lua tests/modules/test_interrupt_tracker.lua
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools commit -m "refactor: enrich interrupt tracker preview data"
```

### Task 3: Replace the tracker row composition with OmniCD-style bars

**Files:**
- Modify: `Modules/InterruptTracker.lua`
- Reference: `../OmniCD/Modules/Party/StatusBar.lua`
- Reference: `../OmniCD/Modules/Party/StatusBar.xml`

- [ ] **Step 1: Build a new row structure**

```lua
bar.bg = bar:CreateTexture(nil, "BACKGROUND")
bar.bg:SetAllPoints()

bar.borderTop = bar:CreateTexture(nil, "BORDER")
bar.borderBottom = bar:CreateTexture(nil, "BORDER")
bar.borderRight = bar:CreateTexture(nil, "BORDER")

bar.cooldown = CreateFrame("StatusBar", nil, bar)
bar.cooldown:SetPoint("TOPLEFT", bar.borderTop, "BOTTOMLEFT", 0, 0)
bar.cooldown:SetPoint("BOTTOMRIGHT", bar.borderRight, "BOTTOMLEFT", 0, 0)
```

- [ ] **Step 2: Render ready vs cooldown state distinctly**

```lua
if isReady then
    bar.bg:SetVertexColor(classR, classG, classB, 1)
    bar.nameText:Show()
    bar.timerText:Hide()
    bar.cooldown:Hide()
else
    bar.bg:Hide()
    bar.cooldown:Show()
    bar.timerText:Show()
end
```

- [ ] **Step 3: Update icon, text, border, and sizing rules**

```lua
bar.icon:SetSize(db.iconSize, db.iconSize)
bar.nameText:SetPoint("LEFT", bar, "LEFT", db.iconSize + 6, 0)
bar.timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
bar.borderTop:SetColorTexture(0, 0, 0, 1)
```

- [ ] **Step 4: Preserve preview/edit mode and real cooldown state**

```lua
if ShouldShowPreview() then
    PopulateBars(BuildPreviewBars())
else
    PopulateBars(entries)
end
```

- [ ] **Step 5: Run the targeted tests**

Run: `python3 -m pytest -q /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests/test_review_fixes.py`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools add Modules/InterruptTracker.lua tests/test_review_fixes.py
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools commit -m "feat: restyle interrupt tracker like omnicd"
```

### Task 4: Simplify the tracker settings panel

**Files:**
- Modify: `Modules/InterruptTracker.lua`
- Test: `tests/test_review_fixes.py`

- [ ] **Step 1: Remove controls that conflict with the fixed OmniCD-style presentation**

```lua
-- Remove:
-- Ready Text
-- Show Ready Text
-- Use Class Color
-- Name Font Size
-- Timer Font Size
```

- [ ] **Step 2: Add the reduced settings surface**

```lua
helpers:CreateSlider(panel, "Icon Size", 16, 32, 1, moduleDB.iconSize, ...)
helpers:CreateSlider(panel, "Font Size", 8, 20, 1, moduleDB.fontSize, ...)
helpers:CreateCheckbox(panel, "Show Preview When Solo", moduleDB.previewWhenSolo, ...)
```

- [ ] **Step 3: Update config-change handling to match the new keys**

```lua
if key == "iconSize" or key == "fontSize" then
    CreateContainer()
    UpdatePartyData()
end
```

- [ ] **Step 4: Run the full test suite**

Run: `python3 -m pytest -q /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools add Modules/InterruptTracker.lua tests/test_review_fixes.py
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools commit -m "refactor: simplify interrupt tracker settings"
```

### Task 5: Final verification and repository hygiene

**Files:**
- Modify: `docs/superpowers/specs/2026-03-29-omnicd-interrupt-tracker-redesign-design.md`
- Modify: `docs/superpowers/plans/2026-03-29-omnicd-interrupt-tracker-redesign-implementation.md`

- [ ] **Step 1: Run full verification**

Run: `python3 -m pytest -q /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools/tests`
Expected: `10 passed` or updated count with zero failures

- [ ] **Step 2: Check whitespace and patch cleanliness**

Run: `git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools diff --check`
Expected: no output

- [ ] **Step 3: Review git status**

Run: `git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools status --short`
Expected: clean after commit

- [ ] **Step 4: Commit documentation and any final adjustments**

```bash
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools add docs/superpowers/specs/2026-03-29-omnicd-interrupt-tracker-redesign-design.md docs/superpowers/plans/2026-03-29-omnicd-interrupt-tracker-redesign-implementation.md
git -C /mnt/c/Users/Chris/Desktop/Projects/ExWindtools/SunderingTools commit -m "docs: record omnicd tracker redesign"
```
