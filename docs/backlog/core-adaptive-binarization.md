# core-adaptive-binarization

**Status:** open · **Target:** v1.1.0 · **Effort:** L · **Trace:** TODO.md V1-S2-05

## Problem
Native barcode decode currently uses a uniform global threshold. Low-light and shadowed scenes (cold-room labels, partially-lit shelves) degrade 1D scan rates more than they should.

## Scope
- Implement Wolf-Jolion adaptive threshold for 1D bands and Sauvola for 2D regions in `native/barcode/`.
- Wire as a pre-decode pass behind `SupyDeviceTier` so tier-low skips it.
- Expose a build switch (`SUPY_BIN_WJ`, `SUPY_BIN_SAUVOLA`) so the legacy global path stays available for A/B.

## Out of scope
- Halide AOT for the kernel — see [infra-halide-aot-kernels](infra-halide-aot-kernels.md).
- Tuning for 2D PDF417 (deferred to a separate ticket if needed).

## Acceptance
- [ ] 1D read rate on low-light fixtures improves ≥ 15% vs. global threshold.
- [ ] Tier-mid per-frame cost ≤ 6 ms; tier-low path stays disabled.
- [ ] No regression on the existing high-contrast fixtures (≤ 1% delta).

## Dependencies
- [core-perf-gate-harness](core-perf-gate-harness.md) to enforce the cost budget in CI.

## Source
- `TODO.md` — V1-S2-05 "Wolf-Jolion / Sauvola binarization".
