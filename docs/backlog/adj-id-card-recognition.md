# adj-id-card-recognition

**Status:** planned · **Target:** v1.4.0 · **Effort:** L · **Trace:** PLAN.md §7 Post-v1.2 candidate

## Problem
Beyond MRZ, retailer onboarding may need parsed ID-card fields (name, DoB, ID number) for jurisdictions with non-MRZ cards. Listed in PLAN.md §7 alongside MRZ.

## Scope
- Owned capture surface with field-aware OCR (templates per supported card type, e.g. UAE Emirates ID front/back).
- Sealed `SupyIdCardResult` per card type.
- On-device only; the field templates live under `lib/src/idcard/templates/`.

## Out of scope
- Government registry lookups.
- Liveness / face-match (separate epic).

## Acceptance
- [ ] First supported type (defined with retailer) parses with ≥ 95% field accuracy on the fixture set.
- [ ] Template registration is plug-in style — adding a new card type doesn't change the channel surface.

## Dependencies
- [adj-mrz-recognition](adj-mrz-recognition.md) (shares the OCR + capture plumbing).

## Source
- `docs/PLAN.md` §7 Post-v1.2 candidates.
