# infra-device-runner-matrix

**Status:** planned · **Target:** v1.3.0 · **Effort:** L · **Trace:** TODO.md H4-05 follow-up

## Problem
Today CI uses an Android emulator and an iOS simulator. Thermal / tier behavior is invisible on those. H4-05 canary jobs check stable + JDK21 but not real silicon.

## Scope
- Wire one real device per tier into CI (Firebase Test Lab for Android, BrowserStack or in-house rack for iOS).
- Run only the perfgate + reliability suites — not the full unit set — to keep cost bounded.
- Failure on a device-runner job is a warning, not a block, until baselines stabilize.

## Out of scope
- A full device fleet — pick one tier-low, one tier-mid, one tier-high device.

## Acceptance
- [ ] At least one real-device run per OS per nightly.
- [ ] Per-device baselines committed.
- [ ] Cost ≤ documented monthly budget (decide with infra).

## Dependencies
- [core-perf-gate-harness](core-perf-gate-harness.md).

## Source
- `TODO.md` — H4-05 canary follow-up.
