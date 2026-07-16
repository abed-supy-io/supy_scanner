# infra-web-platform-wasm

**Status:** planned · **Target:** v2.0.0 · **Effort:** XL · **Trace:** PLAN.md non-goal → v2 candidate

## Problem
Retailer back-office and partner portals could benefit from a browser-based scanner. zxing-cpp compiles to WASM; this is a viable, on-device, no-cloud path that matches the CLAUDE.md "no cloud OCR" rule.

## Scope
- Add a `web/` plugin target with a `MediaStream`-based capture surface.
- Compile the C++ core (zxing-cpp subset) to WASM and bind via JS interop.
- Document feature gap vs. mobile (no DM ROI assist v1, OCR via Tesseract.js as a follow-up).

## Out of scope
- Document scanning v1 (barcode-only for initial web release).
- Tesseract.js OCR — separate ticket if needed.

## Acceptance
- [ ] `flutter run -d chrome` reads QR + Code128.
- [ ] No network call in the scan path.

## Dependencies
- Native core split that isolates the platform-portable subset.

## Source
- `docs/PLAN.md` non-goals list.
