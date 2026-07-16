# core-csu-result-parity

**Status:** planned · **Target:** v1.3.0 · **Effort:** M · **Trace:** PLAN.md Phase CSU5–CSU6

## Problem
Before CSU becomes default, results must match the GMS/VisionKit baselines structurally so the retailer app sees no change. Need automated parity tests, not just spot checks.

## Scope
- Fixture-driven test that runs the same input through legacy and CSU backends and diffs the `SupyDocumentPage` shape + bytes-at-format.
- Cover JPG, PNG, and PDF outputs.
- Run on both Android Robolectric and iOS XCTest layers.

## Out of scope
- Pixel-perfect image equality (different encoders) — diff at structure + checksum-of-decoded-content level.

## Acceptance
- [ ] Parity suite green on the QA fixture set for at least 20 documents.
- [ ] Any new field added to the result requires updating the parity baseline in the same PR.

## Dependencies
- All other CSU items.

## Source
- `docs/PLAN.md` — Phase CSU5–CSU6.
