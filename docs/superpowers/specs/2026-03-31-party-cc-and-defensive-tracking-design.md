# Party CC And Defensive Tracking Design

## Goal

Modernize party crowd control and personal defensive tracking while preserving the current addon UI:

- Party personals remain as icons attached to Blizzard-style party frames.
- Active crowd control is shown on nameplates while the aura exists.
- Crowd control cooldowns are shown in bars from application time until the cooldown ends.

The result must stay stable under Blizzard's current restricted aura model and secret-value API behavior.

## Scope

This design covers:

- Party personal defensive tracking logic
- Party crowd control cooldown tracking logic
- Active crowd control rendering on nameplates
- Source-priority rules across self casts, sync, aura detection, and heuristics
- Secret-safe handling rules

This design does not change the visible addon UI layout patterns unless required to preserve current behavior.

## Product Decisions

### Party Personals

- Keep the current attached-icon UI.
- Keep addon sync as the primary source of truth.
- Add MiniCC-style aura-based detection only as a fallback when no owner-authoritative state is available.
- Prefer hiding uncertain data over showing guessed cooldowns.

### Crowd Control

- While CC is active, show it on the relevant nameplate using live aura duration.
- Also start the owner's CC cooldown bar when the CC is applied, if the resolver can identify the spell and caster with sufficient rigor.
- The cooldown bar continues after the CC aura ends until the cooldown expires.
- If a stronger source arrives later, update the existing cooldown entry rather than creating a duplicate.

## External Constraints

### Blizzard API Constraints

The implementation must assume Blizzard's modern restricted aura environment:

- Some aura-derived values may be secret or partially restricted.
- `spellID`, `sourceUnit`, names, GUIDs, colors, and other aura-derived values may not always be usable.
- Safe classification APIs exist and should be used as the first filter:
  - `C_Spell.IsSpellCrowdControl`
  - `C_Spell.IsSpellImportant`
  - `C_UnitAuras.AuraIsBigDefensive`
  - `C_UnitAuras.GetAuraDuration`
  - `issecretvalue`
- Addon sync remains a supported public path through:
  - `C_ChatInfo.RegisterAddonMessagePrefix`
  - `C_ChatInfo.SendAddonMessage`

### Engineering Constraints

- Preserve current addon UI expectations.
- Logic may be rewritten or split into new files if it improves reliability and maintainability.
- Detection logic must be testable without frame rendering code.
- Heuristics are allowed only behind clear confidence rules.

## High-Level Architecture

The system should be split into four responsibilities:

1. Aura observation
2. Resolution and normalization
3. Runtime tracking state
4. UI rendering

This removes the current tight coupling between detection logic and presentation and allows different surfaces to consume the same normalized events.

## Proposed Components

### `Core/PartyCrowdControlAuraWatcher.lua`

Responsibility:

- Observe active crowd control auras for relevant units.
- Emit normalized lifecycle events such as:
  - `CC_APPLIED`
  - `CC_UPDATED`
  - `CC_REMOVED`

Inputs:

- Unit tokens appropriate for the surface
- Blizzard aura APIs

Outputs:

- Secret-safe normalized aura snapshots

Rules:

- Use safe classification APIs before reading other aura fields.
- Never assume `spellID` or `sourceUnit` is usable without checking `issecretvalue`.
- Treat "cannot identify" as a first-class outcome.

### `Core/PartyCrowdControlResolver.lua`

Responsibility:

- Convert CC aura events plus sync/self-cast evidence into a resolved owner/spell/cooldown decision.
- Assign source and confidence.
- Upgrade existing entries when better evidence arrives.

Inputs:

- CC aura watcher events
- Self cast events
- Sync payloads
- Existing spell database data
- Optional correlation signals

Outputs:

- Normalized CC active and CC cooldown records

This component is the policy layer. It should contain the rules that decide whether a cooldown bar is created, updated, promoted, or suppressed.

### `Core/PartyDefensiveAuraFallback.lua`

Responsibility:

- Observe personal and external defensive auras on party units.
- Reconstruct personal defensive cooldowns only when sync is absent or insufficient.
- Publish normalized fallback defensive cooldown events to the existing defensive runtime pipeline.

This is intentionally not a replacement for sync. It is a secondary evidence source.

### Existing UI Modules

#### `Modules/PartyDefensiveTracker.lua`

- Remains the attached-icon UI.
- Continues to consume runtime defensive state.
- Gains source awareness but should not own fallback detection policy.

#### `Modules/CrowdControlTracker.lua`

- Becomes explicitly the CC cooldown bar surface.
- Consumes normalized CC cooldown records from the resolver.
- Should no longer directly own low-level aura detection.

#### Nameplate CC Module

- Either add a dedicated module such as `Modules/NameplateCrowdControl.lua` or extend the existing nameplate surface in a tightly-scoped way.
- Shows active CC only while the aura exists.
- Does not own cooldown inference.

## Data Model

All detection sources should publish normalized runtime entries with the same shape so UI modules do not care where the data came from.

### Normalized Fields

- `kind`
  - `CC_ACTIVE`
  - `CC_CD`
  - `DEF_CD`
- `spellID`
- `ownerGUID`
- `ownerUnit`
- `ownerName`
- `targetGUID` when relevant
- `targetUnit` when relevant
- `source`
  - `self`
  - `sync`
  - `aura`
  - `correlated`
- `confidence`
  - `high`
  - `medium`
- `startTime`
- `endTime`
- `baseCd`
- `uiSurface`
  - `partyIcon`
  - `bar`
  - `nameplate`

### Identity Rules

- `CC_ACTIVE` identity should key by target plus aura instance or equivalent stable lifecycle key.
- `CC_CD` identity should key by owner plus resolved spell.
- `DEF_CD` identity should key by owner plus resolved spell.

Promotion from weaker to stronger evidence must update the existing runtime entry rather than fan out new entries.

## Source Priority Rules

### Party Personals

Priority order:

1. Self cast
2. Sync from addon user
3. Aura fallback
4. Nothing

Behavior:

- If self or sync exists, it is authoritative.
- Aura fallback may fill gaps but must not overwrite stronger owner-authoritative state unless it is clearly correcting stale state.
- If the system cannot identify a defensive with sufficient rigor, no personal cooldown icon is shown.

### CC Active On Nameplates

Priority order:

1. Live aura state

Behavior:

- If the aura exists and is classified as CC, it is shown.
- When the aura disappears, the nameplate CC display disappears immediately.
- Cooldown continuation belongs to the bar system, not the nameplate surface.

### CC Cooldown Bars

Priority order:

1. Self cast
2. Sync
3. Aura with usable `spellID` and usable caster attribution
4. Unambiguous heuristic correlation
5. Nothing

Behavior:

- The bar starts when the CC is applied, not when the aura ends.
- If the aura remains active, the bar still progresses using cooldown elapsed time.
- If the aura ends early, the bar continues until cooldown completion.
- If a better source arrives later, the entry is promoted in place.
- If only low-confidence ambiguous evidence exists, suppress the bar.

## Confidence Policy

### High Confidence

Use when at least one of these is true:

- Local self cast was observed.
- Sync payload was received from the owner.
- Aura event includes usable identity data sufficient to resolve spell and owner directly.

High-confidence records are allowed to create or replace runtime cooldown state.

### Medium Confidence

Use when:

- The spell can be identified from the aura path, but some attribution detail came from constrained fallback logic.
- The result is still materially unambiguous.

Medium-confidence records may create state when no better source exists.

### Rejected / No Record

Do not create a cooldown record when:

- Multiple plausible owners exist.
- The spell cannot be resolved with enough confidence.
- Secret values block spell or owner identity and there is no supporting sync/cast evidence.

Showing no cooldown is preferable to showing a wrong cooldown.

## Secret-Safe Rules

These rules are mandatory:

- Never store secret values as map keys.
- Never cache secret values as persistent identity.
- Never compare or normalize names, GUIDs, spell IDs, or units without guarding for `issecretvalue`.
- Never assume aura-provided `sourceUnit` is available or valid.
- Never let a secret-blocked path silently fall through to guessed identity unless the correlation policy explicitly allows it.
- Secret failure paths should be explicit and observable in debug output.

### Allowed Degradation

If a secret-restricted aura can still be classified as crowd control:

- Nameplate active CC may still be shown using safe aura state.
- A cooldown bar should only be created if another safe path resolves spell and owner.

If a defensive aura is visibly present but not safely attributable:

- The personal defensive fallback should do nothing.
- Sync remains the intended exact path.

## Detailed CC Flow

1. Aura watcher sees a CC aura applied to a target.
2. Nameplate surface receives active CC state and renders it immediately.
3. Resolver attempts to identify:
   - spell
   - owner
   - cooldown
   - confidence
4. If confidence passes threshold, create or update the owner's CC cooldown bar.
5. While the aura remains active, nameplate state keeps updating from live aura duration.
6. When the aura ends, remove nameplate state only.
7. Keep the cooldown bar alive until cooldown completion.
8. If sync or self evidence arrives after fallback creation, promote the existing cooldown entry in place.

## Detailed Personal Defensive Flow

1. Existing personal defensive tracker keeps publishing self and sync state.
2. Aura fallback watches party units for big defensives and other relevant personal defensive signals.
3. If no authoritative owner state exists for a unit/spell, the fallback attempts to reconstruct cooldown timing.
4. If resolved with enough confidence, inject a fallback runtime defensive cooldown record.
5. If authoritative sync later arrives, replace or promote the existing fallback state in place.
6. The attached icon UI continues to render from the unified defensive runtime model.

## UI Preservation Rules

Visible UI behavior should stay familiar:

- Party personal defensive icons remain attached where they are now.
- CC cooldowns remain bars in the tracker area.
- Active CC on nameplates should follow MiniCC-style visibility but match the addon's existing visual language as much as possible.

Internal rewrites are allowed, but visual regressions are not.

## Migration Strategy

### Phase 1

- Introduce normalized watcher and resolver layers without changing visible UI.
- Feed existing `CrowdControlTracker` and `PartyDefensiveTracker` from the new runtime model.

### Phase 2

- Move CC active display onto nameplates.
- Keep the existing bar UI backed by the new CC cooldown runtime state.

### Phase 3

- Add defensive aura fallback behind sync-primary rules.
- Validate that fallback never degrades authoritative sync behavior.

### Phase 4

- Remove or simplify legacy duplicated detection paths once parity is confirmed.

## Error Handling And Diagnostics

The runtime should expose enough debug information to diagnose missed or suppressed detections:

- Which source created the entry
- Confidence level
- Whether a record was promoted
- Whether a path was suppressed due to secrets
- Whether a path was suppressed due to ambiguity

Debug output should help answer:

- Why did the nameplate show the CC but no cooldown bar appear?
- Why did a fallback defensive show instead of sync?
- Why was a candidate rejected?

## Testing Strategy

### Unit-Level

Test resolution policy in isolation:

- Sync beats aura fallback
- Self beats sync when appropriate
- Medium-confidence aura fallback creates state only when no stronger source exists
- Ambiguous heuristic candidates are rejected
- Promotion updates existing entries instead of duplicating them

### Runtime Slice Tests

Test source and secret handling through focused runtime slices:

- Secret `spellID` blocks cooldown creation
- Secret `sourceUnit` still allows active CC display but suppresses cooldown creation unless another source resolves identity
- Defensive fallback does not override authoritative sync

### Integration-Level

Test current modules against the new runtime shape:

- Party personal icons still render expected cooldowns
- CC bars still sort and expire correctly
- Nameplates show active CC only while aura exists

### In-Game Verification

Verify these cases:

- Full addon group
- Mixed addon and non-addon group
- Secret-restricted target data
- Multiple same-class candidates
- Early-cancelled defensives
- CC with normal expiration
- CC with weak fallback attribution

## Risks

### Main Risk

The biggest risk is creating duplicated or conflicting state when sync, aura fallback, and heuristic paths all report the same event at different times.

Mitigation:

- Central resolver ownership
- Stable runtime identity keys
- Promotion in place rather than append-only state

### Secondary Risk

Blizzard secret restrictions can allow safe classification but block identity details, creating pressure to guess.

Mitigation:

- Explicit no-record outcomes
- Strong sync-primary policy
- Strict confidence thresholds

## Recommendation Summary

The recommended implementation is:

- Keep sync as the primary truth for party personal defensives.
- Add MiniCC-style aura fallback only as a secondary gap-filling source.
- Split active CC and cooldown CC into different runtime concerns.
- Show active CC on nameplates from live aura state.
- Start CC cooldown bars at application time when identity is resolved with enough confidence.
- Treat secret-blocked uncertainty as a reason to suppress cooldown state, not to fabricate it.

This gives the addon better coverage without sacrificing correctness or professionalism.
