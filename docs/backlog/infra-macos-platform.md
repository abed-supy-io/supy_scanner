# infra-macos-platform

**Status:** planned · **Target:** v2.0.0 · **Effort:** L · **Trace:** PLAN.md non-goal → v2 candidate

## Problem
macOS is not a v1 target. As retailer back-office tools move to Flutter desktop, a macOS barcode/document scanner using AVFoundation + Vision becomes the natural next platform — most of the iOS code is reusable.

## Scope
- Add a `macos/` plugin target sharing `SupyScanner` Swift module.
- Camera permission flow per macOS sandboxing (`com.apple.security.device.camera` entitlement docs).
- Document scanner uses Vision-only path (no VisionKit on macOS).

## Out of scope
- Touch-style review UI; keep behavior identical and let consumers re-skin.
- File-import scanning (separate epic).

## Acceptance
- [ ] `flutter run -d macos` in the example app opens a working scanner.
- [ ] Reuses ≥ 70% of `ios/Classes/` code.

## Dependencies
- [core-csu-ios-avcapture](core-csu-ios-avcapture.md) (shared capture pipeline).

## Source
- `docs/PLAN.md` non-goals list (v1 scope explicitly mobile-only).
