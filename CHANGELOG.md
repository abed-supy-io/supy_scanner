# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-13

First stable release. Drop-in replacement for Scanbot SDK in the Supy retailer mobile app.

### Added
- Public Dart API: `SupyBarcode`, `SupyBarcodeFormat`, `SupyBarcodeScannerView`, `SupyBarcodeScannerController`, `SupyDocumentData`, `SupyDocumentPage`, `SupyScanError`, `SupyScanOptions`, `SupyBatchBarcodeScanOptions`, `SupyDocumentScanOptions`.
- Embedded barcode preview via Android `LifecycleCameraController` + ML Kit and iOS `AVCaptureSession` + Vision; per-view MethodChannel for `pause`/`resume`/`setTorch`/`setFormats`.
- Finder overlay, configurable scan window, 2s cooldown, torch toggle.
- Document scanning: iOS `VNDocumentCameraViewController`, Android `GmsDocumentScanning`. JPEG re-encode + `maxPages` (0 = unlimited).
- OCR: iOS `VNRecognizeTextRequest` (en + ar), Android ML Kit `TextRecognition`.
- Batch barcode session with native dedupe.
- `SupyScannerChannel.instance.scanDocument(...)` and `.scanBarcodesBatch(...)`; `SupyDocumentScanner.prewarm()`.
- Permission helper `SupyPermissions.requestCamera()`.
- Standardized error codes via `SupyScanError(code: SupyScanErrorCode, message)`.
- Versioned channel `io.supy.scanner/v1`.

### Compat
- `supy_scanner_scanbot_compat` sibling package shipping `BarcodeScanbotView`, `BarcodeScannerController`, `BarcodeItem`, `IInvoiceScannerService`, `InvoiceScannerService` — verbatim Scanbot shapes wired over `supy_scanner`.

### Docs
- `PLAN.md`, `ARCHITECTURE.md`, `MIGRATION.md`, `SYMBOLOGIES.md`, `LOCALIZATION.md`, `QA.md`, `SPRINTS.md`.

### Pending sign-off
- Real-device perf numbers (`example/integration_test/perf_bench_test.dart`).
- Reliability harness execution under Profiler/Instruments (`example/integration_test/reliability_harness_test.dart`).
- Memory profile pass (S3-10).
- Mobile-lead walkthrough of `docs/QA.md` scenarios on Android + iPhone (S4-08).
