# dx-sprint8-migration-cookbook

**Status:** decision-gated · **Target:** v1.3.0 · **Effort:** S · **Trace:** TODO.md V1-S8-DECISION

## Problem
If V1-S8-DECISION resolves to "build owned" (multi-page review sheet), retailer needs an upgrade cookbook documenting what changes for them and what stays the same.

## Scope
- Add a `docs/MIGRATION.md` section: "Adopting the owned multi-page review (v1.3)".
- Before/after snippets for the most common retailer call patterns.
- A one-line opt-in flag for staged rollout.

## Out of scope
- Migration tooling / codemod (manual instructions are enough for the scope).

## Acceptance
- [ ] Section covers every public API change introduced by Sprint 8.
- [ ] A retailer engineer can follow it without escalating.

## Dependencies
- [core-multi-page-review-sheet](core-multi-page-review-sheet.md).

## Source
- `TODO.md` — V1-S8-DECISION.
- `docs/MIGRATION.md`.
