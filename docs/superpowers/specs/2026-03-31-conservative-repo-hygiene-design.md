# Conservative Repo Hygiene Design

**Date:** 2026-03-31

## Goal

Clean the repository with a conservative, behavior-preserving pass that removes verifiable dead code, redundant compatibility scaffolding, low-value test duplication, and trivial repetition without changing architecture or product behavior.

## Scope

### Included

- remove dead or unreachable code paths that are no longer exercised
- remove obsolete migration/normalization leftovers once they are proven redundant
- consolidate trivial duplicated helpers when the extraction is mechanical and low-risk
- tighten tests so they verify meaningful behavior rather than stale textual details
- align lightweight docs/specs/plans with the current shipped state where clearly necessary

### Excluded

- file splitting for style alone
- architectural rewrites
- tracker behavior changes
- sync protocol redesign
- performance work unless it naturally falls out of dead-code removal

## Hygiene Rules

### Rule 1: Behavior wins over neatness

No cleanup is allowed if it changes visible behavior without a dedicated reason and regression coverage.

### Rule 2: Delete only what is proven irrelevant

A code path may be removed only if one of these is true:

- it is unreachable from current entrypoints
- it is neutralized immediately on load and never used afterward
- it duplicates a helper whose replacement is already equivalent and tested
- it exists only to satisfy an outdated textual test

### Rule 3: Tests should become less brittle, not less strict

If a test currently checks exact strings for implementation detail rather than behavior, prefer replacing that assertion with a stronger, less brittle one.

### Rule 4: Ignore unrelated user work

The repo currently contains unrelated modified and untracked files. Hygiene work must stay scoped and must not revert or absorb unrelated changes.

## Expected Cleanup Targets

### Legacy normalization leftovers

`PartyDefensiveTracker.lua` still zeroes out legacy settings like `syncEnabled` and `strictSyncMode`.

The hygiene pass should verify:

- whether those keys are still needed for migration in active code
- whether tests still rely on them
- whether the behavior can be simplified without changing saved-variable compatibility

If compatibility is still required, keep the behavior and only simplify code shape if safe.

### Repeated naming helpers

Multiple modules define local copies of `ShortName` and `NormalizeName`.

The hygiene pass may consolidate these only if:

- the implementations are identical or trivially compatible
- extraction does not create a sprawling shared-utility dependency
- tests can verify the shared behavior without adding indirection noise

If not, leave them duplicated.

### Repeated spell texture helpers

Multiple trackers implement nearly identical `GetCachedSpellTexture` helpers.

The hygiene pass may consolidate these only if:

- the calling pattern remains simple
- cache ownership stays clear
- the change does not force unrelated modules into a common runtime coupling

Otherwise, do not unify them just for aesthetics.

### Runtime-slice textual duplication

Several Python runtime slices assert the presence of exact helper names or string literals.

The hygiene pass should prefer:

- assertions on exported wiring or behavior-critical tokens
- minimal text assertions that survive harmless refactors

This includes new tests added during recent sync work.

### Orphaned or low-signal docs artifacts

There are untracked docs files in the workspace. Hygiene should only touch docs that are:

- part of the current cleanup work
- clearly stale relative to shipped code

Do not auto-delete user drafts just because they are untracked.

## Implementation Strategy

### Pass 1: Inventory and classify

Build a short list of candidate cleanup sites with one of these labels:

- dead
- redundant
- brittle-test
- leave-alone

Anything that is not clearly in the first three buckets stays untouched.

### Pass 2: TDD per cleanup cluster

For each cleanup cluster:

- add or adjust the smallest test needed
- verify the current code fails or the old brittle assertion is superseded
- make the smallest cleanup change
- rerun targeted tests

### Pass 3: Full-repo verification

After all cleanup clusters:

- run the full Python suite
- run the Lua harness path already used by the repo
- review diff for accidental style churn

## Recommended Targets for This Pass

### Target A: test hygiene

Reduce brittle text assertions introduced by implementation details, especially where exact helper names are asserted instead of runtime wiring.

### Target B: tracker utility cleanup

Simplify trivial duplicated normalization helpers only where extraction is local and obviously safe.

### Target C: legacy normalization review

Review legacy saved-variable cleanup in defensive trackers and either:

- keep with clearer intent, or
- delete only if proven unnecessary

### Target D: dead local scaffolding

Remove variables, branches, or helper code that no longer feed any active path after recent sync/nameplate changes.

## Risks

- “cleanup” can easily drift into behavior changes if not tightly scoped
- textual runtime tests may fail in ways that tempt reintroducing needless code
- utility consolidation can make modules less clear if done too aggressively

## Success Criteria

- the repository is simpler in areas with proven redundancy
- no unrelated user changes are touched
- no tracker behavior changes without explicit regression coverage
- full verification remains green
- the diff reads as maintenance, not redesign
