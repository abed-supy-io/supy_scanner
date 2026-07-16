# infra-symbolication-pipeline

**Status:** planned · **Target:** v1.3.0 · **Effort:** M · **Trace:** docs/RELEASE.md follow-up

## Problem
The native C++ core ships as a stripped library. When retailer crash reports surface a native frame, we have nothing to symbolicate against.

## Scope
- Per-release upload of `.so` debug symbols (Android) and dSYM bundles (iOS) to the retailer crash backend (Crashlytics / Sentry — whatever they use).
- Document the upload step in `docs/RELEASE.md`.
- Verify by triggering a canary native crash from a debug build.

## Out of scope
- Choosing the crash backend — retailer already has one.

## Acceptance
- [ ] Release workflow uploads symbols and fails if upload fails.
- [ ] A test crash surfaces a fully-symbolicated stack.

## Dependencies
- `docs/RELEASE.md`.

## Source
- `docs/RELEASE.md` (symbolication note).
