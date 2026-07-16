# core-zxing-ios-bridge

**Status:** open · **Target:** v1.1.0 · **Effort:** M · **Trace:** TODO.md V1-S2-03b

## Problem
zxing-cpp is vendored under `native/barcode/` and the Android JNI already calls `supy_core_decode*`. iOS is still routing all barcode reads through `VNDetectBarcodesRequest`, so iOS does not benefit from the C++ multi-symbol pass that Android gets.

## Scope
- Add Swift/ObjC++ shim in `ios/Classes/barcode/` that forwards frame buffers to `supy_core_decode_yuv` / `supy_core_decode_gray` from `SupyNativeCoreBridge`.
- Plumb mode select (Vision-only / native-only / fused) into `SupyBarcodeScannerView` view options without breaking compat keys.
- Reuse the deduplication and confidence logic that the Android side already uses.

## Out of scope
- Adding a new wire format. Mode select must reuse the existing options dict.
- Replacing Vision; it stays as the default path until perf-gate proves the native path wins.

## Acceptance
- [ ] iOS reads QR + Code128 fixtures through the native decoder when mode=`native`.
- [ ] Fused mode emits each barcode at most once per frame (dedup by `(format, value, ROI hash)`).
- [ ] No leak of `CVPixelBufferRef`; instruments shows no growth across 5-min soak.
- [ ] Perf-gate (see `core-perf-gate-harness`) shows ≤ Vision baseline for QR p50/p95.

## Dependencies
- Native core ABI version already pinned in `native/include/supy_scanner_core.h`.
- `core-perf-gate-harness` to gate the rollout.

## Source
- `TODO.md` — V1-S2-03b "iOS Swift bridge to supy_core_decode".
- `docs/ARCHITECTURE.md` — native core C ABI table.
