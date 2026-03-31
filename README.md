# SunderingTools

Lightweight WoW addon with interrupt, crowd control, party defensive, raid defensive, and bloodlust tracking.

## Tracker Model

SunderingTools keeps cooldown bars as the primary layer for interrupts, crowd control, and raid defensives, with secondary live-state overlays where they improve reliability:

- Crowd control bars start from resolved runtime events and active CC can also appear on nameplates while the aura is live.
- Party defensives stay attached to Blizzard party frames and combine addon sync with aura-driven fallback automatically.
- Remote sync and fallback policy is automatic; there are no user-facing strict sync toggles.

The repository is set up for tagged GitHub release packaging via the BigWigs packager.

## Release

Create a tag like `v1.0.0` to trigger the GitHub Actions packaging workflow.
The workflow uses BigWigs packager and emits a release zip with `SunderingTools/` as the addon root.
