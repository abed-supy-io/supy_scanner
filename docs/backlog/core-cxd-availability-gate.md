# core-cxd-availability-gate

**Status:** landed (Unreleased, 2026-06) · **Target:** v1.2.0 · **Effort:** S · **Trace:** PLAN.md Phase CXD1

## Problem
`MlKitDocumentScanner` requires GMS. Non-GMS devices (Huawei post-ban, some Pixel-equivalents in emerging markets) fall back to camera-only with no recovery path. Phase CXD lays out a CameraX fallback; first step is the availability gate.

## Scope
- Add a runtime probe behind `requestCameraPermission` / `nativeCoreProbe` that reports GMS availability + DocumentScanner module version.
- Surface as `SupyDocumentScannerBackend.gms | .cameraX` on the Dart side.
- Default to GMS where available, CameraX otherwise; expose `preferredBackend` for tests.

## Out of scope
- Building the CameraX activity — see [core-cxd-camerax-activity](core-cxd-camerax-activity.md).

## Acceptance
- [ ] Emulator without GMS reports `cameraX` and does not crash on `scanDocument`.
- [ ] Dart consumers can read the resolved backend in the result payload.
- [ ] No new channel method added without a row in `docs/ARCHITECTURE.md` table.

## Dependencies
- Existing GMS detection helper in Android nativecore.

## Source
- `docs/PLAN.md` — Phase CXD1.
- `docs/CAMERAX_FALLBACK.md`.
