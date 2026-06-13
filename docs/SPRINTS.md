# Sprints

Four 2-week sprints + a buffer sprint. Each ticket is sized so one engineer can land it in 1–3 days. Tickets are grouped by phase from `PLAN.md`.

> **Definition of Done** for every ticket: PR merged, `dart analyze` clean, tests added (unit or example-app integration), entry checked off in `TODO.md`.

---

## Sprint 1 — Foundations & Android Embedded Barcode

**Goal:** project scaffolds, CI green, scanning a barcode in the embedded widget on Android.

### S1-01 — Repo scaffold *(0.5d)*
- `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `LICENSE`, `CHANGELOG.md`.
- `example/` Flutter app skeleton with two screens (barcode tab, document tab).

### S1-02 — Dart public API types *(1d)*
- `lib/src/models/supy_barcode.dart`, `supy_barcode_format.dart`, `supy_document_page.dart`, `supy_document_data.dart`, `supy_scan_error.dart`.
- All frozen value types with `==`, `hashCode`, `toString`.
- Unit tests for equality and JSON round-trip.

### S1-03 — MethodChannel + EventChannel boundary *(1d)*
- `lib/src/channel/method_channel.dart` (singleton).
- `lib/src/channel/event_channel.dart` (per-view factory).
- Mockable; unit tests use `setMockMethodCallHandler`.

### S1-04 — Android plugin skeleton *(0.5d)*
- `SupyScannerPlugin.kt` `FlutterPlugin` lifecycle.
- Empty `MethodCallHandler` returning `notImplemented`.
- AndroidManifest with camera permission.

### S1-05 — iOS plugin skeleton *(0.5d)*
- `SupyScannerPlugin.swift` registration.
- Empty MethodCallHandler.
- `Info.plist` template snippet documented in `docs/MIGRATION.md`.

### S1-06 — CI: analyze + test + example build *(1d)*
- `.github/workflows/ci.yml` running `dart analyze`, `dart format --set-exit-if-changed`, `dart test`, `flutter build apk --debug`, `flutter build ios --no-codesign`.

### S1-07 — Android PlatformView shell *(1.5d)*
- `BarcodeScannerView` implementing `PlatformView` with a `PreviewView`.
- `BarcodeScannerViewFactory` registered in the plugin.
- Empty preview displays in example app.

### S1-08 — Android CameraX preview lifecycle *(1.5d)*
- `LifecycleCameraController` bound to host activity lifecycle.
- Resume/pause on view attach/detach.
- Torch toggle wired through per-view MethodChannel.

### S1-09 — Android ML Kit barcode analyzer *(1.5d)*
- `ImageAnalysis` analyzer with `BarcodeScanning.getClient(...)`.
- `FormatMapper.kt` covering 13 formats (see `docs/SYMBOLOGIES.md`).
- Stream detections to EventChannel.

### S1-10 — Dart `SupyBarcodeScannerView` widget + finder overlay *(1d)*
- `StatefulWidget` composing `AndroidView`, finder rectangle, header/footer slots.
- 2-second cooldown logic in `SupyBarcodeScannerController`.
- Example app demonstrates a scan-and-display flow.

**Sprint 1 exit:** Android example app: open the barcode tab, point at a QR / EAN-13, see the result on screen. Header/footer slots render. Pause/resume works.

---

## Sprint 2 — iOS Embedded Barcode + Symbology Parity

**Goal:** iOS reaches barcode parity with Android. Symbology matrix is published. Permissions standardized.

### S2-01 — iOS `BarcodeScannerPlatformView` *(1.5d)*
- `FlutterPlatformView` wrapping a `UIView` with `AVCaptureVideoPreviewLayer`.
- Lifecycle: start/stop the `AVCaptureSession` on view attach/detach.

### S2-02 — iOS Vision barcode detection *(1.5d)*
- `AVCaptureVideoDataOutput` feeding a `VNDetectBarcodesRequest`.
- `SymbologyMapper.swift` mapping the 13 formats.
- Throttle to 10 detections/sec.

### S2-03 — Torch + flash availability on iOS *(0.5d)*
- `setTorch` wired to `AVCaptureDevice.torchMode`.
- `preview_started` event carries `flashAvailable`.

### S2-04 — Per-view MethodChannel parity *(1d)*
- iOS implements `pause`, `resume`, `setTorch`, `setFormats` to match Android.
- Channel-mock test verifies identical call shapes.

### S2-05 — Permission helper *(0.5d)*
- `SupyPermissions.requestCamera()` wrapping `permission_handler`.
- Returns the unified `permission_denied` / `permanentlyDenied` codes.

### S2-06 — Error code normalization *(1d)*
- `SupyScanError` shared codes (see `docs/ARCHITECTURE.md`).
- Both native sides translate platform errors into the shared set.

### S2-07 — `docs/SYMBOLOGIES.md` published *(0.5d)*
- Full per-format support matrix (Vision vs ML Kit).
- Tested in the example app against a printed reference sheet.

### S2-08 — Begin Phase 3: Android document scanner intent *(1d)*
- `GmsDocumentScanning.getClient(...)` + `startScanIntent(...)` integrated.
- `ActivityResultLauncher` returns the scan result to a pending `Result` callback.

**Sprint 2 exit:** iOS example app scans the same set of barcodes as Android. Permission denial shows a consistent error. `SYMBOLOGIES.md` published.

---

## Sprint 3 — Document Scan + OCR + Batch Barcode

**Goal:** document multi-page flow with OCR on both platforms. Batch barcode mode.

### S3-01 — iOS document scanner *(1d)*
- Present `VNDocumentCameraViewController` over the Flutter root view controller.
- Save pages as JPEGs to `NSTemporaryDirectory()`.
- Return `[{uri, width, height}]`.

### S3-02 — Android OCR pass *(1d)*
- `TextRecognition.getClient(...)` loop over scanned pages.
- Concatenate page texts; return as `ocrText`.

### S3-03 — iOS OCR pass *(1d)*
- `VNRecognizeTextRequest` with `recognitionLevel = .accurate`.
- `recognitionLanguages` from `ocrLanguages` param; default `["en-US", "ar-SA"]`.

### S3-04 — Palette + locale plumbing *(1d)*
- Pass `palettePrimary`, `paletteOnPrimary`, `locale` through the channel.
- Android: apply to GMS scanner config where supported; otherwise log "ignored" warning.
- iOS: VisionKit ignores palette (system UI) — documented limitation in `MIGRATION.md`.

### S3-05 — Page limit + JPEG quality *(0.5d)*
- `maxPages: 0` means unlimited (matches Scanbot).
- `jpegQuality` (0–100) honored on both platforms.

### S3-06 — `SupyDocumentScanner.prewarm()` *(0.5d)*
- Android: invokes `getClient(...)` to trigger the model download.
- iOS: no-op (VisionKit ships in-OS).

### S3-07 — Batch barcode mode (Android) *(1d)*
- Long-lived CameraX session keeping a `Set<String>` of unique payloads.
- On-screen counter overlay; "Done" CTA returns the list.

### S3-08 — Batch barcode mode (iOS) *(1d)*
- Mirror of S3-07 on `AVCaptureSession`.
- Same 800ms same-payload debounce.

### S3-09 — Example app: document & batch screens *(1d)*
- Document tab shows pages + OCR text.
- Batch tab shows the unique-scans counter.

### S3-10 — Memory profile pass *(0.5d)*
- Instruments / Android Profiler over a 10-page scan; document peak heap in `docs/QA.md`.

**Sprint 3 exit:** scanning a 10-page receipt produces both image pages and OCR text on both platforms. Batch mode scans 20 unique barcodes in under 30s.

---

## Sprint 4 — Compat Shim, Hardening, v1.0.0

**Goal:** drop-in compat package shipped, perf benchmarks met, docs finalized, tag v1.0.0.

### S4-01 — `supy_scanner_scanbot_compat` package *(1d)*
- Sibling package under `compat/`.
- Typedef re-exports per `MIGRATION.md` section "Compatibility shim".
- Smoke test compiles the existing retailer call shapes against the shim.

### S4-02 — Reliability harness *(1d)*
- Example-app integration test: open/close the barcode view 100 times, assert no leak.
- 50-iteration scan loop without controller dispose.

### S4-03 — Perf bench *(1.5d)*
- QR p50/p95 on a Moto G Power.
- 10-page OCR end-to-end on an iPhone SE 3.
- 20-barcode batch time.
- Numbers recorded in `docs/QA.md`.

### S4-04 — Localized strings pass *(0.5d)*
- Verify Arabic and English in the document review screen on both platforms.
- Confirm RTL layout doesn't break the embedded barcode finder overlay.

### S4-05 — README polish + dartdoc *(0.5d)*
- Top-level `README.md` final sweep.
- Generate dartdoc; publish artifact in CI.

### S4-06 — `CHANGELOG.md` for v1.0.0 *(0.25d)*
- Initial release notes.

### S4-07 — Tag v1.0.0 + internal pub publish *(0.25d)*
- Git tag + signed release.
- Pin SHA in retailer-app cutover plan (separate work).

### S4-08 — Sign-off review *(0.5d)*
- Mobile lead walks through the example app and `docs/QA.md`.

**Sprint 4 exit:** `v1.0.0` tagged. Compat shim works against a fork of retailer's `barcode_scanbot_view.dart` consumer code. All `docs/QA.md` scenarios pass.

---

## Buffer sprint

Reserved for regressions, platform-specific UI tweaks, and stakeholder feedback during the consumer-side cutover trial. **Do not pre-allocate work here.**

## Sprint capacity assumption

Two engineers full-time on the package (one Flutter/Android, one iOS) + one engineer at 25% for QA and docs. Adjust day estimates if the team shape differs.
