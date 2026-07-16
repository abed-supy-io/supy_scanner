# History — archived design and sprint docs

This file consolidates **completed** design and planning docs whose specs have
already shipped. They are preserved verbatim for archaeology — to answer "why
was this built this way?" — but they are **no longer the source of truth**.

For the current state of the codebase, consult:

- `docs/PLAN.md` / `docs/V1.1_PLAN.md` — active phase plans
- `docs/ARCHITECTURE.md` — current channel surface and threading model
- `TODO.md` — live sprint progress
- `CHANGELOG.md` — what shipped, when

If anything here disagrees with those, the live docs win.

---

## Archived: v1.0 sprint plan (was `docs/SPRINTS.md`, shipped with v1.0.0)

Four 2-week sprints + a buffer sprint. Each ticket is sized so one engineer can land it in 1–3 days. Tickets are grouped by phase from `PLAN.md`.

> **Definition of Done** for every ticket: PR merged, `dart analyze` clean, tests added (unit or example-app integration), entry checked off in `TODO.md`.

### Sprint 1 — Foundations & Android Embedded Barcode

**Goal:** project scaffolds, CI green, scanning a barcode in the embedded widget on Android.

- **S1-01 — Repo scaffold** *(0.5d)* — `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `LICENSE`, `CHANGELOG.md`. `example/` Flutter app skeleton with two screens (barcode tab, document tab).
- **S1-02 — Dart public API types** *(1d)* — `lib/src/models/supy_barcode.dart`, `supy_barcode_format.dart`, `supy_document_page.dart`, `supy_document_data.dart`, `supy_scan_error.dart`. All frozen value types with `==`, `hashCode`, `toString`. Unit tests for equality and JSON round-trip.
- **S1-03 — MethodChannel + EventChannel boundary** *(1d)* — `lib/src/channel/method_channel.dart` (singleton). `lib/src/channel/event_channel.dart` (per-view factory). Mockable; unit tests use `setMockMethodCallHandler`.
- **S1-04 — Android plugin skeleton** *(0.5d)* — `SupyScannerPlugin.kt` `FlutterPlugin` lifecycle. Empty `MethodCallHandler` returning `notImplemented`. AndroidManifest with camera permission.
- **S1-05 — iOS plugin skeleton** *(0.5d)* — `SupyScannerPlugin.swift` registration. Empty MethodCallHandler. `Info.plist` template snippet documented in `docs/MIGRATION.md`.
- **S1-06 — CI: analyze + test + example build** *(1d)* — `.github/workflows/ci.yml` running `dart analyze`, `dart format --set-exit-if-changed`, `dart test`, `flutter build apk --debug`, `flutter build ios --no-codesign`.
- **S1-07 — Android PlatformView shell** *(1.5d)* — `BarcodeScannerView` implementing `PlatformView` with a `PreviewView`. `BarcodeScannerViewFactory` registered in the plugin. Empty preview displays in example app.
- **S1-08 — Android CameraX preview lifecycle** *(1.5d)* — `LifecycleCameraController` bound to host activity lifecycle. Resume/pause on view attach/detach. Torch toggle wired through per-view MethodChannel.
- **S1-09 — Android ML Kit barcode analyzer** *(1.5d)* — `ImageAnalysis` analyzer with `BarcodeScanning.getClient(...)`. `FormatMapper.kt` covering 13 formats (see `docs/SYMBOLOGIES.md`). Stream detections to EventChannel.
- **S1-10 — Dart `SupyBarcodeScannerView` widget + finder overlay** *(1d)* — `StatefulWidget` composing `AndroidView`, finder rectangle, header/footer slots. 2-second cooldown logic in `SupyBarcodeScannerController`. Example app demonstrates a scan-and-display flow.

**Sprint 1 exit:** Android example app: open the barcode tab, point at a QR / EAN-13, see the result on screen. Header/footer slots render. Pause/resume works.

### Sprint 2 — iOS Embedded Barcode + Symbology Parity

**Goal:** iOS reaches barcode parity with Android. Symbology matrix is published. Permissions standardized.

- **S2-01 — iOS `BarcodeScannerPlatformView`** *(1.5d)* — `FlutterPlatformView` wrapping a `UIView` with `AVCaptureVideoPreviewLayer`. Lifecycle: start/stop the `AVCaptureSession` on view attach/detach.
- **S2-02 — iOS Vision barcode detection** *(1.5d)* — `AVCaptureVideoDataOutput` feeding a `VNDetectBarcodesRequest`. `SymbologyMapper.swift` mapping the 13 formats. Throttle to 10 detections/sec.
- **S2-03 — Torch + flash availability on iOS** *(0.5d)* — `setTorch` wired to `AVCaptureDevice.torchMode`. `preview_started` event carries `flashAvailable`.
- **S2-04 — Per-view MethodChannel parity** *(1d)* — iOS implements `pause`, `resume`, `setTorch`, `setFormats` to match Android. Channel-mock test verifies identical call shapes.
- **S2-05 — Permission helper** *(0.5d)* — `SupyPermissions.requestCamera()` wrapping `permission_handler`. Returns the unified `permission_denied` / `permanentlyDenied` codes.
- **S2-06 — Error code normalization** *(1d)* — `SupyScanError` shared codes (see `docs/ARCHITECTURE.md`). Both native sides translate platform errors into the shared set.
- **S2-07 — `docs/SYMBOLOGIES.md` published** *(0.5d)* — Full per-format support matrix (Vision vs ML Kit). Tested in the example app against a printed reference sheet.
- **S2-08 — Begin Phase 3: Android document scanner intent** *(1d)* — `GmsDocumentScanning.getClient(...)` + `startScanIntent(...)` integrated. `ActivityResultLauncher` returns the scan result to a pending `Result` callback.

**Sprint 2 exit:** iOS example app scans the same set of barcodes as Android. Permission denial shows a consistent error. `SYMBOLOGIES.md` published.

### Sprint 3 — Document Scan + OCR + Batch Barcode

**Goal:** document multi-page flow with OCR on both platforms. Batch barcode mode.

- **S3-01 — iOS document scanner** *(1d)* — Present `VNDocumentCameraViewController` over the Flutter root view controller. Save pages as JPEGs to `NSTemporaryDirectory()`. Return `[{uri, width, height}]`.
- **S3-02 — Android OCR pass** *(1d)* — `TextRecognition.getClient(...)` loop over scanned pages. Concatenate page texts; return as `ocrText`.
- **S3-03 — iOS OCR pass** *(1d)* — `VNRecognizeTextRequest` with `recognitionLevel = .accurate`. `recognitionLanguages` from `ocrLanguages` param; default `["en-US", "ar-SA"]`.
- **S3-04 — Palette + locale plumbing** *(1d)* — Pass `palettePrimary`, `paletteOnPrimary`, `locale` through the channel. Android: apply to GMS scanner config where supported; otherwise log "ignored" warning. iOS: VisionKit ignores palette (system UI) — documented limitation in `MIGRATION.md`.
- **S3-05 — Page limit + JPEG quality** *(0.5d)* — `maxPages: 0` means unlimited (matches Scanbot). `jpegQuality` (0–100) honored on both platforms.
- **S3-06 — `SupyDocumentScanner.prewarm()`** *(0.5d)* — Android: invokes `getClient(...)` to trigger the model download. iOS: no-op (VisionKit ships in-OS).
- **S3-07 — Batch barcode mode (Android)** *(1d)* — Long-lived CameraX session keeping a `Set<String>` of unique payloads. On-screen counter overlay; "Done" CTA returns the list.
- **S3-08 — Batch barcode mode (iOS)** *(1d)* — Mirror of S3-07 on `AVCaptureSession`. Same 800ms same-payload debounce.
- **S3-09 — Example app: document & batch screens** *(1d)* — Document tab shows pages + OCR text. Batch tab shows the unique-scans counter.
- **S3-10 — Memory profile pass** *(0.5d)* — Instruments / Android Profiler over a 10-page scan; document peak heap in `docs/QA.md`.

**Sprint 3 exit:** scanning a 10-page receipt produces both image pages and OCR text on both platforms. Batch mode scans 20 unique barcodes in under 30s.

### Sprint 4 — Compat Shim, Hardening, v1.0.0

**Goal:** drop-in compat package shipped, perf benchmarks met, docs finalized, tag v1.0.0.

- **S4-01 — `supy_scanner_scanbot_compat` package** *(1d)* — Sibling package under `compat/`. Typedef re-exports per `MIGRATION.md` section "Compatibility shim". Smoke test compiles the existing retailer call shapes against the shim.
- **S4-02 — Reliability harness** *(1d)* — Example-app integration test: open/close the barcode view 100 times, assert no leak. 50-iteration scan loop without controller dispose.
- **S4-03 — Perf bench** *(1.5d)* — QR p50/p95 on a Moto G Power. 10-page OCR end-to-end on an iPhone SE 3. 20-barcode batch time. Numbers recorded in `docs/QA.md`.
- **S4-04 — Localized strings pass** *(0.5d)* — Verify Arabic and English in the document review screen on both platforms. Confirm RTL layout doesn't break the embedded barcode finder overlay.
- **S4-05 — README polish + dartdoc** *(0.5d)* — Top-level `README.md` final sweep. Generate dartdoc; publish artifact in CI.
- **S4-06 — `CHANGELOG.md` for v1.0.0** *(0.25d)* — Initial release notes.
- **S4-07 — Tag v1.0.0 + internal pub publish** *(0.25d)* — Git tag + signed release. Pin SHA in retailer-app cutover plan (separate work).
- **S4-08 — Sign-off review** *(0.5d)* — Mobile lead walks through the example app and `docs/QA.md`.

**Sprint 4 exit:** `v1.0.0` tagged. Compat shim works against a fork of retailer's `barcode_scanbot_view.dart` consumer code. All `docs/QA.md` scenarios pass.

### Buffer sprint

Reserved for regressions, platform-specific UI tweaks, and stakeholder feedback during the consumer-side cutover trial. **Do not pre-allocate work here.**

### Sprint capacity assumption

Two engineers full-time on the package (one Flutter/Android, one iOS) + one engineer at 25% for QA and docs. Adjust day estimates if the team shape differs.

---

## Archived: V1-S6-02 — `captureAndRectify` channel-method design (was `docs/V1-S6-02-CAPTURE-DESIGN.md`)

Original status: design only (native impl is V1-S6-03/04 once Sprint 4 `warpPerspective` lands).
Owner: Abed.
Depends on: V1-S4-0x — `supy_scanner_core::warpPerspective` + DoQA gate.
Consumed by: V1-S6-03 (Android), V1-S6-04 (iOS), retailer demo flow (Sprint 6 exit criterion).

Current status (2026-06-17): **iOS implementation landed** (`CIPerspectiveCorrection` + `AVCapturePhotoOutput` in `SupyDocumentScannerView.swift`); Android `captureAndRectify` still blocked on Sprint 4 `warpPerspective` and falls back to `captureFullFrame`. See `TODO.md` V1-S6-02 for the live status.

### 1. Why this doc exists

The Dart wire surface is already implemented (`SupyDocumentScannerController.capture()` / `.captureAndRectify()` / `.captureFullFrame()` in `lib/src/widgets/supy_document_scanner_controller.dart:197-275`). Native handlers do not exist yet. This doc nails down what the native side has to deliver so V1-S6-03 / V1-S6-04 can be implemented and reviewed against a single specification — and reconciles two stale entries (`docs/ARCHITECTURE.md:156` and `docs/V1.1_PLAN.md:277`) against the canonical Dart shape.

### 2. Reconciliation — stale doc rows

Three sources currently disagree:

| Source | Return shape | quad? | Second method? |
|---|---|---|---|
| `docs/ARCHITECTURE.md:156` | `{ uri, width, height }` | no | no |
| `docs/V1.1_PLAN.md:277` | `{ uri, width, height, quad: [{x,y}×4] }` | yes | no |
| `lib/src/widgets/supy_document_scanner_controller.dart` (truth) | `{ path, widthPx, heightPx, quad: [{x,y}…] }` accepts legacy `uri`/`width`/`height` | yes | yes — `captureFullFrame` |

**Resolution.** The Dart layer is the source of truth — both docs get updated, not the wire. Canonical keys are `path` / `widthPx` / `heightPx` / `quad`. Native MUST emit canonical keys. Legacy keys (`uri`/`width`/`height`) remain Dart-side aliases for forward compatibility but native MUST NOT emit them.

Doc updates that land alongside V1-S6-03:

- `docs/ARCHITECTURE.md:156` row replaced (see §3 below — paste verbatim).
- `docs/ARCHITECTURE.md` gains a second row for `captureFullFrame`.
- `docs/V1.1_PLAN.md` §6 return shape updated to canonical keys.
- `docs/MIGRATION.md` — no change. Both methods are additive on a v1.1 controller; retailer Scanbot call sites do not invoke either.

### 3. Final channel surface

Channel: `io.supy.scanner/v1/document/<viewId>` (per-view, already wired). Channel name does **not** bump — additive methods only.

#### Method: `captureAndRectify`

| Field | Value |
|---|---|
| Args | `{}` (none) |
| Returns | `{ path: string, widthPx: int, heightPx: int, quad: [{x: double, y: double}, …] }` |
| Returns on no-document | error, NOT `null` — see §6 |
| Threading | rectify + JPEG write off main; result marshalled to main at the `FlutterResult.success` boundary |

The `quad` is the **input** quad (the last smoothed frame quad, in preview coordinates with top-left origin) that the warp consumed. It is NOT the corners of the output rectangle (the output rectangle is by construction `(0,0)–(widthPx, heightPx)`). Returning the input quad lets the host UI draw a "captured from this region" debug overlay.

#### Method: `captureFullFrame`

| Field | Value |
|---|---|
| Args | `{}` |
| Returns | `{ path: string, widthPx: int, heightPx: int, quad: [] }` |
| Threading | JPEG write off main; result on main |

Used by `SupyDocumentScannerView` as the `allowUnrectifiedFallback` retry path when `captureAndRectify` fails with `captureUnsupported` (no quad locked). No rectification, no DoQA gate — caller decided to accept whatever's in frame.

#### ARCHITECTURE.md row replacements

Replace the existing `captureAndRectify` row at line 156, and add the new `captureFullFrame` row:

```
| `captureAndRectify` | — | `{ path: string, widthPx: int, heightPx: int, quad: [{x, y}, …] }`. Native rectifies the last smoothed quad to a top-down rectangle (warpPerspective via `supy_scanner_core`, ≥300 DPI when `useNativeCore` is on) and persists the JPEG (quality follows `SupyDocumentScanOptions.jpegQuality`). `quad` is the consumed input quad in preview coordinates with top-left origin. Errors: `captureUnsupported` (no quad locked / DoQA gate failed), `capture_failed`, `unknown`. v1.1 / Sprint 6 — depends on Sprint 4 `warpPerspective`. |
| `captureFullFrame` | — | `{ path: string, widthPx: int, heightPx: int, quad: [] }`. Persists the next preview frame verbatim, no rectification, no DoQA gate. Used as the `allowUnrectifiedFallback` retry path. Errors: `capture_failed`, `unknown`. |
```

### 4. Android implementation sketch (V1-S6-03)

Path: `android/src/main/kotlin/io/supy/scanner/document/SupyDocumentScannerView.kt` (existing file; the per-view `MethodChannel.MethodCallHandler` is already registered for `pause` / `resume` / `setTorch`).

#### Quad source

`DocumentFrameAnalyzer` (existing) already runs the per-frame edge detector and emits `frame_metrics` events. It must additionally hold the last **smoothed** quad as `@Volatile var lastSmoothedQuad: FloatArray? = null` (8 floats — 4 corner points, preview coordinates, top-left origin). The analyzer writes to this on every accepted frame; the channel handler reads it on `captureAndRectify`.

#### Handler flow (`captureAndRectify`)

1. Read `lastSmoothedQuad` snapshot. If `null` → fail `result.error("captureUnsupported", "no smoothed quad available", null)` on the main thread. Done.
2. Grab the next preview frame via the CameraX `ImageAnalysis` analyzer's "next frame" latch. (One-shot `OnImageAnalyzed` listener; releases the `ImageProxy` after copy.)
3. Hop to a worker `ExecutorService` (single thread, reused across calls):
   1. Convert YUV → RGB (existing helper in `android/src/main/cpp/supy_scanner_core_jni.cpp`).
   2. Call `supy_scanner_core::warpPerspective(rgb, quad, dstW, dstH)`. `dstW`/`dstH` derived from the quad's bounding rectangle, scaled to ≥300 DPI when `useNativeCore` is on and `jpegQuality > 0`.
   3. JPEG-encode via existing `PageReencoder` at `SupyDocumentScanOptions.jpegQuality`.
   4. Write to the cache dir under `<cacheDir>/supy_scanner/captures/<uuid>.jpg`. Same convention as Sprint 4 launcher pages.
   5. Build the result map (canonical keys; `quad` serialized as `List<Map<String, Double>>`).
4. Marshal to main thread via `mainHandler.post { result.success(map) }`.
5. Exceptions in steps 3.1–3.5 → `result.error("capture_failed", e.message, null)` on main.

#### Handler flow (`captureFullFrame`)

Identical except step 3.1 reads the raw frame, step 3.2 is skipped, `dstW`/`dstH` = source dimensions, `quad` field is `emptyList()`.

#### Threading invariants

- `lastSmoothedQuad` is `@Volatile` — single writer (analyzer thread), single reader (channel handler). No lock needed; a torn read is impossible because `FloatArray?` is one reference.
- The next-frame latch is one-shot per capture call. Two overlapping `captureAndRectify` calls are prevented Dart-side (`controller.capture()` ignores re-entrant calls — line 200) but the native side defends anyway: a `@Volatile var captureInFlight = false` guard short-circuits the second call with `capture_failed`.
- `ImageProxy` must be `.close()`d in a `try/finally` before hopping to the worker thread to avoid back-pressuring CameraX.

#### Lifecycle

`dispose()` shuts down the worker `ExecutorService` and cancels the next-frame latch. A capture in flight at dispose resolves with `capture_failed` ("view disposed").

### 5. iOS implementation sketch (V1-S6-04)

Path: `ios/Classes/document/SupyDocumentScannerView.swift` (existing file; per-view `FlutterMethodChannel` already registered).

#### Quad source

`DocumentScannerPresenter` (existing) drives the per-frame `VNDetectDocumentSegmentationRequest` / `VNDetectRectanglesRequest`. It must expose `private(set) var lastSmoothedQuad: [CGPoint]? = nil` guarded by a dedicated serial queue (`quadAccessQueue`). The analyzer writes; the channel handler reads via `quadAccessQueue.sync`.

#### Handler flow (`captureAndRectify`)

1. `quadAccessQueue.sync { lastSmoothedQuad }` → if `nil`, fail `result(FlutterError(code: "captureUnsupported", message: "no smoothed quad available", details: nil))` on `.main` (the FlutterResult queue is already main).
2. Pull the next pixel buffer from the active `AVCaptureVideoDataOutput` delegate. The presenter holds a one-shot `pendingCapture: ((CVPixelBuffer) -> Void)?` closure; the delegate fires it on the next sample-buffer callback and nils it out.
3. Hop to a background `DispatchQueue.global(qos: .userInitiated)`:
   1. Convert the pixel buffer to the format `supy_scanner_core::warpPerspective` expects (existing helper).
   2. Call `warpPerspective(...)` with the snapshotted quad.
   3. JPEG-encode via the existing `JpegReencoder` (path: `ios/Classes/document/JpegReencoder.swift` — already shipped).
   4. Write to `NSTemporaryDirectory()` / `supy_scanner/captures/<uuid>.jpg`.
   5. Build the result dict (canonical keys; `quad` as `[["x": Double, "y": Double], …]`).
4. `DispatchQueue.main.async { result(dict) }`.
5. Failures in 3.1–3.5 → `result(FlutterError(code: "capture_failed", ...))` on main.

#### Handler flow (`captureFullFrame`)

Same as Android — skip the warp, dst dims = source dims, `quad` is empty.

#### Threading invariants per `CLAUDE.md`

- `AVCaptureSession` start/stop already happens on `DispatchQueue.global(qos: .userInitiated)`. Nothing in this design changes that.
- All `VNRequest` work stays on the presenter's background queue; `lastSmoothedQuad` updates happen there.
- Results cross to `.main` only at the `FlutterResult` boundary.
- `iOS 16` floor: `VNDetectDocumentSegmentationRequest` is iOS 17+. The iOS 16 fallback path uses `VNDetectRectanglesRequest` (already shipped). `captureAndRectify` does NOT need an `@available(iOS 17, *)` gate — both detectors feed the same `lastSmoothedQuad`.

### 6. Error mapping

Single source of truth — both platforms emit the same codes verbatim.

| Code | When | `message` |
|---|---|---|
| `captureUnsupported` | No smoothed quad available (FSM not in `documentReady`/`capturing`). Or DoQA gate failed (blur / coverage / tilt out of bounds — V1-S7-02). | Reason — `"no smoothed quad available"`, `"DoQA: blur too high (score=…)"`, etc. |
| `capture_failed` | Anything between "got a quad" and "wrote the JPEG" — YUV conversion, warp failure, encoder failure, fs write failure, re-entrant call, view disposed mid-capture. | Underlying `Throwable` / `NSError.localizedDescription`. |
| `unknown` | Truly unexpected (NPE / Swift trap caught at the channel boundary). | Stringified exception. |

`PlatformException(code: "captureUnsupported")` is the contract the Dart controller decodes into `StateError('captureUnsupported: …')` (see `supy_document_scanner_controller.dart:239`). The `UNIMPLEMENTED` alias the Dart side also accepts is a v1.0 vestige; native MUST NOT emit it.

Channel-wide canonical error codes (`docs/ARCHITECTURE.md:208`) remain unchanged — `captureUnsupported` and `capture_failed` are method-scoped, not canonical channel codes. They are documented under the `captureAndRectify` row, not in the channel-wide table.

### 7. Out of scope

- **`useNativeCore = false` path.** Spec says the warp uses `supy_scanner_core` "≥300 DPI when `useNativeCore` is on". With it off, the native side falls back to a platform warp (Vision `VNImageRequestHandler`'s `perspectiveCorrection` on iOS; nothing equivalent on Android — Android with `useNativeCore=false` MUST surface `captureUnsupported`). The Android fallback gap is logged as a Sprint 6 follow-up.
- **HEIC output.** Sprint 6 sticks to JPEG. HEIC is a v1.2 decision.
- **Multi-page sequencing.** `captureAndRectify` returns one page; the multi-page collector lives in the host UI (Sprint 7).
- **Quality scoring at the wire.** V1-S7-02 lands the DoQA scorer which feeds into the `captureUnsupported` gate; the wire shape doesn't change.

### 8. Open questions

1. **Quad coordinate normalization.** The `frame_metrics` event quad is in **preview coordinates** with top-left origin (`docs/ARCHITECTURE.md:165`). Should the returned `quad` field also be preview coords, or normalized [0,1]×[0,1]? Recommendation: keep preview coords for consistency with `frame_metrics`. The host already maps preview coords for the overlay; one coordinate system is one less thing to get wrong.
2. **Output DPI cap.** Sprint 4 spec says ≥300 DPI. For an A4 source at 300 DPI that's ~2480×3508 px — fine for OCR, heavy for memory on LOW-tier devices. Recommendation: cap `max(dstW, dstH) ≤ 3508` and document the ceiling.

Both questions are non-blocking for the doc but the answers must land in the V1-S6-03 PR.

### 9. Test plan (lands with V1-S6-03/04, not now)

- **Android JVM unit:** mock `DocumentFrameAnalyzer.lastSmoothedQuad` and the worker executor; assert canonical-key map shape for both success and each error code path.
- **iOS XCTest unit:** stub the presenter's `pendingCapture` closure; assert canonical-key dict shape and the same error mapping.
- **Dart channel fuzz:** extend `test/channel/fuzz_test.dart` with `captureAndRectify` / `captureFullFrame` payloads — canonical, legacy alias, missing-quad, extra-keys, malformed quad entries.
- **Example integration:** `example/integration_test/document_capture_test.dart` (new) under `SUPY_SCANNER_DEVICE_TEST=true` gating.
- **QA scenario:** add `D13` to `docs/QA.md` — "embedded preview capture end-to-end". Sprint-scoped to v1.1.x in the per-release scope table.
