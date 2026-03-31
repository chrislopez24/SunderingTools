# MiniCC-Style Tracking Core Design

**Date:** 2026-03-31

## Goal

Rebuild SunderingTools tracking logic around the same operating model that makes MiniCC reliable:

- visible-aura tracking for active CC, defensives, and important buffs
- evidence-backed cooldown inference for friendly defensives and raid defensives
- cast/correlation-backed interrupt tracking when direct state is unavailable
- zero secret-value indexing or serialization

The existing UI, frames, settings layout, and visual presentation stay intact unless a logic fix requires a minimal rendering change.

## Product Direction

SunderingTools should stop mixing several partial strategies:

- ad-hoc spell DB lookups from aura payloads
- sync-first enrichment for cases that are actually inferable locally
- separate module-specific aura fallback logic

Instead, it should use one coherent tracking stack:

1. collect active visible auras safely
2. collect concurrent public evidence safely
3. infer cooldown state from those signals
4. expose normalized state to the existing trackers and nameplate renderers

This matches MiniCC much more closely and keeps the addon defensible against Blizzard secret restrictions.

## Current Problems

### Secret handling is fragmented

Several modules still accept spell IDs from live aura payloads and only sanitize them after the fact, which leads to crashes and inconsistent unknown-state handling.

### Defensive tracking is too literal

`PartyDefensiveTracker` and `DefensiveRaidTracker` still rely on spell-centric fallback/resolution flows where MiniCC instead treats the aura as a timed signal and infers the cooldown when the aura ends.

### Nameplate CC is underpowered

`NameplateCrowdControl` still behaves like a bespoke tracker instead of simply consuming a visible CC aura state stream the way MiniCC does.

### Interrupt tracking is too separate

`InterruptTracker` has its own path instead of sharing the same evidence model. Loxx/Kryos show that interrupt cooldown tracking becomes much better when cast evidence, spec/talent knowledge, and public combat signals are unified.

### Tests overfit old implementation seams

Some tests still target old helper layout or legacy modules rather than the behavior of the new tracking model. The final repo should keep only tests that validate the new functional surface.

## Target Architecture

### 1. Visible Aura Watcher Core

Add a new watcher core modeled after MiniCC `UnitAuraWatcher`:

- reads `C_UnitAuras.GetUnitAuras(unit, filter, ...)`
- resolves `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)`
- classifies auras through safe filters first:
  - `HARMFUL|CROWD_CONTROL`
  - `HELPFUL|BIG_DEFENSIVE`
  - `HELPFUL|EXTERNAL_DEFENSIVE`
  - `HELPFUL|IMPORTANT`
- stores normalized aura records:
  - `AuraInstanceID`
  - `SpellID` only when non-secret
  - `SpellName` only when non-secret
  - `SpellIcon` only when non-secret
  - `DurationObject`
  - category flags
  - optional dispel/category color

This watcher is the source of truth for:

- `NameplateCrowdControl`
- active friendly CC/defensive indicators
- active bloodlust/lockout detection
- aura-driven inference entrypoints

### 2. Friendly Evidence Collector

Add a second core component modeled after MiniCC `FriendlyCooldownTrackerModule` evidence gathering:

- `UNIT_SPELLCAST_SUCCEEDED`
- `UNIT_FLAGS`
- `UNIT_AURA` additions for harmful/public side effects
- `UNIT_ABSORB_AMOUNT_CHANGED`
- optional `COMBAT_LOG_EVENT_UNFILTERED` support only for public, stable signals

Store short-lived timestamps keyed by unit:

- recent cast time
- recent harmful-debuff add time
- recent absorb/shield event time
- recent unit flags change
- optional feign-death style state transitions when needed

This collector must never depend on secret payload extraction. It only records public timing evidence.

### 3. Rule-Based Cooldown Inference Engine

Create a normalized inference engine that:

- starts tracking when a watched aura instance appears
- snapshots concurrent evidence and per-unit cast timestamps
- measures real aura lifetime when the aura disappears
- matches against rules by:
  - class/spec
  - aura type
  - expected buff duration
  - evidence requirements
  - talent/spec gating
  - early-cancel tolerance
- emits normalized cooldown entries for renderers

This engine will be used for:

- party defensives
- raid defensives
- crowd-control bars where aura duration is the meaningful state
- interrupts when enough public evidence exists

### 4. Talent/Spec Resolution Layer

Replace the current narrow local-talent cooldown modifiers with a shared resolver inspired by MiniCC `FriendlyCooldownTalents`:

- keep local-player authoritative talent knowledge
- accept cooperative spec/talent sync when available
- cache resolved spec/talent info by player
- apply cooldown and duration modifiers to inference rules

`CooldownViewerMeta` becomes optional metadata only. It must no longer be a core dependency for tracker correctness.

### 5. Tracker Adapters

Keep the current SunderingTools modules as view/adaptor layers:

- `NameplateCrowdControl` consumes visible CC aura state directly
- `PartyDefensiveTracker` consumes inferred defensive cooldown state
- `DefensiveRaidTracker` consumes inferred raid defensive cooldown state
- `InterruptTracker` consumes direct self/sync state when known and evidence-inferred state otherwise
- `CrowdControlTracker` consumes inferred/shared CC bar state
- `BloodlustSound` consumes active aura state directly and regains correct sound triggering

The existing settings panels, frame placement, and bar/icon presentation stay in place.

## Module Migration Strategy

### Nameplate CC

Move to a watcher-driven model:

- no custom unknown-payload tracker as primary path
- no fallback question-mark icon behavior
- active visible CC auras render directly from watcher state
- sync enrichment may remain only as a secondary enhancement, not as the main mechanism

### Party and Raid Defensives

Replace `PartyDefensiveAuraFallback` with an inference path:

- active aura appears on a party unit
- aura gets tracked with evidence snapshot
- when aura disappears, infer cooldown from matched rule
- update active cooldown bars/icons on the owner unit

This should match MiniCC behavior much more closely than the current spell-ID fallback.

### Interrupts

Use a hybrid path:

- self and cooperative sync remain owner-authoritative when available
- inference path adds support using public cast evidence and known class/spec interrupt rules
- Loxx/Kryos style timestamp correlation can be reused for cases where unit spellcast timing is the best available signal

Interrupt bars should be treated as cooldown entries in the same normalized engine shape as defensives.

### Bloodlust Sound

Switch active/lockout detection to the shared visible-aura watcher path:

- active bloodlust-family helpful aura starts or resumes the sound/display state
- lockout debuffs are tracked through the same safe visible-aura path
- no direct secret-string or secret-spell indexing

## File-Level Refactor Direction

### New Core Files

- `Core/UnitAuraStateWatcher.lua`
  - shared visible-aura watcher
- `Core/FriendlyEventEvidence.lua`
  - public event timestamp collector
- `Core/FriendlyCooldownInference.lua`
  - tracked-aura lifecycle + rule matching + cooldown entry emission
- `Core/FriendlyTrackingRules.lua`
  - spec/class rule book for defensives, raid defensives, interrupts, and tracked CC
- `Core/FriendlyTalentResolver.lua`
  - local/cooperative spec and talent modifiers

### Existing Core Files Likely Removed or Shrunk

- `Core/PartyCrowdControlAuraWatcher.lua`
- `Core/PartyCrowdControlResolver.lua`
- `Core/PartyDefensiveAuraFallback.lua`
- parts of `Core/CooldownViewerMeta.lua`
- large pieces of `Core/CombatTrackSpellDB.lua` that are currently acting as both catalog and runtime resolution engine

### Existing Module Files To Adapt

- `Modules/NameplateCrowdControl.lua`
- `Modules/PartyDefensiveTracker.lua`
- `Modules/DefensiveRaidTracker.lua`
- `Modules/InterruptTracker.lua`
- `Modules/CrowdControlTracker.lua`
- `Modules/BloodlustSound.lua`

## Testing Strategy

### Keep

- behavior tests for watcher output, inference rules, cooldown emission, and module-visible state
- runtime harness tests that execute real Lua modules
- packaging tests that validate shipped entrypoints

### Remove or Rewrite

- tests that only assert helper names or old file seams
- tests for modules/components deleted by the migration
- redundant slice tests that no longer validate runtime behavior

The final test suite should reflect only the target tracking model and shipped functionality.

## Risks

- porting MiniCC-style logic without overfitting to its UI assumptions
- keeping existing SunderingTools tracker surfaces stable while changing their internals
- avoiding regressions in secret-safe behavior when widening inference coverage
- not letting interrupt logic sprawl into a second unrelated engine

## Success Criteria

- no tracker crashes on secret values
- visible CC/defensive/important auras use a single shared watcher path
- party and raid defensive cooldowns are inferred with MiniCC-style evidence/rule matching
- interrupts share the same normalized cooldown-state pipeline where possible
- bloodlust sound/display works reliably on active aura detection
- obsolete modules/tests are deleted when they no longer serve the shipped behavior
