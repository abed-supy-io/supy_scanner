# Architecture

## Layering

```
┌───────────────────────────────────────────────┐
│  Retailer app (supy-mobile)                   │
│  - feature pages call SupyBarcodeScannerView  │
│  - feature pages call SupyInvoiceScannerService│
└──────────────────┬────────────────────────────┘
                   │
┌──────────────────▼────────────────────────────┐
│  supy_scanner_scanbot_compat (optional shim)  │
│  - BarcodeScanbotView = SupyBarcodeScannerView│
│  - BarcodeItem        = SupyBarcode           │
│  - InvoiceScannerService(impl with SupyScanner)│
└──────────────────┬────────────────────────────┘
                   │
┌──────────────────▼────────────────────────────┐
│  supy_scanner (Dart)                          │
│  ┌────────────────────────┐  ┌──────────────┐│
│  │ widgets/               │  │ services/    ││
│  │  BarcodeScannerScreen  │  │  Document    ││
│  │   ├ ArOverlay          │  │  Permissions ││
│  │   ├ TopBar/ActionBar   │  │              ││
│  │   └ Sheets (single/    │  └──────┬───────┘│
│  │      multi/find&pick)  │         │        │
│  │  BarcodeScannerView    │         │        │
│  │  Controller            │         │        │
│  └────────┬───────────────┘         │        │
│  ┌────────▼─────────────────────────▼──────┐ │
│  │ models/ui/  (v1.1 frozen UI configs)    │ │
│  │  Palette · TopBar · ViewFinder ·        │ │
│  │  UserGuidance · ActionBar · ArOverlay · │ │
│  │  Camera · sealed ScanUseCase            │ │
│  └────────┬────────────────────────────────┘ │
│  ┌────────▼────────────────────────────────┐ │
│  │ channel/                                │ │
│  │  MethodChannel('io.supy.scanner/v1')    │ │
│  │  EventChannel('.../barcode/<viewId>')   │ │
│  └────────┬────────────────────────────────┘ │
└───────────┼──────────────────────────────────┘
            │
┌───────────▼────────────────┐  ┌──────────────────────────────┐
│  Android (Kotlin)           │  │  iOS (Swift)                 │
│  ├ CameraX preview          │  │  ├ AVCaptureSession          │
│  ├ ML Kit Barcode           │  │  ├ Vision VNDetectBarcodes   │
│  ├ GMS Document Scanner     │  │  ├ VisionKit VNDocumentCamera│
│  └ ML Kit Text Recognition  │  │  └ Vision VNRecognizeText    │
└─────────────────────────────┘  └──────────────────────────────┘
```

## Module responsibilities

### Dart layer

| Module | Responsibility |
|---|---|
| `models/` | Frozen value types — `SupyBarcode`, `SupyBarcodeFormat`, `SupyDocumentData`, `SupyDocumentPage`, `SupyScanOptions`, `SupyScanError`. |
| `models/ui/` | v1.1 frozen UI-config types — `SupyScannerPalette`, `SupyTopBarConfiguration`, `SupyViewFinderConfiguration`, `SupyUserGuidanceConfiguration`, `SupyActionBarConfiguration` (+ `SupyActionButtonSpec`), `SupyArOverlayConfiguration`, `SupyCameraConfiguration` (+ `SupyScanRange`), sealed `SupyScanUseCase` (+ `SupySingleScanUseCase` / `SupyMultipleScanUseCase` / `SupyFindAndPickUseCase`) and their per-variant configurations (`SupySingleScanUseCaseConfiguration`, `SupyMultipleScanUseCaseConfiguration` (+ `SupyMultipleScanMode`), `SupyFindAndPickUseCaseConfiguration` (+ `SupyExpectedBarcode`)). See `docs/UI_CONFIGURATION.md`. |
| `channel/method_channel.dart` | Single point of `MethodChannel('io.supy.scanner/v1')` access. All native calls go through here. |
| `channel/event_channel.dart` | Per-view EventChannel for barcode detections. |
| `widgets/supy_barcode_scanner_view.dart` | The `StatefulWidget` that composes an `AndroidView`/`UiKitView`, a finder overlay, and slot Stack for header/footer. |
| `widgets/supy_barcode_scanner_controller.dart` | Holds pause/torch/zoom/camera-position state, talks to the per-view MethodChannel. |
| `widgets/supy_barcode_scanner_screen.dart` | v1.1 — full-screen composite (`Scaffold`) that pattern-switches on the sealed `SupyScanUseCase` to wire the correct sheet + result callback. Owns its own controller unless one is supplied. |
| `widgets/supy_ar_overlay.dart` | v1.1 — `CustomPaint` over the preview rendering normalized `[0..1]` bounding boxes + label chips. |
| `widgets/supy_single_scan_confirmation_sheet.dart` | v1.1 — bottom sheet for `SupySingleScanUseCase`. |
| `widgets/supy_multiple_scan_accumulator.dart` + `supy_multiple_scan_sheet.dart` | v1.1 — `ChangeNotifier` (counting/unique modes + debounce) and its collapsible sheet for `SupyMultipleScanUseCase`. |
| `widgets/supy_find_and_pick_accumulator.dart` + `supy_find_and_pick_sheet.dart` | v1.1 — pick-list accumulator (per-row progress capped at `expectedCount`, `isComplete`) and its sheet for `SupyFindAndPickUseCase`. |
| `services/supy_document_scanner.dart` | Static entrypoint `startMultiPage(...)` and `prewarm()`. |
| `services/supy_permissions.dart` | Thin wrapper over `permission_handler` for camera permission. |

### Android layer

| File | Responsibility |
|---|---|
| `SupyScannerPlugin.kt` | `FlutterPlugin` lifecycle, registers `BarcodeScannerViewFactory`, hosts the document MethodCallHandler. |
| `barcode/BarcodeScannerView.kt` | Implements `PlatformView`, builds a `PreviewView` + `LifecycleCameraController`, attaches an `ImageAnalysis` analyzer wired to `BarcodeScanning.getClient(...)`. Streams to EventChannel. |
| `barcode/BarcodeScannerViewFactory.kt` | `PlatformViewFactory` — wires creation params (formats, finder, etc.). |
| `barcode/FormatMapper.kt` | `SupyBarcodeFormat` ↔ ML Kit `Barcode.FORMAT_*` mapping. |
| `document/DocumentScannerLauncher.kt` | Calls `GmsDocumentScanning.getClient(...)` and `startScanIntent(...)`, awaits result via `startActivityForResult`. v1.2: pre-flights `GmsAvailability.isUsable(activity)` and branches to `CameraXDocumentScannerActivity` on non-GMS devices — result pipeline (`PageReencoder` + `OcrRunner`) is shared so wire shape is identical. |
| `document/OcrRunner.kt` | Loops `TextRecognition.getClient(...)` over JPEGs, concatenates results. |
| `document/GmsAvailability.kt` | v1.2 helper wrapping `GoogleApiAvailability.isGooglePlayServicesAvailable(context) == SUCCESS`. Single decision point for "should we route to GMS or to the CameraX fallback?". |
| `document/CameraXDocumentScannerActivity.kt` | v1.2 non-GMS fallback Activity. CameraX `Preview` + `ImageCapture` use cases, tap-to-capture FAB, thumbnail strip with delete, done CTA gated on `pages.isNotEmpty()`. Writes JPEGs to `cacheDir/supy_camx/`, returns URIs via `EXTRA_RESULT_URIS` (ArrayList<String>). Exposes `RESULT_PERMISSION_DENIED` / `RESULT_CAMERA_UNAVAILABLE` sentinel result codes which the launcher maps to `permission_denied` / `camera_unavailable`. PDF output not emitted on this path. |

### iOS layer

| File | Responsibility |
|---|---|
| `SupyScannerPlugin.swift` | `FlutterPlugin` registration; registers `BarcodeScannerViewFactory`; hosts document MethodCallHandler. |
| `barcode/BarcodeScannerPlatformView.swift` | `FlutterPlatformView` wrapping a `UIView` with `AVCaptureVideoPreviewLayer`. Runs `VNDetectBarcodesRequest` from a video output. |
| `barcode/BarcodeScannerViewFactory.swift` | Creation params bridge. |
| `barcode/SymbologyMapper.swift` | `SupyBarcodeFormat` ↔ `VNBarcodeSymbology`. |
| `document/DocumentScannerPresenter.swift` | Presents `VNDocumentCameraViewController` over the Flutter root VC. VisionKit returns each enhanced page at the camera's native resolution; the presenter routes each page through `DocumentEnhancer` (per the requested `filter`, default `color`) and persists it as JPEG at the requested `jpegQuality` (default 95) in `NSTemporaryDirectory()`. |
| `document/DocumentEnhancer.swift` | Core Image + Accelerate post-processing chain that runs on `DispatchQueue.global(qos: .userInitiated)`. The `color` chain flattens illumination (`CIBoxBlur` → divide), lifts midtones via a paper-anchored `CIToneCurve` (endpoint 0.96, NOT 1.0 — preserves paper warmth instead of bleaching to white), and crisps text with `CIUnsharpMask`. `grayscale` adds desaturation; `blackAndWhite` swaps the tone curve for an adaptive threshold; `original` bypasses the chain. |
| `document/OcrRunner.swift` | `VNRecognizeTextRequest` with `recognitionLevel = .accurate`. |

## Platform channel contract

### `io.supy.scanner/v1` (global MethodChannel)

| Method | Args | Returns | Errors |
|---|---|---|---|
| `scanDocument` | `{ maxPages: int, ocrLanguages: [string], jpegQuality: int (0-100), locale: 'en' \| 'ar', palettePrimary: '#RRGGBB', paletteOnPrimary: '#RRGGBB', outputFormat: 'jpg' \| 'png' \| 'pdf' (v1.1), enhanceMode?: 'off' \| 'fast' \| 'balanced' \| 'max' (v1.1), preferredBackend?: 'gms' \| 'cameraX' (v1.2 — Android only, hint), filter?: 'color' \| 'grayscale' \| 'blackAndWhite' \| 'original' (v1.2 — iOS only, default `'color'`; Android ignores) }` | `{ pages: [{ uri: string, width: int, height: int, quality?: 'veryPoor' \| 'poor' \| 'ok' \| 'good' \| 'excellent' (v1.1), qualityScore?: double 0..1 (v1.1), enhancedStages?: int (v1.1 bitmask), enhanceMs?: int (v1.1) }], ocrText: string, pdfUri?: string (v1.1 — only when outputFormat == 'pdf'), resolvedBackend: 'gms' \| 'cameraX' \| 'unknown' (v1.2) }` | `cancelled`, `permission_denied`, `model_unavailable`, `unknown` |
| `scanBarcodesBatch` | `{ formats: [string], maxBatchCount: int (0=unlimited), dedupeWindowMs: int, beep: bool, vibrate: bool }` | `{ items: [{ rawValue: string, format: string }], duplicateCount: int }` | `cancelled`, `permission_denied`, `camera_unavailable`, `unknown` |
| `prewarm` | `{}` | `{}` | `unknown` |
| `parseInvoice` (v1.2 — **experimental**, Phase IXP, iOS-only) | `{ imagePath: string (absolute file path or `file://` URL of an already-captured page) }` | `{ vendor?: string, date?: string, invoiceNumber?: string, currency?: string (ISO 4217), total?: double, tax?: double, lineItems: [{ description: string, amount: double, quantity?: int }], rawText: string }` | `unimplemented` (Android), `unknown` |
| `requestCameraPermission` | `{}` | `{ status: 'granted' \| 'denied' \| 'permanentlyDenied' }` | — |
| `nativeCoreProbe` | `{}` | `{ version: string, abiVersion: int, hasZxing: bool (v1.1), gmsDocumentScannerAvailable: bool (v1.2 — `true` only on Android with usable Play Services + document scanner module) }` | `native_core_unavailable`, `unknown` |
| `getDeviceTier` (v1.1) | `{}` | `{ tier: 'high' \| 'mid' \| 'low' \| 'unknown' }` | — |
| `debugForceTier` (v1.1, debug-only) | `{ tier: 'high' \| 'mid' \| 'low' \| null }` | `null` | `unknown` |

#### Native core C ABI (v1.1)

The shared C++ core in `native/` exposes a stable C ABI consumed by Android JNI, iOS Swift, and (eventually) dart:ffi. The full surface lives in `native/include/supy_scanner_core.h`. Pixel buffers MUST NOT cross dart:ffi — only result structs (decoded payloads, doc page URIs) may.

| Symbol | Purpose |
|---|---|
| `supy_core_version` | Semver string of the native core (e.g. `1.1.0-dev.2`). |
| `supy_core_abi_version` | Integer ABI version (`SUPY_CORE_ABI_VERSION`); platform bridge refuses to load on mismatch. |
| `supy_core_has_zxing` | `1` when build linked zxing-cpp (`SUPY_WITH_ZXING_CPP=ON`); `0` otherwise. Surfaced through `nativeCoreProbe.hasZxing`. |
| `supy_core_decode` | Synchronous decode of a luma frame via zxing-cpp. Returns opaque handle or `NULL`. Caller frees with `supy_core_decode_results_free`. |
| `supy_core_decode_count` / `_text` / `_format` / `_corners` | Result accessors. `text` is UTF-8, `format` is a single `SUPY_FORMAT_*` bit, `corners` is `[x0,y0,…,x3,y3]` in TL/TR/BR/BL pixel space. |
| `supy_core_has_libdmtx` | `1` when build linked libdmtx (`SUPY_WITH_LIBDMTX=ON`); `0` otherwise. |
| `supy_core_locate_datamatrix` | Synchronous Data Matrix **locator** via libdmtx. Returns opaque handle or `NULL`. Returns corners only — actual payload decode runs through `supy_core_decode` on the ROI crop. Locator+decoder split rationale: libdmtx's region search is the most permissive open-source DM finder (catches symbols zxing-cpp misses on noisy/perspective frames); zxing-cpp's decode quality on a clean ROI crop is consistently better than libdmtx's. |
| `supy_core_locate_count` / `_corners` | Result accessors. `corners` is `[x0,y0,…,x3,y3]` in TL/TR/BR/BL pixel space — same convention as `supy_core_decode_corners`. |
| `supy_core_locate_results_free` | Releases a locate-result handle. NULL-safe. |

The decode path is gated end-to-end:
- CMake option `SUPY_WITH_ZXING_CPP` (default OFF) — controls whether zxing-cpp is fetched and linked.
- iOS podspec gate on `ENV['SUPY_SCANNER_ENABLE_ZXING']=='1' || File.directory?('Vendor/ZXing.xcframework')` (see `tools/build_zxing_xcframework.sh`).
- Runtime opt-in via the `useNativeCore` PlatformView arg — platforms only call `supy_core_decode` when `useNativeCore=true`; otherwise the ML Kit / Vision path stays canonical.

#### Enhancement subsystem (v1.1)

Document pages are post-processed by the shared `supy::scanner::enhance` pipeline before persistence / OCR / PDF assembly. The full design lives in [`docs/ENHANCEMENT.md`](./ENHANCEMENT.md); only the architectural surface is summarized here.

| Symbol | Purpose |
|---|---|
| `supy_core_enhance` | Runs the pipeline on a packed RGBA8888 buffer. Returns an opaque handle or `NULL` on invalid input. |
| `supy_core_enhance_rgba` / `_width` / `_height` / `_row_stride` | Output buffer accessors. Buffer is owned by the handle; copy out before freeing. |
| `supy_core_enhance_applied_stages` | Bitmask of stages that ran — see `SUPY_ENHANCE_STAGE_*` in `native/include/supy_scanner_enhance.h`. |
| `supy_core_enhance_verdict` | `OK` / `MARGINAL` / `REJECT`. `REJECT` short-circuits the pipeline (pass-through copy) so callers can re-prompt the user. |
| `supy_core_enhance_quality_score` / `_processing_ms` | Diagnostics surfaced on the per-page result as `qualityScore` / `enhanceMs`. |
| `supy_core_enhance_free` | Releases the handle. NULL-safe. |
| `supy_core_score_page` | Standalone per-page scorer (variance-of-Laplacian + luma). Returns `{ blur_score, quality_score (0..1), bucket }`. Used by the iOS path where `enhanceMode=off` is the default but a quality bucket still has to surface on `SupyDocumentPage`. |
| `supy_core_warp` | Hand-rolled OpenCV-free perspective warp (`supy::scanner::document`). Takes a `supy_warp_input_t` (packed RGBA8888 src + 4 source corners TL,TR,BR,BL in pixel space + `max_long_side` cap), solves the 8-DOF homography (Gaussian elimination on the 8×8 system) and inverse-map bilinear-samples to a flat rect. Returns an opaque handle or `NULL` on NULL input / invalid buffer / degenerate quad. Output size derives from the quad's max edge lengths, clamped to `max_long_side`. |
| `supy_core_warp_rgba` / `_width` / `_height` / `_row_stride` | Warp output accessors. Buffer is owned by the handle; copy out before `supy_core_warp_free`. |
| `supy_core_warp_free` | Releases a warp-result handle. NULL-safe. |

Per-page wire fields: `quality` (`"veryPoor" \| "poor" \| "ok" \| "good" \| "excellent"`) and `qualityScore` (0..1) are added to each entry in the `scanDocument` `pages[]` payload. Both fields are omitted when the JPEG ≥95 + `enhanceMode=off` passthrough skips decode entirely. Bucket thresholds (`40 / 120 / 240 / 480` on the raw blur score) are anchored to the existing reject/marginal gate; `qualityScore = clamp(blurScore / 600, 0, 1)`.

Threading: pipeline runs on a background worker (Android `Executors`, iOS `DispatchQueue.global(qos: .userInitiated)`). Never main thread. Modes (`SUPY_ENHANCE_OFF/FAST/BALANCED/MAX`) come from `SupyDocumentEnhanceMode` on the channel; default is platform-specific (Android `balanced`, iOS `off`). `MAX` is a distinct stack — `BALANCED` plus specular/glare clamp, morphological top-hat flatten, and CLAHE (`SUPY_ENHANCE_STAGE_SPECULAR/TOPHAT/CLAHE`, bits `0x10/0x20/0x40`); it no longer aliases `BALANCED`. See [`docs/ENHANCEMENT.md`](./ENHANCEMENT.md).

#### Document guidance classifier (v1.2)

The document smart-guidance state machine is the C++ class `supy::scanner::document::classify` in `native/document/document_guidance_classifier.{h,cpp}` — a single source of truth that emits one of 12 wire-stable `FrameState` ordinals (`kNoDocument=0` … `kEdgeClipped=11`) plus a live quality score from per-frame metrics, with EMA smoothing, hysteresis exit-margins, min-dwell and priority preemption baked in. It is **not** part of the C ABI in `supy_scanner_core.h`; each platform reaches it through a thin stateful bridge that owns the `GuidanceState` across frames.

- **Android**: JNI shim `nativeGuidanceCreate / Destroy / Reset / Classify` (`supy_scanner_core_jni.cpp`) with the state owned by a Kotlin-held `jlong` handle, wrapped by `SupyNativeCore.guidance*` (`GuidanceFrameMetrics` / `GuidanceConfig` / `GuidanceFrameState`). Consumed by `CameraXDocumentScannerActivity` for auto-snap.
- **iOS**: Obj-C++ instance class `SupyDocumentGuidance` (`ios/Classes/nativecore/SupyNativeCoreBridge.{h,mm}`) heap-allocates the `GuidanceState` in `-init` and frees it in `-dealloc` (ARC-safe equivalent of the Android handle), exposed to Swift as `GuidanceClassifier` (`SupyNativeCore.swift`). The embedded `SupyDocumentScannerView` now drives this classifier: it parses a 19-float `guidanceConfig` from the PlatformView `creationParams`, classifies each frame on the detector's analyzer queue inside `emitFrameMetrics`, and ships the resolved `state`/`liveQualityScore` on the `frame_metrics` payload (the Dart widget consumes `state` and skips its own FSM). `GuidanceClassifier.reset()` runs on `resume` so a re-entered preview starts from `noDocument` rather than a latched state. The launcher-style auto-snap loop in `DocumentScannerPresenter` (the VisionKit modal flow, distinct from the embedded view) is still VisionKit — not wired into the classifier.
- **iOS/Android embedded-view divergence (temporary)**: the iOS embedded view classifies natively (above); the Android embedded `SupyDocumentScannerView` still runs the Dart `SupyDocumentStateMachine` on raw `frame_metrics` (it emits no `state`). Routing Android's embedded view through its JNI `GuidanceClassifier` for full parity is a deferred follow-up. Until then iOS gets the C++ exit-margin hysteresis (so glare/occluded/handShake un-latch correctly) while Android retains the three documented Dart-FSM hysteresis quirks.

Both bridges pack config as a 19-float array in `GuidanceConfig.toFloatArray()` order and return `[stateOrdinal, liveQualityScore]`; the order is fixed and cross-referenced in the Kotlin/Swift packers and the JNI/Obj-C++ unpackers so they cannot drift. The 19th float is `maxCenterOffset` (the off-center half-extent ceiling); Dart sends the sentinel `-1.0` when `centerGuidanceEnabled` is `false`, and the C++ classifier gates off-center detection on `maxCenterOffset > 0`. Off-center is a quick-clear-family state (`kOffCenter`, wire ordinal 12) — while in-state the ceiling is *raised* to `maxCenterOffset * (1 + exitMargin)` so the recenter prompt doesn't re-arm on hand jitter. `perCornerStability` is length 0 (hold prior occlusion judgement) or 4 (TL/TR/BR/BL). Parity is pinned by the host gtest (C++↔Dart), the Dart FSM tests, and `ios/Tests/nativecore/SupyGuidanceClassifierTests.swift` (Swift→Obj-C++→C++).

### `io.supy.scanner/v1/barcode/<viewId>` (per-view MethodChannel)

| Method | Args | Returns |
|---|---|---|
| `pause` | — | `{}` |
| `resume` | — | `{}` |
| `setTorch` | `{ on: bool }` | `{}` |
| `setFormats` | `{ formats: [string] }` | `{}` |
| `setZoom` | `{ factor: double }` | `{}` |
| `flipCamera` | `{}` | `{ position: 'back' \| 'front' }` |
| `setMinFocusDistanceLock` | `{ on: bool }` | `{}` |

### `io.supy.scanner/v1/barcode/<viewId>/events` (EventChannel)

Stream of:
- `{ type: 'detection', items: [{ rawValue, format, boundingBox: { left, top, width, height } | null }] }`
- `{ type: 'preview_started', flashAvailable: bool }`
- `{ type: 'thermal', state: 'nominal' | 'light' | 'fair' | 'moderate' | 'serious' | 'critical', paused: bool, throttled: bool }`
- `{ type: 'idle_pause' }`
- `{ type: 'idle_resume' }`
- `{ type: 'torch_idle_suggested' }`
- `{ type: 'error', code, message }`

`idle_pause` / `idle_resume` are emitted when the luma-variance idle detector
flips state on MID/LOW tier devices (HIGH tier disables idle pause). While
idle, frames are dropped before any ML Kit / Vision work — the camera keeps
running but barcode detection is skipped until motion reappears.

The `thermal` event is emitted whenever the OS thermal state changes. When
`paused` is true the analyzer has stopped processing frames (Android API 29+
`THERMAL_STATUS_SEVERE`+; iOS `.serious`+). When `throttled` is true the
analyzer is running at a reduced frame cadence. `nominal`/`serious`/`critical`
are emitted by both platforms; `light`/`moderate` are Android-only; `fair` is
iOS-only. Android `THERMAL_STATUS_SEVERE` is normalized to wire-string
`"serious"` so consumers branch on a single vocabulary. Consumers should
treat unknown strings as "no concern".

### `io.supy.scanner/v1/document/<viewId>` (per-view MethodChannel)

Backs `SupyDocumentScannerView` — the embedded streaming guidance preview
(distinct from the launcher-style `scanDocument` flow above).

| Method | Args | Returns |
|---|---|---|
| `pause` | — | `{}` |
| `resume` | — | `{}` |
| `setTorch` | `{ on: bool }` | `{}` |
| `captureAndRectify` | — | `{ path: String, widthPx: Int, heightPx: Int, quad: List<{x, y}> }`. **Platform divergence (geometry-equivalent, flagged intentionally):** iOS applies `CIPerspectiveCorrection` to the last smoothed quad and writes a JPEG to `NSTemporaryDirectory()`; Android (Sprint 4) decodes the full-res still, scales the normalized quad into pixel space, and routes through the shared hand-rolled native warp (`supy_core_warp` → JNI `nativeWarpPerspective`), then `PageReencoder.reencodeBitmap`. Routing iOS through the shared native warp for pixel-identical output is deferred (optional per the Sprint 4 plan). When no quad is detected, both platforms return `captureUnsupported` so the Dart widget falls back to `captureFullFrame`. Errors: `captureUnsupported`, `captureFailed`, `unknown`. |
| `captureFullFrame` | — | `{ path: String, widthPx: Int, heightPx: Int }`. iOS: triggers `AVCapturePhotoOutput`, writes JPEG to `NSTemporaryDirectory()`. Android: triggers CameraX `ImageCapture`, writes JPEG to `context.cacheDir`. Always available on both platforms. Errors: `captureFailed`, `unknown`. |

### `io.supy.scanner/v1/document/<viewId>/events` (EventChannel)

Stream of:
- `{ type: 'preview_started', flashAvailable: bool }`
- `{ type: 'frame_metrics', quad: [{x, y}, …] | [], coverageRatio: double, tiltDegrees: double, meanLuma: double, blurScore: double, clipsEdge: bool, quadStability?: double, interiorVariance?: double, centerOffsetX?: double, centerOffsetY?: double, state?: int, liveQualityScore?: double }`
- `{ type: 'error', code, message }`

`quad` is normalized to preview coordinates with a **top-left origin**. An
empty `quad` signals "no document detected" — the Dart state machine maps
that to `noDocument`. `centerOffsetX`/`centerOffsetY` are the document
centroid's signed half-extent offset from frame center (`(centroid − 0.5) × 2`;
+X = right, +Y = below) — consumed by the off-center recenter prompt. The
optional `state` is the wire-stable `FrameState`
ordinal (0–12, where 12 = `offCenter`) when the platform classifies the frame
natively; the Dart
widget maps it via `kSupyDocumentFrameStateWireIndex` and uses it directly,
falling back to the Dart `SupyDocumentStateMachine` only when `state` is
absent. **iOS embedded view emits `state`/`liveQualityScore`** (classified by
the C++ `GuidanceClassifier` — see below); the **Android embedded view does
not yet** and stays on the Dart FSM (tracked follow-up, see the guidance
classifier section). Out-of-range ordinals are ignored, so a stale native
build degrades to the Dart FSM rather than crashing. On iOS the quad is sourced from
`VNDetectDocumentSegmentationRequest` (iOS 17+) with a
`VNDetectRectanglesRequest` fallback on iOS 16. On Android the quad is
sourced from the native C++ document-edge detector (`supy_scanner_core` JNI)
when available, with a graceful fallback to luma/blur-only metrics on load
failure.

`quadStability` (Double, 0.0–1.0) — 1 = no corner drift across the last 6
frames of the stability window. Absent when `quad` is empty. Platforms that
have not yet implemented per-corner tracking may omit the key; Dart defaults
to `0.0`.

`interiorVariance` (Double, ≥ 0) — variance-of-Laplacian inside the detected
quad bounding box (downsampled). High values indicate textured surfaces
(printed documents); low values indicate smooth surfaces (laptop screens
showing a single image). Absent when `quad` is empty.

### `io.supy.scanner/v1/document_view` PlatformView

View-type id registered by both platforms; no creation params in v1.

### `io.supy.scanner/v1/barcode` PlatformView creation params

Passed once at view construction; serialized from `SupyBarcodeScanOptions.toWire()`.

| Key | Type | Notes |
|---|---|---|
| `formats` | `[string]` | Active symbologies (wire names from `SupyBarcodeFormat`). |
| `useScanWindow` | `bool` | Restrict detection to the on-screen finder. |
| `findBarcodeAtCenter` | `bool` | Report only the barcode closest to preview center per pass. |
| `useNativeCore` | `bool` | v1.1 — route frames through the native CV core before ML Kit / Vision. |
| `camera` | `{ initialZoom: double, minFocusDistanceLock: bool, scanRange: 'standard' \| 'close' \| 'extended' }` | Applied at preview-start. Android honors `initialZoom` via `setZoomRatio`; iOS honors `initialZoom` (clamped) and engages `.near` `autoFocusRangeRestriction` when `minFocusDistanceLock` is true or `scanRange == 'close'`. `scanRange == 'extended'` and Android close-focus are deferred to the v1.1 native CV core. |

## Threading

- **Barcode detection** runs on a background thread on both platforms. Detection callbacks are marshalled to Flutter via EventChannel (which already hops to the main thread before delivery).
- **OCR** runs on a background dispatch queue (iOS) / coroutine (Android).
- **Document JPEG writes** happen off the main thread; the channel callback fires after all writes complete.

### Lifecycle invariants

Thread contracts are documented in-source (H1-03):
- **Android** — `androidx.annotation.@MainThread` on `PlatformView.dispose()`, `MethodChannel.MethodCallHandler.onMethodCall(...)`, and host-`Activity.onCreate(...)`. `@WorkerThread` on every `ImageAnalysis.Analyzer.analyze(ImageProxy)` override (CameraX runs analyzers on a dedicated worker thread, never main).
- **iOS** — `dispatchPrecondition(condition: .onQueue(.main))` at the entry of MethodChannel handlers (`SupyBarcodeScannerView.handle`, `SupyDocumentScannerView.handle`, `DocumentScannerPresenter.present`) and `UIViewController.viewDidLoad`. `dispatchPrecondition(condition: .notOnQueue(.main))` immediately before each `VNImageRequestHandler.perform(...)` call. `AVCaptureSession.startRunning/stopRunning` are dispatched via `sessionQueue.async { ... }` — never from main.

## Permissions

- **Camera (iOS):** `NSCameraUsageDescription` required in host app's `Info.plist`. Documented in `docs/MIGRATION.md`.
- **Camera (Android):** `android.permission.CAMERA` declared in plugin's `AndroidManifest.xml`. Runtime request handled in Dart via the existing `permission_handler` integration the retailer already uses.

## Error model

All native errors surface as `PlatformException` and are caught in `channel/method_channel.dart`, then wrapped into `SupyScanError` with a stable `code`:

| Code | Meaning |
|---|---|
| `cancelled` | User cancelled the scan (back button, swipe down). |
| `permission_denied` | Camera permission not granted. |
| `camera_unavailable` | No usable camera (simulator with no host camera). |
| `model_unavailable` | ML Kit Document Scanner model not downloaded and no network. |
| `format_unsupported` | Requested barcode format not supported on this platform. |
| `unknown` | Anything else — `message` carries the platform's description. |

## Testing layers

Three independent test layers run on every PR via `.github/workflows/ci.yml`:

| Layer | Where | Runner | Scope |
|---|---|---|---|
| Dart | `test/` | `flutter test` (job `analyze-and-test`) | Models, channel boundary (`TestDefaultBinaryMessenger`), document state machine, widget paint behavior. |
| Android native | `android/src/test/kotlin/` | `./gradlew :supy_scanner:testDebugUnitTest` from `example/android/` (job `android-native-test`) | JVM unit tests. Robolectric is used where ML Kit `Barcode.FORMAT_*` constants need to resolve. No emulator. |
| iOS native | `ios/Tests/` | `pod lib lint` against `s.test_spec 'Tests'` (job `ios-native-test`) | XCTest unit suite hosted by the podspec test_spec. No simulator. |

Out of scope for the three jobs above: any class that touches `AVCaptureSession`, CameraX, ML Kit detector instances, or a real `PlatformView` — those need instrumented/UI tests, tracked under `TODO.md` H2-05.

The Android job scaffolds `example/android/` at CI time via `flutter create --platforms=android .` because that directory is intentionally not committed.
