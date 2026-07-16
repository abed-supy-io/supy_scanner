# core-libdmtx-ios-bridge

**Status:** open · **Target:** v1.1.0 · **Effort:** M · **Trace:** TODO.md V1-S2-04b

## Problem
Mirror of [core-libdmtx-android-roi](core-libdmtx-android-roi.md) for iOS. Vision detects most DM, but small high-density codes on receipt labels still fall through.

## Scope
- Bridge `supy_core_locate_datamatrix_*` from the C++ core into `ios/Classes/barcode/`.
- Re-run `VNDetectBarcodesRequest` with the ROI as input.
- Reuse the same dedup contract that the Android path uses.

## Out of scope
- Decoding DM payloads in C++ (Vision still produces the payload from the cropped frame).
- Async pipelining beyond a single ROI pass per frame.

## Acceptance
- [ ] DM read rate improvement parity with Android (≥ 25% on the fixtures).
- [ ] Per-frame cost ≤ 8 ms on an iPhone 11 (tier-mid baseline).
- [ ] Camera session start/stop remains on the background queue per CLAUDE.md rule.

## Dependencies
- [core-libdmtx-android-roi](core-libdmtx-android-roi.md) (lands first to validate the dedup contract).

## Source
- `TODO.md` — V1-S2-04b "iOS Swift DM bridge".
