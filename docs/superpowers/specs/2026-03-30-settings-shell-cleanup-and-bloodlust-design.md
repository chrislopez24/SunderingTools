# Settings Shell Cleanup And Bloodlust Design

## Goal

Improve `SunderingTools` in three focused ways without changing tracker runtime behavior:

1. Remove the black square behind the animated `Pedro` Bloodlust icon.
2. Redesign only the settings window to match the exact shell style of the `PedroLust` config window.
3. Clean up and organize the addon structure and the most overloaded implementation files involved in this work.

## Scope

In scope:

- `Bloodlust Sound` visual/runtime cleanup for the `Pedro` icon style.
- Settings shell visual redesign.
- Internal cleanup of settings and bloodlust implementation.
- Lightweight structure cleanup across `toc`, assets, and tests.

Out of scope:

- Changing the visual style of on-screen trackers.
- Reworking interrupt or crowd control detection logic.
- Reorganizing the addon into a completely new folder structure.

## Requirements

### 1. Bloodlust Pedro runtime

- The `Pedro` icon style must animate as a sprite sheet while the Bloodlust effect is active.
- The `Pedro` icon must not show a square black background behind the circular art during normal runtime.
- Edit mode must remain visually usable, but its editing visuals must come from shared tracker-shell behavior instead of a module-specific opaque background.
- `BL Icon`, `Pedro`, and `Custom` must continue to work from the same settings section.

### 2. Settings shell redesign

- Only the settings window changes visually.
- The shell should match the same style as the referenced `PedroLust` window:
  - flat dark header bar
  - subtitle/byline/version metadata in the header
  - flat dark sidebar with clear selected state
  - flat content pane with compact controls
- Existing sections remain:
  - `General`
  - `Interrupt Tracker`
  - `Crowd Control Tracker`
  - `Bloodlust Sound`
- Existing controls and module behavior remain intact.
- The runtime trackers must keep their current look.

### 3. Cleanup and organization

- `Settings.lua` should be easier to follow, with theme/state/render helpers grouped more clearly.
- `BloodlustSound.lua` should separate icon resolution, sprite handling, frame visibility, and effect playback more clearly.
- `SunderingTools.toc` should remain ordered by load dependencies and be easy to scan.
- Asset references for `pedro.tga`, `logo-minimap.tga`, `ready.mp3`, and `ready2.mp3` must be explicit and covered by tests where relevant.

## Architecture

### Bloodlust

`BloodlustSound.lua` remains the module entrypoint, but its internals are clarified around four concerns:

- icon source resolution
- sprite frame application for `PEDRO`
- frame/edit-mode visibility
- effect lifetime (audio + cooldown/timer + stop path)

The square background is removed from normal runtime rendering. Shared edit-mode visuals from `TrackerFrame.lua` remain the source of edit-mode affordance.

### Settings

`Settings.lua` keeps the current two-column functional layout and section rendering contract, but its shell is rebuilt:

- top-level window chrome uses the `PedroLust`-style flat shell
- header becomes a first-class frame with title, byline, and version line
- left navigation becomes a flat sidebar with selected-state emphasis
- right content pane becomes a flat panel container for existing grouped blocks

The module settings APIs do not change.

### Cleanup boundaries

Cleanup is targeted and local:

- no unrelated refactors
- no new framework
- no change to runtime tracker skin

## Testing

- Add or adjust regression tests for the `Pedro` sprite-sheet path and its configuration surface.
- Add or adjust source-based tests for the new settings shell structure and minimap/logo references as needed.
- Run the full `SunderingTools/tests` suite after implementation.
- Run `git diff --check` in the addon repo before claiming completion.

## Risks

- The settings shell redesign touches a large file, so layout regressions are possible if heights/anchors drift.
- The `Pedro` fix must avoid breaking `BL Icon` and `Custom` texture modes.
- Cleanup must not accidentally alter module behavior while improving organization.

## Success Criteria

- `Pedro` animates cleanly without the black square artifact.
- The settings window clearly matches the referenced `PedroLust` shell style.
- Existing settings behavior still works.
- The repo is easier to navigate in the touched areas.
- Tests pass cleanly.
