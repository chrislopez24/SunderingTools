# SunderingTools

Lightweight WoW addon with interrupt, crowd control, party defensive, raid defensive, and bloodlust tracking.

## Strict Sync PvE Mode

The trackers support a strict sync-first mode for party and raid PvE. When enabled per tracker, the addon prefers owner-authoritative addon sync and manifest-backed spell ownership, hides uncertain remote data, and uses clock-safe `remaining` payloads instead of sender-local absolute cooldown timestamps.

The repository is set up for tagged GitHub release packaging via the BigWigs packager.

## Release

Create a tag like `v1.0.0` to trigger the GitHub Actions packaging workflow.
The workflow uses BigWigs packager and emits a release zip with `SunderingTools/` as the addon root.
