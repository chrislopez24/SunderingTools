# Strict Sync PvE Tracking Design

**Date:** 2026-03-30

## Goal

Define a `sync-first` strict tracking mode for `party/raid PvE` that produces realistic, high-confidence data for:

- interrupts
- crowd control cooldowns
- personal defensives
- raid defensives

The target is not theoretical 100% across the WoW addon API. The target is the closest practical result to 100% when all relevant players have the addon installed, while hiding uncertain data instead of guessing.

## Why This Mode Exists

Blizzard's retail API explicitly supports secret-value restrictions for aura and cooldown queries. In practice this means remote observation cannot always be trusted as a full source of truth. The design therefore treats the owner of a spell as authoritative for that spell's runtime state.

For this mode, owner-authoritative sync is primary. Local observation is secondary and only used to confirm, enrich, or invalidate state.

## Scope

### Included

- party and raid PvE only
- active, synchronizable spells only
- owner-authoritative tracking for addon users
- strict hide-on-uncertainty behavior
- sync manifest and state replay
- shared handling across `InterruptTracker`, `CrowdControlTracker`, `PartyDefensiveTracker`, and `DefensiveRaidTracker`

### Excluded

- battleground or world-specific degradation behavior
- passive and proc defensives such as cheat-death effects
- heuristic fallback for players without addon sync
- global active-CC target state outside units that the local client can directly validate
- "best guess" interrupt or cooldown attribution

## Product Rules

### Trust model

Every tracked entry carries a source and a confidence tier:

- `self`: owner-local, highest confidence
- `sync`: owner-sent state from another addon user, high confidence
- `observed`: locally validated state that confirms an existing owner record
- `invalid`: known stale or contradicted data, hidden from UI

Strict mode never promotes uncertain data into a visible cooldown.

### Visibility rule

If a player has not published a valid manifest and usable state for a given spell family, that spell is not shown.

This is intentional. Missing data is preferable to false confidence.

## Architecture

### Shared runtime contract

`Core/CombatTrackEngine.lua` remains the single runtime store for cooldown entries, but the meaning of sources becomes stricter:

- `self` and `sync` are authoritative
- `correlated` and `auto` are not used to create visible entries in strict mode
- local observation may mutate an existing entry into `invalid` or attach validation metadata, but may not invent an entry

This keeps one engine while making strict mode a product policy instead of a per-module heuristic.

### Manifest-first registration

Each addon user publishes the spells they truly own in the relevant bucket:

- `INT_MANIFEST`
- `CC_MANIFEST`
- `DEF_MANIFEST`
- `RAID_DEF_MANIFEST`

Each manifest item should resolve locally on the owner before broadcast and include the effective data needed for replication:

- canonical spell ID
- effective cooldown
- charges, if relevant
- spec ID
- optional talent hash or manifest version

For non-local users, runtime registration only happens from manifest data. Class-only fallback is disabled in strict mode.

### State-first replication

After manifest registration, the owner publishes runtime updates:

- cast or use events
- current active cooldown state for replay
- charge state when relevant
- invalidation or reset when state becomes obsolete

The receiver trusts the owner record, not remote inference.

## Protocol Design

### Current limitation to remove

Current defensive sync transmits `readyAt` based on `GetTime()` from the sender session. That value is not a shared clock across clients and is not safe as a replicated absolute timestamp.

Strict mode must stop using sender-local session time as cross-client truth.

### Required message shape

Messages should move to a clock-safe format:

- manifest messages describe static ownership and resolved spell metadata
- cast messages describe a fresh use detected locally by the owner
- state messages describe remaining cooldown and charges as of send time

Preferred fields:

- `spellID`
- `kind`
- `baseCD`
- `remaining`
- `charges`
- `maxCharges`
- `manifestVersion`

`v1` does not depend on a shared absolute clock. If replay smoothing later needs one, that should be treated as a follow-up enhancement rather than part of the initial strict-mode contract.

Receivers rebuild local `startTime` and `readyAt` from their own `GetTime()` at receipt using the transmitted remaining duration.

## Per-Tracker Behavior

### Interrupts

The owner publishes exactly one supported interrupt entry in PvE strict mode unless class design requires otherwise.

Rules:

- local player resolves interrupt spell and cooldown locally
- remote users are shown only if they have published an interrupt manifest
- `UNIT_SPELLCAST_SUCCEEDED` on the owner drives `INT_CAST`
- remote interrupted-target heuristics are no longer allowed to create visible entries

Observation remains useful only for:

- sanity checks
- metrics
- desync detection

### Crowd control

Strict mode tracks cooldown usage, not omniscient target state.

Rules:

- supported CC list stays curated and explicit
- owner syncs `CC_CAST` on use
- cooldown spent is shown from sync even if the target was immune
- active CC state on a target is only shown when the local client can validate the aura on an observed unit

This separates:

- `CC used and on cooldown`
- `CC currently active on a visible target`

The first can be near-owner-perfect with sync. The second remains line-of-sight and visibility dependent.

### Personal defensives

The owner resolves all active personal defensives locally from known spells, spec, and talent state.

Rules:

- manifest includes effective cooldown and charges
- self cast drives `DEF_CAST`
- current state replay drives `DEF_STATE`
- local aura validation may confirm the active window if visible
- aura validation may invalidate clearly stale sync state

Passive or proc defensives are excluded from this mode entirely.

### Raid defensives

Raid defensives follow the same pattern as personals, but stay in their own bucket and UI.

Rules:

- owner manifest is required
- owner cast is authoritative for cooldown start
- state replay is required for reload, zone change, and late join recovery
- visible aura windows may validate activity, but not replace owner authority

## Reconciliation Rules

### Replay and join behavior

When a player joins, reloads, or sends `HELLO`, addon users should resend:

- their manifest
- their currently active cooldown states

This avoids losing accurate state after client reloads or roster churn.

### Desync handling

If local validation strongly contradicts synced state:

- mark entry as desynced internally
- hide or invalidate the entry in strict mode
- never guess a replacement state

Examples:

- synced aura-active window has already ended and no confirming aura is visible on a directly observable unit
- manifest version changed after talents or spells changed
- state replay references a spell not present in the latest manifest

### Encounter lifecycle

Strict mode needs deterministic cleanup around PvE lifecycle boundaries:

- `ENCOUNTER_START`
- `ENCOUNTER_END`
- `PLAYER_ENTERING_WORLD`
- `GROUP_ROSTER_UPDATE`
- wipe or release transitions when relevant

The goal is to prefer clearing stale state over preserving possibly wrong state.

## Workarounds That Are Worth Implementing

- owner-authoritative manifests for all four tracked buckets
- state replay on hello, reload, and roster change
- clock-safe sync using remaining duration instead of sender-local absolute times
- local validation from auras only as confirmation or invalidation
- manifest versioning so talent and spell changes invalidate old runtime entries
- strict-mode hide policy for missing or contradictory data

## Workarounds That Are Not Worth Implementing

- guessing remote cooldowns from class, role, or recent cast noise
- showing partial data with a false aura of certainty
- trying to derive omniscient target CC state for non-observed units
- mixing strict and heuristic semantics in the same visible tracker without explicit product separation

## Risks

- strict mode will intentionally show less data in partially-adopted groups
- message volume will increase due to manifest and replay traffic
- charge-based spells need careful protocol design to avoid drift
- existing tests assume some looser sync semantics and will need updating

## Testing Strategy

### Unit tests

- sync encode/decode for new manifest and state message shapes
- engine reconstruction from `remaining`-based state payloads
- manifest version invalidation
- late join replay handling
- strict hide behavior when manifest is absent

### Module tests

- interrupt tracker refuses to show non-manifest users in strict mode
- CC tracker separates cooldown-use from aura-active confirmation
- party defensive tracker rebuilds state correctly after replay
- raid defensive tracker clears stale entries on lifecycle events

### Manual verification

- 5-player addon-only dungeon run with reload mid-key
- raid roster change during active raid defensive cooldowns
- talent swap outside instance followed by regroup
- conflicting local validation and synced state to confirm hide/invalidate behavior

## Success Criteria

- With all relevant players running the addon, tracked active and synchronizable PvE cooldowns are owner-authoritative and high confidence.
- Missing sync never produces guessed visible entries in strict mode.
- Session-local timestamps are no longer used as cross-client absolute truth.
- The same strict confidence policy applies consistently across interrupts, CC, personal defensives, and raid defensives.
