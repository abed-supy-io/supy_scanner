# TODO — supy_scanner v1.0.0

Live tracker. Check items off as work lands. Source of truth for sprint progress.

## Sprint 1 — Foundations & Android Embedded Barcode

- [x] S1-01 — Repo scaffold (`pubspec.yaml`, lints, example skeleton) — 2026-06-13
- [x] S1-02 — Dart public API types (`SupyBarcode`, `SupyBarcodeFormat`, `SupyDocumentData`, `SupyDocumentPage`, `SupyScanError`) — 2026-06-13
- [x] S1-03 — MethodChannel + EventChannel boundary + mock tests — 2026-06-13
- [x] S1-04 — Android plugin skeleton + manifest camera permission — 2026-06-13
- [x] S1-05 — iOS plugin skeleton + `Info.plist` template doc — 2026-06-13
- [x] S1-06 — CI: analyze, format, test, build both platforms — 2026-06-13
- [x] S1-07 — Android PlatformView shell + factory — 2026-06-13
- [x] S1-08 — Android CameraX preview lifecycle + torch — 2026-06-13
- [x] S1-09 — Android ML Kit barcode analyzer + format mapper — 2026-06-13
- [x] S1-10 — Dart `SupyBarcodeScannerView` + finder overlay + 2s cooldown — 2026-06-13

## Sprint 2 — iOS Embedded Barcode + Symbology Parity

- [x] S2-01 — iOS `BarcodeScannerPlatformView` (AVCaptureSession) — 2026-06-13
- [x] S2-02 — iOS Vision barcode detection + symbology mapper — 2026-06-13
- [x] S2-03 — iOS torch + `flashAvailable` event — 2026-06-13
- [x] S2-04 — Per-view MethodChannel parity (`pause`/`resume`/`setTorch`/`setFormats`) — 2026-06-13
- [x] S2-05 — Permission helper (`SupyPermissions.requestCamera()`) — 2026-06-13
- [x] S2-06 — Error code normalization — 2026-06-13
- [x] S2-07 — Publish `docs/SYMBOLOGIES.md` matrix verified against printed sheet — 2026-06-13
- [x] S2-08 — Begin Phase 3: Android `GmsDocumentScanning` intent — 2026-06-13

## Sprint 3 — Document Scan + OCR + Batch Barcode

- [x] S3-01 — iOS `VNDocumentCameraViewController` integration — 2026-06-13
- [x] S3-02 — Android `TextRecognition` OCR pass — 2026-06-13
- [x] S3-03 — iOS `VNRecognizeTextRequest` OCR pass (en + ar) — 2026-06-13
- [x] S3-04 — Palette + locale plumbing (accepted at wire boundary; VisionKit & GMS scanner UIs are system-owned, so palette/locale are no-ops on-device — documented in `docs/MIGRATION.md`) — 2026-06-13
- [x] S3-05 — `maxPages` (0 = unlimited) + `jpegQuality` re-encode — 2026-06-13
- [x] S3-06 — `SupyDocumentScanner.prewarm()` — 2026-06-13
- [x] S3-07 — Android batch barcode session — 2026-06-13
- [x] S3-08 — iOS batch barcode session — 2026-06-13
- [x] S3-09 — Example app: document & batch screens — 2026-06-13
- [ ] S3-10 — Memory profile pass + recorded numbers in `docs/QA.md`

## Sprint 4 — Compat Shim, Hardening, v1.0.0

- [x] S4-01 — `supy_scanner_scanbot_compat` package + smoke compile against retailer call shapes (2026-06-13)
- [x] S4-02 — Reliability harness (100 open/close, 50-iter scan loop) — authored 2026-06-13; device run pending sign-off
- [x] S4-03 — Perf bench numbers recorded — harness authored 2026-06-13; numbers pending device run
- [x] S4-04 — Localized strings pass (en + ar, RTL) — audit clean; `docs/LOCALIZATION.md` published; compat AppBar string removed (2026-06-13); device verification pending sign-off
- [x] S4-05 — README polish + dartdoc — README rewritten for v1.0.0; lib/ analyzer clean incl. `public_member_api_docs` (2026-06-13)
- [x] S4-06 — `CHANGELOG.md` for v1.0.0 — 2026-06-13
- [ ] S4-07 — Tag `v1.0.0` + internal pub publish
- [ ] S4-08 — Mobile-lead sign-off walkthrough

## QA scenarios

See `docs/QA.md`. Track per-release sign-off there.

## Out-of-scope (do not start here)

- Retailer-app cutover (separate plan).
- CameraX-based document fallback for non-GMS Android.
- MRZ / ID-card recognition.
- Web/desktop support.

## Decisions log

- **2026-06-13** — Embedded PlatformView is **in scope** for v1 (required for drop-in compatibility with `BarcodeScanbotView`). Earlier draft scoped this out — corrected before any code shipped.
- **2026-06-13** — iOS deployment target jumps from 13 to 16. Confirm retailer iOS-15 fleet share is < 1% before cutover.
- **2026-06-13** — Compat shim package (`supy_scanner_scanbot_compat`) ships alongside v1 to allow import-only migration.
