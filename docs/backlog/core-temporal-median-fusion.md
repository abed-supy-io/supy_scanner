# core-temporal-median-fusion

**Status:** open · **Target:** v1.1.0 · **Effort:** M · **Trace:** TODO.md V1-S2-06

## Problem
Hand-held scans produce micro-jitter ROIs whose individual frames decode unreliably. Fusing three consecutive ROI frames with a temporal-median should lift the read rate without raising per-frame cost.

## Scope
- Add a 3-frame circular buffer keyed by ROI center + size with tolerance ε.
- Compute per-pixel median on luma plane; feed median frame to decoder.
- Bypass fusion when `SupyIdleDetector` reports motion above threshold.

## Out of scope
- N>3 fusion (deferred until benchmarks justify the working-set cost).
- Color fusion — luma-only is sufficient for decode.

## Acceptance
- [ ] Read rate on the shaky-hand fixture improves ≥ 10%.
- [ ] Working-set growth ≤ 2 MB on tier-mid.
- [ ] Falls back to single-frame decode within 1 frame of motion detection.

## Dependencies
- `IdleDetector` (already shipped) + ROI plumbing from [core-libdmtx-android-roi](core-libdmtx-android-roi.md).

## Source
- `TODO.md` — V1-S2-06 "3-frame temporal-median ROI fusion".
