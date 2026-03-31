# Tracking And Settings Consolidation Design

## Goal

Upgrade SunderingTools so interrupts, crowd control, party defensives, and raid-style defensives are more reliable under modern Blizzard secret-value restrictions while the addon surface becomes simpler, cleaner, and more consistent for a Mythic+ and world-play user.

This design combines:

- the existing party CC and defensive tracking work
- a global cleanup of obsolete or duplicated settings
- functional borrowing from local reference addons

## Product Direction

### Supported play contexts

The addon is optimized for:

- `Dungeon`
- `World`

`Raid` and `Arena` remain implementation concepts only where technically useful, but they are removed from the visible settings model and should no longer drive user-facing configuration.

### Tracker roles

- `InterruptTracker` remains a dedicated cooldown bar tracker.
- `CrowdControlTracker` remains a dedicated cooldown bar tracker.
- `NameplateCrowdControl` becomes a secondary live-state layer that shows active CC while the aura exists.
- `PartyDefensiveTracker` remains an attached-icon tracker in the style of MiniCC.
- `DefensiveRaidTracker` remains a separate bar-based tracker because its presentation is materially different from attached icons, even when some tracked spells are useful in party play.

### Configuration philosophy

Settings should be aggressively simplified:

- Keep settings that affect layout, sizing, readability, preview, or clearly meaningful behavior.
- Remove stale compatibility toggles and weakly justified expert flags.
- Replace manual `sync` and `strict sync` controls with internal automatic policy.
- Share one bar-settings structure between `InterruptTracker` and `CrowdControlTracker` while keeping the modules distinct.
- Give `NameplateCrowdControl` its own settings and preview because it is a separate visual layer.
- Keep `Debug Mode` visible, but treat it as diagnostics only, not as a user-facing behavior control.

No legacy dead settings should remain in runtime or migration code unless they are needed to preserve saved-variable loading during one explicit migration pass.

## Reference Addons And What To Borrow

### Kryos

Use Kryos as a reference for:

- timestamp correlation when party spell identity is hidden
- practical cooldown-bar UX for interrupts and CC
- low-friction fallback behavior when perfect attribution is impossible

### LoxxInterruptTracker

Use Loxx as a reference for:

- robust interrupt and CC correlation logic under Blizzard 12.x restrictions
- class-primary fallback ownership heuristics
- pragmatic handling of ambiguity and confidence

If Loxx logic is better than current SunderingTools logic for interrupt or CC attribution, copy the logic into SunderingTools and adapt it to the existing UI rather than preserving inferior local behavior.

### MiniCC

Use MiniCC as a reference for:

- aura classification using Blizzard filter APIs
- attached-icon defensive presentation
- handling of secret/opaque aura data through typed filters and instance-based predicates

Parity target:

- Party defensive attached icons should be functionally comparable to MiniCC where technically possible.
- CC nameplate live-state handling should also follow MiniCC’s discipline around aura filters and secret-safe classification.

### OmniCD

Use OmniCD as a reference for:

- runtime/state separation
- cooldown ownership and fallback rigor
- generally proven addon patterns where SunderingTools has weaker internals

## Technical Strategy

### Runtime decomposition

Introduce dedicated watcher and resolver layers so modules stop embedding Blizzard API edge-case handling directly inside UI code.

Key runtime units:

- `PartyCrowdControlAuraWatcher`
  - normalizes live aura snapshots into apply/update/remove events
  - accepts external classification functions so Blizzard filter workarounds can be used without hard-coding policy into the watcher
  - redacts secret identity values before emission
- `PartyCrowdControlResolver`
  - converts watcher/correlation observations into cooldown entries with source and confidence
- `PartyDefensiveAuraFallback`
  - derives defensive cooldown state from aura removal when sync is absent or late

### Crowd control behavior

Crowd control has two parallel outputs:

1. active CC on nameplates while the aura exists
2. cooldown bars starting at application time when attribution is reliable enough

Reliability strategy:

- Prefer direct aura attribution when Blizzard exposes enough information.
- Under restrictions, use filter-based classification and instance-based checks first.
- Fall back to timestamp correlation using class-primary CC only when direct identification is impossible.
- Preserve source/confidence so lower-certainty paths do not silently masquerade as perfect attribution.

### Defensive behavior

Party defensives are sync-primary, but not sync-only.

Policy:

- Sync is authoritative when present and timely.
- Aura-based fallback fills holes when sync is missing.
- Party attached icons should never regress in usability because another addon user is absent.

Raid-style defensive bars remain separate, but their spell ownership and context policy should use the same cleaned-up internal runtime rules where possible.

### Automatic sync policy

Visible `syncEnabled` and `strictSyncMode` toggles are removed from tracker settings.

Internal behavior becomes:

- use sync whenever the tracker/module has a trustworthy sync path
- prefer sync over fallback when both exist
- suppress uncertain remote state when confidence is below the module’s threshold
- allow fallback where Blizzard API evidence is strong enough to improve UX without fabricating certainty

This keeps rigor high without asking the user to understand transport policy.

## Settings Consolidation

### What stays

- enable/disable per module
- edit mode / preview controls
- position, dimensions, font sizes, icon sizes, spacing, row/column layout
- `Dungeon` and `World` visibility
- `showReady`, tooltip, hide-out-of-combat, and other clearly user-meaningful display toggles where they still affect real behavior
- nameplate-specific settings and preview
- debug mode

### What goes

- visible `Raid` and `Arena` context toggles
- visible sync/strict-sync toggles
- stale or duplicated controls that no longer map to distinct behavior
- module-specific bar-structure settings duplicated across interrupt and CC if they can be expressed by one shared settings schema

### Shared bar settings

`InterruptTracker` and `CrowdControlTracker` should use one common settings model for:

- header visibility
- width / bar height
- font sizes
- show ready
- hide out of combat
- tooltip behavior
- `Dungeon` / `World` visibility
- growth / ordering where both trackers support the same concept

The modules stay separate, but the settings code path should stop forking into two near-identical implementations.

## Constraints

### Hard constraints

- Internal logic may be rewritten or deleted aggressively.
- Visible tracker presentation patterns must stay recognizable.
- Configuration UI should become simpler, not more cluttered.
- Any improvement must stay technically honest under Blizzard restrictions.

### API honesty

If Blizzard does not expose enough data to support a reliable behavior and there is no real workaround through typed aura filters, instance checks, combat log events, or safe correlation, the addon should degrade gracefully instead of pretending certainty.

## Testing Strategy

Testing must cover both behavior and packaging/runtime wiring.

Required coverage themes:

- secret-safe watcher behavior
- resolver confidence and cooldown derivation
- nameplate CC module loading and watcher integration
- CC tracker resolver-backed cooldown starts
- defensive aura fallback acceptance rules
- settings/runtime-slice assertions for removed or added controls
- focused regressions for interrupt, hybrid, and defensive trackers

## Expected Outcome

After implementation:

- interrupts use stronger logic borrowed from the best local reference where appropriate
- CC bars and active nameplates work together cleanly
- party defensives behave much closer to MiniCC attached-icon expectations
- raid-style defensive bars remain distinct but cleaner internally
- settings are materially smaller, easier to understand, and aligned with real use in Mythic+ and world content
