# core-csu-options-plumbing

**Status:** planned · **Target:** v1.3.0 · **Effort:** S · **Trace:** PLAN.md Phase CSU4

## Problem
Custom scanner UI needs Dart-side options that map cleanly to both backends without breaking the Scanbot-compat API surface. PLAN.md CSU4 calls for explicit option plumbing rather than ad-hoc props.

## Scope
- Extend `SupyScanOptions` with a sealed `SupyCustomUiOptions` sub-config (gated by `useCustomScannerUi`).
- Mirror keys 1:1 in the channel arg table (`docs/ARCHITECTURE.md`).
- Compat shim translates legacy Scanbot prop names to the new options where they overlap.

## Out of scope
- New theming primitives — see `docs/UI_CONFIGURATION.md` follow-ups.

## Acceptance
- [ ] All option keys typed; no `Map<String,dynamic>` leaks out of `lib/src/channel/`.
- [ ] `compat/` package still compiles with no required-arg break.
- [ ] Channel arg table updated in the same PR.

## Dependencies
- [core-csu-classifier-plumbing](core-csu-classifier-plumbing.md).

## Source
- `docs/PLAN.md` — Phase CSU4.
- `CLAUDE.md` Dart conventions.
