# OmniCD Interrupt Tracker Redesign

**Context**

`SunderingTools` keeps its own interrupt tracking logic, but the current tracker presentation does not match the desired visual quality. The target is the visual language of `OmniCD` status bars: flat class-colored ready bars, integrated left icon, dark border, compact typography, and timer shown only while cooling down.

**Goals**

- Keep the existing interrupt tracking logic and event matching in `Modules/InterruptTracker.lua`.
- Replace the current tracker visuals with an OmniCD-like bar layout.
- Simplify tracker settings so the panel supports the intended visual style instead of exposing controls that break it.
- Preserve `Edit Mode`, `Reset Position`, and preview support while making preview visually representative of the final tracker.

**Non-Goals**

- Do not port OmniCD code directly.
- Do not adopt OmniCD data models, spell databases, or cooldown sync behavior.
- Do not redesign the global settings shell beyond what is needed for the tracker panel to stay coherent.

**Visual Direction**

- Each row is a compact rectangular bar with a small square icon on the left and a flat status area on the right.
- `Ready` state shows only the player name on a class-colored inactive background.
- `Cooldown` state shows a fill/status texture with the timer aligned to the right and the name aligned to the left.
- Borders are subtle and dark, similar to the OmniCD status bar frame.
- Text remains compact and high-contrast, avoiding bright fantasy styling, oversized labels, or stacked overlays.

**Behavior**

- Existing interrupt tracking remains unchanged:
  - player direct trigger by interrupt spell
  - party matching via temporal correlation of party cast, enemy interrupted event, and aura filtering
- Preview remains available in two cases:
  - forced while edit mode is enabled
  - optionally visible while solo through a dedicated setting
- Preview bars must visually match the final tracker, including icon placement, border, class color, and timer treatment.

**Settings Scope**

The tracker panel should be simplified to the controls that still make sense for an OmniCD-style presentation:

- `Enabled`
- `Open Edit Mode`
- `Reset Position`
- `Show Preview When Solo`
- `Maximum Bars`
- `Grow Direction`
- `Bar Spacing`
- `Bar Width`
- `Bar Height`
- `Icon Size`
- `Font Size`
- `Show Name`
- `Show Timer`

The following options should no longer drive the main UI and should be removed from the panel:

- `Ready Text`
- `Show Ready Text`
- split text sizing between name and timer
- class-color toggles that conflict with the fixed OmniCD-style presentation

**Implementation Shape**

- `Modules/InterruptTracker.lua` remains the main runtime file and receives the bar rendering refactor plus settings cleanup.
- `Modules/InterruptTrackerModel.lua` remains the source of preview/sample data and sorting helpers.
- Existing static regression tests are extended to lock the new settings surface and prevent reintroduction of the old visual controls.

**Validation**

- Automated validation is limited to static tests in this environment.
- In-game validation must confirm:
  - ready bars look like OmniCD-style rows
  - cooldown bars show timer correctly
  - edit mode preview is draggable and visually representative
  - solo preview matches the final visual treatment
