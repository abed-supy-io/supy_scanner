# ml-doc-type-router

**Status:** planned · **Target:** v1.3.0 · **Effort:** M · **Trace:** completes core-image-filter-pipeline

## Problem
`supy::scanner::enhance` ships modes (off / fast / balanced / max) and (once `core-image-filter-pipeline` lands) filters (b&w / color / perspective-polish). Choosing the right combo per document is on the consumer. A small classifier can pick automatically based on doc type.

## Scope
- 5-class classifier — `invoice | receipt | id_card | business_card | other`, ~1 MB.
- Runs once per captured page (not per frame).
- Output drives a router that picks `(enhanceMode, filter)` from a small policy table.
- Consumer can override via `SupyScanOptions.documentTypeOverride` for deterministic flows.
- Budget: ~1 MB bundled.

## Out of scope
- A general doc-classification API beyond the 5 classes.
- Field extraction (that's `adj-id-card-recognition` / receipt-template work).

## Acceptance
- [ ] Classifier accuracy ≥ 92% on the QA fixture set per class.
- [ ] Routing policy table committed under `lib/src/enhance/policy/` and reviewable diff-by-diff.
- [ ] Override path covered by unit test.

## Dependencies
- [ml-runtime-and-loader](ml-runtime-and-loader.md), [core-image-filter-pipeline](core-image-filter-pipeline.md).

## Source
- This conversation's ML roadmap.
