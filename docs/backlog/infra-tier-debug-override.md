# infra-tier-debug-override

**Status:** planned · **Target:** v1.1.x · **Effort:** S · **Trace:** PLAN.md §7 Post-v1.2 candidate

## Problem
`SupyDeviceTier` is derived at runtime. We can't reproduce tier-low bugs on a tier-high CI device. PLAN.md §7 lists `debugForceTier` as a candidate.

## Scope
- Add `SupyScanner.debugForceTier(SupyDeviceTier?)` — `null` clears the override.
- Plumb to both platforms; honored only in debug builds, ignored in release.
- Surface in the example app's debug menu.

## Out of scope
- Override of thermal state (separate, more invasive).

## Acceptance
- [ ] Setting tier in debug forces all governor / downscale decisions to match.
- [ ] Release builds ignore the call (compile-time strip).
- [ ] Used by at least one CI perfgate run per tier.

## Dependencies
- Existing `SupyDeviceTier` plumbing.

## Source
- `docs/PLAN.md` §7 Post-v1.2 candidates.
