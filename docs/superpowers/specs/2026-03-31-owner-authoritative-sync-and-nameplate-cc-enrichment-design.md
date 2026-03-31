# Owner-Authoritative Sync and Nameplate CC Enrichment Design

**Date:** 2026-03-31

## Goal

Define a safe, cooperative sync model for addon users that can enrich:

- `InterruptTracker`
- `PartyDefensiveTracker`
- `DefensiveRaidTracker`
- `NameplateCrowdControl`

The design must stay within Blizzard's secret-value restrictions. The sender may only publish normalized, non-secret payloads that its own client can legitimately construct. The receiver may render from sync, but may not treat sync as proof of a remote aura target unless local confirmation exists.

## Core Rule

Owner-authoritative sync is valid only when the payload is built from non-secret primitives.

Safe examples:

- canonical `spellID` from addon-owned spell tables
- canonical `spellID` and spell metadata resolved locally from `C_CooldownViewer`
- `GetTime()` timestamps
- cooldown or duration values resolved locally from known spell metadata
- charge counts already normalized into plain numbers
- explicit tracker kind such as `interrupt`, `defensive`, `raid_defensive`, or `cc`

Unsafe examples:

- forwarding raw `AuraData`
- forwarding `LuaDurationObject`
- forwarding `spellId`, `sourceUnit`, `GUID`, or target identity from APIs that returned secret values
- serializing data directly from restricted remote aura or cooldown queries

## Why This Design Exists

Blizzard's generated API docs currently support this split:

- `C_ChatInfo.SendAddonMessage` is usable for addon comms, but its arguments may not be secret values
- `C_UnitAuras.GetUnitAuras` returns `AuraData` with conditional secret contents
- `C_UnitAuras.GetAuraDuration` may still provide a duration object even when the aura identity is not safely readable
- `C_Spell.GetSpellTexture` works if a readable `spellIdentifier` already exists
- `C_CooldownViewer` exposes cooldown catalog and spell metadata, but not the full dynamic runtime state needed for remote target tracking

This means sync is a good transport for owner-known spell identity, while local aura observation remains necessary for target-specific validation on nameplates.

## Scope

### Included

- cooperative sync among players who have the addon
- owner-sent spell identity and timing for tracked modules
- hybrid enrichment of unknown local CC auras on enemy nameplates
- generic CC fallback when a safe spell-specific match cannot be proven

### Excluded

- followers, NPCs, or any non-addon-controlled actor
- direct serialization of secret values
- guessing exact nameplate targets from sync alone when multiple matches are plausible
- replacing local aura detection with remote sync for target-specific CC state

## Module Contract

## CooldownViewer Role

`C_CooldownViewer` should be treated as a safe metadata source for the owner's local client.

Good uses:

- discovering Blizzard-supported cooldown entries
- resolving `spellID`, `overrideSpellID`, `linkedSpellIDs`, and category information
- checking whether a tracked spell uses charges
- building or validating the owner's manifest for interrupts, personals, raid defensives, and curated CC spells

Non-goals:

- reading full dynamic cooldown state for other players
- replacing owner-authoritative cast sync
- replacing local aura confirmation for target-specific nameplate CC

The intended model is:

- `CooldownViewer` provides spell metadata
- owner-local runtime logic decides when a tracked spell was used
- addon comms publish normalized non-secret payloads
- receivers reconstruct UI state from sync plus local confirmation where required

### InterruptTracker

This is a direct owner-authoritative sync case.

The owner sends:

- `spellID`
- `usedAt`
- `cooldown`
- optional `charges` and `maxCharges` if relevant

The owner may resolve `spellID`, charge capability, and override metadata from `C_CooldownViewer` before constructing the payload.

The receiver renders the cooldown directly from sync.

No local target confirmation is required.

### PartyDefensiveTracker

This is also a direct owner-authoritative sync case.

The owner sends:

- `spellID`
- `usedAt`
- `cooldown`
- optional `charges` and `maxCharges`

The owner may use `C_CooldownViewer` to resolve metadata for supported spells before sending manifest or cast state.

The receiver renders the cooldown directly from sync.

### DefensiveRaidTracker

Same transport model as party defensives, but kept in its own message bucket and UI lane.

The owner sends:

- `spellID`
- `usedAt`
- `cooldown`
- optional `charges` and `maxCharges`
- optional `kind` flag for raid-wide ordering or presentation

The owner may use `C_CooldownViewer` metadata to normalize spell identity and charges support before sync.

### NameplateCrowdControl

This is a hybrid case.

The owner sends:

- `spellID`
- `appliedAt`
- `expectedDuration`
- optional non-secret destination hint if one exists and is proven readable

The receiver continues to discover active CC locally from `UNIT_AURA` and `GetAuraDuration`.

If a local aura is classified as crowd control but lacks a safe spell identity, it enters the runtime as `CC_UNKNOWN`. A correlator then tries to promote it using recent sync events.

If the correlator finds exactly one plausible sync candidate, the aura can borrow:

- `spellID`
- `GetSpellTexture(spellID)`
- display name if safely available from spell info

The timer remains local to the aura slot when possible.

If the correlator does not find a unique plausible match, the slot stays generic.

## Nameplate Matching Rules

### Matching objective

Use sync only to enrich a local unknown aura. Never use sync alone to assert exact target state on a nameplate.

### Required conditions for promotion

An unknown aura may be promoted from generic to spell-specific only if all of the following are true:

- the aura is active on a local visible nameplate
- the sync event is recent enough to fit a narrow time window
- the sync spell belongs to the tracked CC set
- no second sync candidate is equally plausible for the same aura

### Preferred tie-breakers

Use these only when the values are non-secret and locally available:

- destination hint
- emitter identity
- compatible expected duration
- cast-to-aura application timing

### Hide and fallback behavior

If matching is ambiguous:

- do not guess a spell-specific icon
- keep the generic CC icon
- keep the local aura timer only if the aura itself is still visible locally

If no local aura exists:

- do not render target-specific nameplate CC from sync alone

## Transport Shape

Each message should contain only normalized primitives.

Recommended shared fields:

- `msgType`
- `spellID`
- `sentAt`
- `usedAt` or `appliedAt`
- `cooldown` or `expectedDuration`
- `charges`
- `maxCharges`
- `sourceUnitToken` only if it is local-owner self context and not used as cross-client identity
- optional destination hint only if proven non-secret

The transport should never contain raw objects or values whose readability depends on the receiver repeating a restricted API query.

## Security Boundary

The sender is allowed to say:

- "I used spell 2139 now"
- "My cooldown for spell 2139 is 24 seconds"
- "I applied tracked CC spell 207167 now"

The sender is not allowed to say:

- "Here is the aura object Blizzard gave me"
- "Here is a secret GUID or secret spellId I got from another unit"
- "Here is a duration object or opaque value from a restricted query"

This keeps sync on the side of local facts, not forwarded restricted state.

## Testing Strategy

### Probe requirements

Before implementation is treated as safe, probe exact source APIs per module:

- where each emitted `spellID` comes from
- whether `C_CooldownViewer` coverage is sufficient for the spell families we want to sync
- whether each candidate field can ever become secret
- whether the payload can be built without touching restricted values

### Manual cases

- two-addon-user party: interrupt usage sync
- two-addon-user party: personal defensive usage sync
- two-addon-user party: raid defensive usage sync
- two-addon-user party: visible CC on one enemy nameplate with unique sync match
- multi-CC pull with ambiguous matches to confirm generic fallback
- follower dungeon run to confirm follower/NPC events never claim cooperative certainty

### Success criteria

- cooldown trackers can render owner-authoritative state without guessing
- `CooldownViewer` is used only as owner-local metadata, not as remote runtime truth
- nameplate CC can replace generic icons with spell-specific icons only on unique local matches
- no message construction depends on secret values
- no target-specific state is shown from sync alone when the local client cannot confirm an aura

## Risks

- nameplate correlation may intentionally leave many cases generic
- destination hints may not be consistently available as non-secret values
- ambiguous multi-CC pulls will reduce spell-specific enrichment
- transport safety depends on disciplined payload construction in every module

## Recommendation

Implement one shared owner-authoritative sync contract for cooldown-style trackers and treat `NameplateCrowdControl` as a hybrid consumer:

- sync supplies safe spell identity
- local aura state supplies target-local presence and timer
- generic fallback remains the default when proof is incomplete
