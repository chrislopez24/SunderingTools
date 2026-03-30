# Defensive Tracker Design

**Date:** 2026-03-30

## Goal

Add OmniCD-style defensive tracking for party members in two surfaces:

- attached icons on each Blizzard party frame for party-member defensives
- a separate raid-defensive tracker using the existing tracker pattern

The design must respect Blizzard 12.0 secret restrictions and prefer owner-authoritative sync over remote cooldown inference.

## Scope

### Included

- personal defensives
- external defensives
- tank defensives
- raid defensives
- party-frame attachment for the owner of the cooldown
- sync-first cooldown state propagation when addon users are grouped
- aura-assisted active-state confirmation where Blizzard exposes visible auras

### Excluded from v1

- exact cooldown inference for non-addon party members beyond simple heuristic fallback
- target-frame duplication for external defensives
- proc/passive cheat-death style defensives as exact cooldowns unless the owner syncs them

## Architecture

### Spell catalog

SunderingTools will extend `Core/CombatTrackSpellDB.lua` with a defensive catalog seeded from OmniCD Mainline spell data. The local catalog will only include the defensives needed for retail party play and will flatten OmniCD metadata into runtime-friendly buckets:

- `DEF`
- `RAID_DEF`

Each entry will carry enough metadata for UI and tracking:

- spell id
- cooldown
- aura spell id when useful
- class token
- group bucket
- tracking hints such as `charges`, `auraOnly`, `syncOnly`, `showOnPartyFrame`

### Tracking model

Tracking uses three confidence levels:

- `self` and `sync`: exact
- `correlated`: active or confirmed from visible aura
- `auto`: estimated from public casts only

The shared combat engine remains the source of truth for tracked entries. Defensive tracking extends it rather than replacing it.

### Sync model

Each client is authoritative for its own defensives. It broadcasts:

- manifest of tracked spells
- usage
- current state
- resets or charge-affecting transitions

This avoids depending on restricted third-party cooldown APIs while still allowing OmniCD-like fidelity for groups running the addon.

### UI model

Party-frame icons are attached to the Blizzard party frame that belongs to the owner of the cooldown. The frame should communicate:

- ready
- on cooldown
- active
- estimated versus synced confidence if needed internally

Raid defensives stay in a standalone tracker module instead of being attached to a party frame.

## API stance

The implementation deliberately avoids relying on:

- exact third-party `C_Spell.GetSpellCooldown`
- exact third-party `C_Spell.GetSpellCharges`
- `UNIT_SPELLCAST_SUCCEEDED` as the sole authoritative remote signal

The implementation does rely on:

- local self cooldown APIs
- addon comms
- visible auras via `UNIT_AURA`
- Blizzard's defensive classification helpers where useful

## Success criteria

- A party member with the addon broadcasts their defensives and peers see owner-attached cooldown icons update.
- Raid defensives appear in a standalone tracker with the same sync-first logic.
- Existing interrupt and crowd-control trackers continue to work unchanged.
- The codebase keeps the current modular pattern: spell DB, model, module, shared engine, shared sync.
