# SunderingTools Debug Mode, CC Spell DB Cleanup, and Project Organization Design

**Date:** 2026-03-30

**Goal**

Add a low-cost global debug mode for SunderingTools, clean the crowd control spell database so it only tracks cooldown-based spells with a sharper `essential` definition, and reorganize project assets so the repository layout is easier to maintain and package.

## Context

SunderingTools already has a native settings window with a `General` section and module-specific pages. Global state is stored under `db.global`, while interrupt and crowd control metadata live in `Core/CombatTrackSpellDB.lua`. The addon currently uses direct `print` calls instead of a shared logging helper, and the crowd control database includes spells with `cd = 0`, which do not fit a cooldown tracker well.

## Requirements

### Debug Mode

- Add a `debugMode` setting under `db.global`, defaulting to `false`.
- Expose the toggle from the `General` settings page.
- Provide a central helper for debug logging instead of scattered conditional `print` calls.
- Keep runtime overhead low:
  - No debug logging from per-frame ticker or render loops.
  - Cheap early-return when disabled.
  - Avoid expensive formatting work unless debug mode is enabled.
- Log output is chat-only. No persistence, file output, or history buffer.

### Crowd Control Spell DB Cleanup

- Remove crowd control spells with `cd <= 0` from the tracked database used by the tracker.
- Redefine `essential = true` to mean:
  - cooldown-based crowd control
  - high tactical value
  - suitable for the default M+ view
- Allow zero, one, or multiple `essential` spells per class.
- Preserve compatibility for existing consumers:
  - `GetPrimaryCrowdControlForClass` still returns a reasonable default
  - fallback is the first valid cooldown-based CC for that class if there is no essential entry

### Project Organization

- Improve repository organization without breaking addon packaging.
- Focus especially on assets:
  - move loose-root assets into clearer folders
  - keep addon paths stable from the packaged addon root
- Update references so `.toc`, Lua modules, and tests continue to point at valid paths.

## Architecture

### Logging

The addon root module will own a shared `addon:DebugLog(scope, ...)` helper. It will check `db.global.debugMode` first and return immediately when disabled. When enabled, it will format a prefixed chat message and call `print`.

This keeps logging semantics centralized and avoids per-module feature flags or repeated branching logic. Existing informational `print` calls that should remain always-on can stay as-is; debug-only traces should move to the helper.

### Settings Integration

The `General` settings renderer in `Settings.lua` will add a small diagnostics block or inline toggle near the system actions. This keeps the new setting global, discoverable, and isolated from tracker-specific pages.

### Crowd Control Data Model

`Core/CombatTrackSpellDB.lua` will treat the crowd control source table as the canonical tracker input rather than a general encyclopedia. During registration, only entries with `cd > 0` will be loaded into tracked CC collections.

The tracker-facing API remains stable:

- `GetTrackedSpell(spellID)` returns tracked cooldown-based spells only
- `GetCrowdControlForClass(classToken)` returns cooldown-based CC spells only
- `FilterCrowdControl("ESSENTIALS")` returns only high-value cooldown-based entries
- `GetPrimaryCrowdControlForClass(classToken)` returns the first essential CC for the class, or the first remaining tracked CC if none are marked essential

### Asset Layout

Static assets currently live in the repository root and in `sounds/`. The project will move visual assets into dedicated folders such as `assets/icons/` and `assets/art/`, while keeping audio in `sounds/` unless a broader split is warranted.

All Lua references, `.toc` paths, and packaging assumptions must continue to resolve from the addon root after the move.

## Data Flow

### Debug Mode

1. The addon builds defaults with `global.debugMode = false`.
2. The user toggles Debug Mode in settings.
3. Runtime code calls `addon:DebugLog(scope, ...)` only in event-driven paths.
4. If disabled, the helper exits immediately.
5. If enabled, the helper prints a namespaced message to chat.

### Crowd Control Tracking

1. `CombatTrackSpellDB.lua` registers only cooldown-based CC entries.
2. Crowd control modules read the filtered database as before.
3. Default tracker mode uses refined `essential` entries.
4. “All” mode still shows the broader cooldown-based set, but no zero-cooldown spam or utility-only entries.

## Error Handling and Compatibility

- If `db` is not initialized yet, `DebugLog` should safely no-op.
- Existing APIs should remain callable with the same names and signatures.
- The cleanup should not affect interrupt tracking paths.
- Asset path changes must be mirrored everywhere they are referenced to avoid missing texture or sound failures.

## Testing Strategy

### Automated Tests

- Add or update Lua tests for:
  - `debugMode` default state
  - crowd control filtering of zero-cooldown spells
  - refined `essential` semantics
  - primary crowd control fallback behavior
- Add or update Python/textual tests for:
  - settings UI presence of the Debug Mode toggle
  - path/reference changes for moved assets
  - packaging metadata pointing at the correct files

### Verification

- Run targeted failing tests before code changes.
- Run the targeted suite after each implementation slice.
- Run the full local test entrypoint before commit.
- Validate git diff carefully because the worktree already contains unrelated user changes.

## Scope Boundaries

Included:

- global debug mode toggle and helper
- low-cost event-driven debug traces
- cleanup of tracked CC entries with `cd <= 0`
- refined `essential` curation
- repository asset/layout cleanup needed for maintainability
- version bump to `0.0.1`
- public GitHub publication and release workflow trigger via tag push

Excluded:

- persistent debug log storage
- debug UI consoles
- new tracker features unrelated to logging or CC data quality
- broad refactors outside files touched by this work
