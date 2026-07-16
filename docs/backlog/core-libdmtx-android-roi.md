# core-libdmtx-android-roi

**Status:** open · **Target:** v1.1.0 · **Effort:** M · **Trace:** TODO.md V1-S2-04a.2

## Problem
libdmtx (`SUPY_WITH_LIBDMTX`) is vendored and `supy_core_locate_datamatrix*` is exported, but Android still hands ML Kit the full frame for DataMatrix. Small DM codes on packaging are missed at retail scanning distance.

## Scope
- Call `supy_core_locate_datamatrix_yuv` to produce ROI candidates, then re-run ML Kit Barcode on each cropped tile.
- Confidence-merge with full-frame results to avoid duplicates.
- Respect `SupyThermalGovernor` — skip the ROI pass under throttle.

## Out of scope
- Reading DM directly from libdmtx (kept for a follow-up; ML Kit still decodes the cropped ROI for v1.1).
- Tuning DM-specific quiet-zone thresholds (those live in `native/barcode/libdmtx/`).

## Acceptance
- [ ] DM read rate on the existing fixture set improves ≥ 25% vs. full-frame baseline.
- [ ] Per-frame cost ≤ 8 ms on a tier-mid device (Pixel 6a).
- [ ] No DM duplicates when the same code is found by both passes.

## Dependencies
- Native ABI version `SUPY_CORE_ABI_VERSION` already exposes the locate API.
- `infra-tier-debug-override` to repro on a fixed tier in CI.

## Source
- `TODO.md` — V1-S2-04a.2 "Android DM ROI assist".
