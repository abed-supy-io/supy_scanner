# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — Unreleased (pending P5 re-bench)

Performance workstream from `docs/PERFORMANCE.md`. **No public API changes** — all event additions are advisory and backwards-compatible (consumers that ignore them continue to work). Drop-in for v1.0.0 retailer consumers.

### Added
- Device-tier classifier (Android: `perf/DeviceTier.kt`; iOS: `perf/SupyDeviceTier.swift`) — runtime HIGH / MID / LOW resolution drives analyzer resolution, FPS cap, and idle threshold. HIGH tier is uncapped — flagship behavior matches v1.0.0.
- `ThermalGovernor` (Android API 29+ `PowerManager.OnThermalStatusChangedListener`) / `SupyThermalGovernor` (iOS `ProcessInfo.thermalStateDidChangeNotification`). Pauses analyzer on `serious`+ (Android: `SEVERE`+); throttles FPS on `fair`+ (Android: `MODERATE`+). Emits `{type: 'thermal', state, paused, throttled}` over the barcode EventChannel. Android `STATE_SEVERE` is normalized to wire-string `"serious"` to match iOS — consumers branch on a single vocabulary.
- `IdleDetector` / `SupyIdleDetector` — luma-variance gate (32×32 strided Y-plane sample) drops frames before ML Kit / Vision when the scene is still. Emits `{type: 'idle_pause'}` / `{type: 'idle_resume'}` on transition. MID/LOW tiers only; HIGH opts out.
- `torch_idle_suggested` advisory event — emitted alongside `idle_pause` when the torch is currently on. Native does NOT auto-toggle the torch; consumers may call `setTorch(false)` to save battery.
- OCR image downscaling (tier-tiered): HIGH uncapped, MID 1600 px long edge, LOW 1280 px long edge — applied before the recognizer; persisted `pages` are unchanged. JPEG-quality cap on LOW (≤ 75); MID/HIGH pass through consumer request. Peak heap on 10-page OCR drops from ~360 MB to ~25 MB on 4 GB-RAM Android.

### Hardened
- `BatchBarcodeScannerPresenter` (iOS) now observes `AVCaptureSessionWasInterrupted` / `InterruptionEnded` / `RuntimeError` and gates `startRunning()` through `safeStartRunning()`. Mirrors `SupyBarcodeScannerView`'s interruption guard — fixes NSGenericException on Control Center / phone-call resume.

### Docs
- `docs/PERFORMANCE.md` — phased plan, bench protocol, Results (v1.1.x) table, sign-off checklist.
- `docs/MIGRATION.md` — new "v1.1 Performance — advisory events" section documenting payload shapes.
- `docs/ARCHITECTURE.md` — `idle_pause` / `idle_resume` event types under barcode EventChannel.

### Channel
- Channel name unchanged: `io.supy.scanner/v1`. Additive event types only.

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
