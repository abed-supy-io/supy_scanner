# core-multi-page-review-sheet

**Status:** decision-gated · **Target:** v1.3.0 · **Effort:** L · **Trace:** TODO.md V1-S8-DECISION

## Problem
Sprint 8 in v1.1 is blocked on a decision about owning the multi-page review/reorder UI. Until owned, retailer falls back to the GMS/VisionKit reviewer, which constrains branding and reorder gestures.

## Scope
- Build a Dart-side `SupyDocumentReviewSheet` that consumes the page list from the capture activity.
- Reorder, retake, delete-page, re-crop primitives.
- Surface only after the V1-S8-DECISION is "build owned".

## Out of scope
- Editing pixels (crop coords only, not pixel filters — that's [core-image-filter-pipeline](core-image-filter-pipeline.md)).

## Acceptance
- [ ] Drop-in for both CSU-default and GMS paths.
- [ ] Compat shim exposes the legacy Scanbot review API.
- [ ] No `flutter_bloc` dependency; expose streams + ChangeNotifier per CLAUDE.md.

## Dependencies
- V1-S8-DECISION resolved.
- [core-csu-result-parity](core-csu-result-parity.md).

## Source
- `TODO.md` — V1-S8-DECISION; `docs/HISTORY.md` § "Archived: V1-S6-02 — `captureAndRectify` channel-method design".
