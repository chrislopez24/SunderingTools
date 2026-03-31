# Loxx-Style Interrupts And Reliable Raid Sync Design

## Goal

Bring `InterruptTracker` to the same operational model as `LoxxInterruptTracker` for party interrupt attribution, while keeping SunderingTools' stronger runtime/state model, and harden `DefensiveRaidTracker` so bar-based raid cooldown tracking remains reliable through owner-authoritative sync plus local inference.

## Scope

- Migrate interrupt attribution to a Loxx-style flow:
  - owner-authoritative manifest and state sync
  - timestamp correlation from `UNIT_SPELLCAST_SUCCEEDED` on party and party pets
  - enemy interrupt and short channel-stop correlation
  - periodic self state rebroadcast while on cooldown
- Keep SunderingTools UI unchanged.
- Keep `PartyDefensiveTracker` on the MiniCC-style watcher/inference model already implemented.
- Strengthen `DefensiveRaidTracker` for bar rendering with sync and local inference, especially for spells like `Anti-Magic Zone`.

## Non-Goals

- No UI redesign.
- No attempt to bypass Blizzard secret restrictions.
- No replacement of the MiniCC-style aura watcher core for party or nameplate aura tracking.

## Constraints

- `SendAddonMessage` may only carry non-secret payloads.
- Interrupt attribution for non-addon users must not depend on readable remote `spellID`.
- Nameplate and raid tracking must stay compatible with Blizzard secret-value behavior in current live API docs.

## Architecture

### Interrupt Tracker

`InterruptTracker` will use three cooperating layers:

1. Discovery and authority
   - `HELLO` announces presence/spec.
   - `INT_MANIFEST` declares authoritative interrupt spells for addon users.
   - `INT` carries owner-authoritative cooldown state for active cooldowns.

2. Correlation fallback
   - party and party pet `UNIT_SPELLCAST_SUCCEEDED` only record timestamps, never consume remote `spellID`
   - enemy `UNIT_SPELLCAST_INTERRUPTED` and short `CHANNEL_STOP` resolve the best candidate inside a narrow window
   - self casts remain exact and outrank correlation ties

3. Runtime arbitration
   - `CombatTrackEngine` remains the source-of-truth
   - source priority stays `auto < correlated < sync < self`
   - module logic should consume the engine’s correlation API instead of hand-rolling duplicate correlation state

### Defensive Raid Tracker

`DefensiveRaidTracker` remains a hybrid tracker:

1. Local watcher/inference
   - `UnitAuraStateWatcher` and `FriendlyCooldownInference` detect visible raid-defensive auras and infer cooldown starts where possible

2. Owner-authoritative sync
   - `HELLO` and `DEF_MANIFEST` declare ownership and spell inventory
   - `DEF_STATE` carries active cooldown state for bar rendering
   - self state is periodically rebroadcast while on cooldown so late joiners and drifted peers can recover

3. Runtime merge
   - sync should outrank aura inference
   - aura inference should still seed bars when no sync exists

## Data Flow

### Interrupts

1. Local player cast:
   - resolve canonical interrupt spell
   - apply `self` cast to `CombatTrackEngine`
   - broadcast `INT`
   - seed self correlation timestamp

2. Party or pet cast:
   - record timestamp only if the owner plausibly has an interrupt and is not already cooling down
   - feed that timestamp into `CombatTrackEngine` pending-cast correlation state

3. Enemy interrupted or early channel stop:
   - ask `CombatTrackEngine` to resolve the best pending cast within the correlation window
   - if ambiguous, consume and drop
   - if matched, apply correlated cooldown

4. Late sync recovery:
   - while local interrupt is on cooldown, periodically rebroadcast `INT`
   - on `HELLO` from peers, replay current self state immediately

### Raid Defensives

1. Local cast:
   - normalize spell to canonical tracked raid-defensive entry
   - apply `self` state to the engine
   - broadcast `DEF_STATE`

2. Local aura detection:
   - watcher collects `BIG_DEFENSIVE` and `IMPORTANT`
   - inference promotes matching raid-defensive rules into engine entries

3. Remote sync:
   - manifest establishes authority for remote spell lists
   - `DEF_STATE` updates cooldown bars directly
   - periodic self rebroadcast keeps peers converged

## Reliability Rules

- Never index tables with remote secret values.
- Never require remote readable `spellID` from party spellcast events.
- Prefer sync over correlation, and correlation over class/spec fallback.
- Consume ambiguous interrupt candidates without attribution rather than guessing.
- Keep periodic rebroadcast throttled so it helps convergence without spamming.

## Testing Strategy

- Add runtime Lua tests for interrupt behavior, not just source-slice assertions.
- Cover:
  - correlated party interrupt attribution
  - self winning ties
  - ambiguity suppression
  - periodic `INT` rebroadcast while local cooldown is active
  - periodic `DEF_STATE` rebroadcast while local raid cooldown is active
  - replay on `HELLO`
- Remove or rewrite tests that only assert legacy implementation details no longer needed after the migration.

## Expected Outcome

- Interrupt bars behave like Loxx in mixed groups, including non-addon party members and pet kicks.
- Raid defensive bars remain accurate for addon users through sync and degrade gracefully to local inference when sync is absent.
- The runtime stays aligned with Blizzard secret-value constraints.
