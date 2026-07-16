# core-cxd-camerax-activity

**Status:** landed (Unreleased, 2026-06) · **Target:** v1.2.0 · **Effort:** L · **Trace:** PLAN.md Phase CXD2–CXD4

## Problem
The CameraX document fallback needs a working capture activity that produces the same `SupyDocumentPage` payload the GMS path produces. The existing `CameraXDocumentScannerActivity` is a stub.

## Scope
- Bind `LifecycleCameraController` to the host `Activity` lifecycle (CLAUDE.md rule — no `FragmentActivity` cast).
- Wire edge detection from `supy_core_locate_*` (corners only — no auto-snap yet).
- Re-encode pages through `PageReencoder` so the JPEG/PDF output matches the GMS path byte-for-byte at the format level.

## Out of scope
- Auto-snap — see [core-cxd-auto-snap](core-cxd-auto-snap.md).
- New result fields. The output shape stays identical to the GMS payload.

## Acceptance
- [ ] Capture → review → confirm flow returns at least one `SupyDocumentPage` on a no-GMS emulator.
- [ ] Output PDF passes `pdftotext` smoke check on a printed-text fixture.
- [ ] No main-thread frames > 16 ms during capture (Systrace).

## Dependencies
- [core-cxd-availability-gate](core-cxd-availability-gate.md).

## Source
- `docs/PLAN.md` — Phase CXD2–CXD4.
- `docs/CAMERAX_FALLBACK.md`.
