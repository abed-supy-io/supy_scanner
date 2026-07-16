# core-image-filter-pipeline

**Status:** planned · **Target:** v1.3.0 · **Effort:** L · **Trace:** PLAN.md §7 Post-v1.2 candidate

## Problem
Retailer needs Scanbot-parity image filters (B&W, color polish, perspective polish) for documents. PLAN.md §7 explicitly lists "image-filter pipeline" as a post-v1.2 candidate.

## Scope
- Extend `supy::scanner::enhance` with three filter modes that operate on the cropped page (not the live preview).
- Dart-level `SupyDocumentFilter.{bw, color, perspectivePolish}` enum exposed via scan options.
- Apply at re-encode time in `PageReencoder` / iOS equivalent.

## Out of scope
- Live-preview filter rendering.
- Style transfer / ML-based enhancement.

## Acceptance
- [ ] Each filter produces output within +30% encode cost vs. `mode=balanced`.
- [ ] Compat shim maps Scanbot's filter constants 1:1.
- [ ] `docs/ENHANCEMENT.md` updated with mode + filter matrix.

## Dependencies
- [core-document-image-enhance-bench](core-document-image-enhance-bench.md).

## Source
- `docs/PLAN.md` §7 Post-v1.2 candidates table.
