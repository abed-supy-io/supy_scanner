# core-csu-ios-avcapture

**Status:** planned · **Target:** v1.3.0 · **Effort:** L · **Trace:** PLAN.md Phase CSU1

## Problem
Today the iOS document scanner is `VNDocumentCameraViewController`, a black-box VisionKit UI. UX parity with Scanbot's branded scanner needs an owned capture surface. PLAN.md Phase CSU starts here.

## Scope
- New `AVCaptureSession`-based scanner under `ios/Classes/document/csu/`.
- Reuse the C++ guidance state machine for corners/steadiness.
- Camera session start/stop on a background queue (CLAUDE.md rule).
- Identical `SupyDocumentPage` output shape.

## Out of scope
- Branding/theming UI — that comes via `UI_CONFIGURATION.md` follow-ups.
- Replacing `VNDocumentCameraViewController` until parity tests pass — see [core-csu-result-parity](core-csu-result-parity.md).

## Acceptance
- [ ] CSU path opt-in via `useCustomScannerUi: true`; legacy path is default until parity verified.
- [ ] No main-thread blocking; iOS 16 deployment target respected.
- [ ] Multi-page capture works end-to-end on iPhone SE 3.

## Dependencies
- Native guidance state machine (already shipped in c4e4650).

## Source
- `docs/PLAN.md` — Phase CSU1.
