# core-cxd-auto-snap

**Status:** landed (Unreleased, 2026-06) · **Target:** v1.2.x · **Effort:** M · **Trace:** PLAN.md Phase CXD (deferred sub)

## Problem
The GMS document scanner snaps automatically when the document is steady and in frame. The CameraX fallback ships without auto-snap in v1.2 — users have to tap. The C++ guidance state machine ported in c4e4650 already has the inputs needed (corners + steadiness + glare).

## Scope
- Reuse the document guidance state machine from `native/` to drive auto-snap.
- Add a tier-aware steadiness window (longer for tier-low).
- Manual-tap path stays as a fallback the user can force.

## Out of scope
- Editing the guidance state machine itself. Treat the C++ contract as a black box.

## Acceptance
- [ ] Auto-snap fires within 1.5 s of a steady, framed document on tier-mid.
- [ ] No spurious snaps when hand-held > 8° tilt.
- [ ] User can disable auto-snap via existing scan options without breaking compat.

## Dependencies
- [core-cxd-camerax-activity](core-cxd-camerax-activity.md).

## Source
- `docs/PLAN.md` — Phase CXD follow-up.
- commit c4e4650 (guidance state machine port).
