# adj-mrz-recognition

**Status:** planned · **Target:** v1.4.0 · **Effort:** L · **Trace:** PLAN.md §7 Post-v1.2 candidate

## Problem
Retailer KYC flows may need MRZ (machine-readable zone) reading for passports / national IDs. PLAN.md §7 explicitly lists "MRZ / passport" as a post-v1.2 candidate, retailer-need-gated.

## Scope
- Add a dedicated MRZ recognizer mode: OCR pass with a fixed font model (OCR-B) + ICAO 9303 line parser.
- New `SupyMrzResult` sealed types (TD1, TD2, TD3) with checksum-validated fields.
- iOS uses Vision text recognition with custom words; Android uses ML Kit text + a parser.

## Out of scope
- Cloud verification.
- Full NFC chip read (separate epic if ever taken).

## Acceptance
- [ ] ≥ 95% parse rate on the ICAO public sample set.
- [ ] All on-device, no network call.
- [ ] Compat shim untouched (this is a new surface, not a compat replacement).

## Dependencies
- Owned capture surface from [core-csu-ios-avcapture](core-csu-ios-avcapture.md) / [core-csu-android-camerax-default](core-csu-android-camerax-default.md).

## Source
- `docs/PLAN.md` §7 Post-v1.2 candidates.
- CLAUDE.md "no cloud OCR" rule.
