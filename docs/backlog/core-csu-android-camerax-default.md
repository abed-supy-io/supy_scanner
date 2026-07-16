# core-csu-android-camerax-default

**Status:** planned · **Target:** v1.3.0 · **Effort:** M · **Trace:** PLAN.md Phase CSU2

## Problem
Android already has a CameraX path on the fallback side (Phase CXD). For Phase CSU, the CameraX activity becomes the default capture UI, with GMS demoted to opt-in.

## Scope
- Promote `CameraXDocumentScannerActivity` to the default path when `useCustomScannerUi: true`.
- Keep GMS reachable for hosts that prefer it via a backend selector.
- Share the guidance state machine wire with iOS so behavior matches.

## Out of scope
- Changing the public Dart options (compat-preserving).

## Acceptance
- [ ] CSU-default Android flow matches the GMS flow on the QA matrix scenarios (`docs/QA.md`).
- [ ] No regression in the existing CXD ROI / auto-snap behavior.

## Dependencies
- [core-cxd-camerax-activity](core-cxd-camerax-activity.md), [core-cxd-auto-snap](core-cxd-auto-snap.md).

## Source
- `docs/PLAN.md` — Phase CSU2.
