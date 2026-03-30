# Settings Parity Design

**Goal:** Bring the addon settings to UI/runtime parity so every persisted setting that should be user-facing is exposed, and every exposed setting has an immediate, correct effect.

**Scope**

- Audit all current settings in `Settings.lua`, `SunderingTools.lua`, and module `defaults` / `buildSettings` / `onConfigChanged` paths.
- Fix settings that are visible but do not fully apply their intended behavior.
- Expose settings that already exist in persisted defaults and have clear runtime semantics, but are currently missing from the UI.
- Add regression coverage for the gaps found during the audit.

**Out of Scope**

- Inventing new settings or changing tracker behavior beyond what existing defaults already imply.
- Refactoring the full settings system into a schema-driven renderer.
- Broad combat/runtime changes unrelated to settings application.

## Current Findings

### General

- General settings already expose the expected controls for minimap visibility, minimap unlock/reset, edit mode, debug mode, and reset-all.
- The current `General` page appears internally consistent: the controls map to addon methods and those methods mutate DB and runtime state directly.

### Interrupt Tracker

- The visible settings appear to have a complete `UI -> SetModuleValue -> onConfigChanged -> runtime refresh` path.
- Ready-sound controls are already exposed and routed through DB.
- No hidden persisted settings requiring exposure were identified in this module.

### Crowd Control Tracker

- The visible settings appear to have a complete `UI -> SetModuleValue -> onConfigChanged -> runtime refresh` path.
- `filterMode` is persisted and exposed correctly.
- No hidden persisted settings requiring exposure were identified in this module.

### Bloodlust Sound

- Persisted defaults include `duration`, but the UI currently exposes no control for it.
- `duration` already has runtime semantics via `Model.ResolveDuration(...)`, so this setting should be surfaced.
- `soundFile`, `soundChannel`, `iconStyle`, `customIconPath`, `hideIcon`, and `iconSize` already exist in the UI and runtime.

### Party Defensive Tracker

- Persisted defaults include `maxIcons`, `iconSize`, `iconSpacing`, `attachPoint`, `relativePoint`, `offsetX`, `offsetY`, and `showTooltip`.
- The current UI only exposes `enabled`, `previewWhenSolo`, and `syncEnabled`, so the module is notably incomplete.
- `showTooltip` is effectively dead today because attachment icons do not register tooltip handlers.
- Existing attachments are not re-anchored when attachment settings change after creation; the anchor point is only set during initial attachment creation.
- Existing attachments need an explicit live refresh path for anchor/layout changes.

### Defensive Raid Tracker

- The visible settings appear to have a complete `UI -> SetModuleValue -> onConfigChanged -> runtime refresh` path.
- No hidden persisted settings requiring exposure were identified in this module.

## Blizzard Secret-Value API Note

The latest live Blizzard API docs in `Gethe/wow-ui-source` expose secret-value checks under `C_Secrets` in `SecretPredicateAPIDocumentation.lua`, including `HasSecretRestrictions`, `ShouldAurasBeSecret`, `ShouldUnitAuraIndexBeSecret`, and related helpers. This settings-parity work does not require changing secret-value handling, but the implementation should avoid introducing any new assumptions that conflict with those APIs.

## Design

### Settings Audit Rule

For each setting we keep in scope, the implementation must satisfy all of these:

1. It exists in defaults or addon-global state.
2. If it is meant to be configurable by users, it appears in the settings UI.
3. UI changes persist through `SetModuleValue` or equivalent addon-global setters.
4. The runtime updates immediately or on the next relevant refresh path without requiring a reload.
5. There is regression coverage for the identified gap.

### Bloodlust Sound Changes

- Add a `Duration` slider to the Bloodlust settings page.
- The slider will write `BloodlustSound.duration`.
- Runtime behavior will continue to use the existing `Model.ResolveDuration(auraDuration, db.duration)` path.
- `onConfigChanged` does not need special live refresh for `duration` because the value is consumed when the next effect starts; no immediate frame mutation is required.

### Party Defensive Tracker Changes

- Expand the settings page into structured sections matching the rest of the addon.
- Add layout controls for:
  - `maxIcons`
  - `iconSize`
  - `iconSpacing`
  - `attachPoint`
  - `relativePoint`
  - `offsetX`
  - `offsetY`
- Add a behavior control for `showTooltip`.
- Keep existing controls for `enabled`, `previewWhenSolo`, and `syncEnabled`.
- Preserve the legacy normalization path in `NormalizeAttachmentSettings(...)`.

### Party Defensive Runtime Changes

- Attachment containers must be re-anchored every time attachment settings can change, not only on first creation.
- Layout refresh must resize/reflow existing icon frames using current DB values.
- Tooltip support must be added to icons and must be conditional on `showTooltip`.
- Tooltip content should match the current attachment entry:
  - player/owner name when available
  - tracked spell name when available
  - ready/cooldown status with remaining time when cooling down

### Testing Strategy

- Add Lua runtime tests for `PartyDefensiveTracker` that fail before the fix and pass after it:
  - anchor/offset updates apply to existing attachments
  - `maxIcons`, `iconSize`, and `iconSpacing` affect rendered layout
  - tooltip handlers exist and honor `showTooltip`
- Add static tests for:
  - Party Defensive Tracker settings page exposes the full persisted settings set
  - Bloodlust Sound exposes `Duration`
- Keep the existing tests for the other modules passing to validate no regressions in the settings shell.

## Files Expected To Change

- `Modules/PartyDefensiveTracker.lua`
- `Modules/BloodlustSound.lua`
- `tests/modules/test_party_defensive_tracker.lua`
- `tests/test_settings_ui_redesign.py`
- `tests/test_review_fixes.py`

Potentially:

- `tests/modules/test_bloodlust_sound.lua` if runtime-level Bloodlust settings coverage is needed

## Success Criteria

- Every visible setting in the addon continues to mutate the correct DB key and produce the intended behavior.
- `PartyDefensiveTracker` no longer has persisted layout/tooltip settings hidden from the UI.
- `PartyDefensiveTracker.showTooltip` has real runtime behavior.
- `BloodlustSound.duration` is user-configurable from the UI.
- The relevant test suite passes after the implementation.
