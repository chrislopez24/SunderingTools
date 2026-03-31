# Conservative Repo Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove verifiable dead code, brittle tests, and stale planning artifacts from the repository without changing shipped behavior.

**Architecture:** Keep runtime behavior intact and focus on maintenance-only changes. Prefer deleting obviously dead or redundant code, strengthening tests to depend on behavior instead of implementation strings, and cleaning stale docs/plan artifacts only when they are clearly superseded or untracked leftovers.

**Tech Stack:** Lua addon runtime, Python test slices, `lupa`-backed Lua harness, git docs/plans/specs markdown files.

---

### Task 1: Inventory and codify hygiene targets

**Files:**
- Modify: `tests/test_lua_harness_runtime_slice.py`
- Modify: `tests/test_packaging.py`
- Test: `tests/test_lua_harness_runtime_slice.py`
- Test: `tests/test_packaging.py`

- [ ] **Step 1: Write or adjust the failing tests**

Replace fragile checks with repo-level expectations:

```python
source = read("tests/run.lua")
assert 'dofile("tests/core/test_cooldown_viewer_meta.lua")' in source
```

```python
toc = read("SunderingTools.toc")
assert "## Version: 0.0.7" in toc
```

- [ ] **Step 2: Run tests to verify they fail when stale**

Run: `python3 -m pytest -q tests/test_lua_harness_runtime_slice.py tests/test_packaging.py`
Expected: fail if harness or packaging assertions still reflect stale repo state

- [ ] **Step 3: Apply the minimal test hygiene changes**

Keep only current, behavior-relevant assertions in those files and remove stale literal expectations.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest -q tests/test_lua_harness_runtime_slice.py tests/test_packaging.py`
Expected: `2 passed`

- [ ] **Step 5: Commit**

```bash
git add tests/test_lua_harness_runtime_slice.py tests/test_packaging.py
git commit -m "test: align harness and packaging checks"
```

### Task 2: Clean dead or redundant local model/runtime code

**Files:**
- Modify: `Modules/BloodlustSound.lua`
- Modify: `Modules/BloodlustSoundModel.lua`
- Modify: `Core/PartyCrowdControlAuraWatcher.lua`
- Modify: `tests/modules/test_bloodlust_sound_runtime.lua`
- Modify: `tests/core/test_party_crowd_control_aura_watcher.lua`
- Test: `tests/modules/test_bloodlust_sound_runtime.lua`
- Test: `tests/core/test_party_crowd_control_aura_watcher.lua`
- Test: `tests/test_bloodlust_sound_runtime.py`
- Test: `tests/test_party_crowd_control_aura_watcher_runtime.py`

- [ ] **Step 1: Write or tighten failing tests around the actual cleanup**

Add assertions only for behavior that must survive cleanup, for example:

```lua
assert(events[2].payload.sourceUnit == nil, "secret source units should stay sanitized")
```

```python
source = read("Modules/BloodlustSound.lua")
assert "NormalizeName" in source
assert "SanitizeAuraAsset" in source
```

Then remove or relax assertions that depend only on exact helper placement when they block cleanup.

- [ ] **Step 2: Run the targeted tests to expose stale expectations**

Run:

```bash
PYTHONPATH=.venv-lua/lib/python3.12/site-packages python3 -m pytest -q tests/test_bloodlust_sound_runtime.py tests/test_party_crowd_control_aura_watcher_runtime.py
```

Expected: fail if cleanup candidates are blocked only by brittle textual assumptions

- [ ] **Step 3: Apply the minimal cleanup**

Limit changes to:

- dead or duplicated helper code in `BloodlustSound.lua` and `BloodlustSoundModel.lua`
- local sanitization or comparison scaffolding in `PartyCrowdControlAuraWatcher.lua` that is provably redundant
- no behavior change to aura sanitization or sound display

- [ ] **Step 4: Run targeted tests to verify cleanup**

Run:

```bash
PYTHONPATH=.venv-lua/lib/python3.12/site-packages python3 -m pytest -q tests/test_bloodlust_sound_runtime.py tests/test_party_crowd_control_aura_watcher_runtime.py
```

Run:

```bash
.venv-lua/bin/python3 - <<'PY'
from pathlib import Path
from lupa.lua54 import LuaRuntime
for rel in ['tests/core/test_party_crowd_control_aura_watcher.lua']:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = package.path .. ';./?.lua;./?/init.lua'")
    lua.execute(Path(rel).read_text(encoding='utf-8'))
PY
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add Core/PartyCrowdControlAuraWatcher.lua Modules/BloodlustSound.lua Modules/BloodlustSoundModel.lua tests/modules/test_bloodlust_sound_runtime.lua tests/core/test_party_crowd_control_aura_watcher.lua tests/test_bloodlust_sound_runtime.py tests/test_party_crowd_control_aura_watcher_runtime.py
git commit -m "refactor: remove dead local tracker scaffolding"
```

### Task 3: Clean stale docs and plan artifacts

**Files:**
- Modify: `docs/superpowers/specs/2026-03-31-conservative-repo-hygiene-design.md`
- Create: `docs/superpowers/plans/2026-03-31-conservative-repo-hygiene.md`
- Delete: `docs/superpowers/plans/2026-03-30-strict-sync-pve-tracking.md` if still untracked and superseded
- Delete: `docs/superpowers/specs/2026-03-31-bloodlust-lockout-display-design.md` if still untracked and superseded

- [ ] **Step 1: Verify candidate docs are safe to remove**

Run:

```bash
git status --short
```

Expected: only untracked stale docs are considered for deletion, not user-owned tracked work.

- [ ] **Step 2: Remove only clearly stale untracked planning artifacts**

Delete only if all are true:

- file is untracked
- file is not referenced by current implementation work
- a newer committed spec/plan supersedes it or it is abandoned draft material

- [ ] **Step 3: Keep current hygiene spec and plan**

Ensure the final repo keeps:

- `docs/superpowers/specs/2026-03-31-conservative-repo-hygiene-design.md`
- `docs/superpowers/plans/2026-03-31-conservative-repo-hygiene.md`

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-03-31-conservative-repo-hygiene-design.md docs/superpowers/plans/2026-03-31-conservative-repo-hygiene.md
git add -u docs/superpowers/plans docs/superpowers/specs
git commit -m "docs: clean stale planning artifacts"
```

### Task 4: Full verification and release

**Files:**
- Modify: `SunderingTools.toc` if version needs bump

- [ ] **Step 1: Run full verification**

Run:

```bash
PYTHONPATH=.venv-lua/lib/python3.12/site-packages python3 -m pytest -q tests
```

Expected: full Python suite passes

Run:

```bash
.venv-lua/bin/python3 - <<'PY'
from pathlib import Path
from lupa.lua54 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = package.path .. ';./?.lua;./?/init.lua'")
lua.execute(Path('tests/run.lua').read_text(encoding='utf-8'))
PY
```

Expected: Lua harness prints `ok`

- [ ] **Step 2: Commit final hygiene adjustments**

If any version or final cleanup changes remain, commit them before release.

- [ ] **Step 3: Push and tag release**

Use the next patch version after the latest existing tag. If the latest tag is already `v0.0.7`, tag this hygiene release as `v0.0.8`.

```bash
git push origin main
git tag -a v0.0.8 -m "Release v0.0.8"
git push origin v0.0.8
```
