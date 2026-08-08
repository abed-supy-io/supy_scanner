# Architecture

How `supy_scanner` is wired across Dart and the two native plugins, and the
**canonical channel surface** — every MethodChannel method, its argument keys,
and its return shape. This table is the source of truth referenced by
`CLAUDE.md` and the `supy-scanner:add-channel-method` skill.

Keep it in sync with, in the same PR:

- `lib/src/channel/supy_scanner_channel.dart` — the global method channel wrapper.
- `lib/src/widgets/supy_document_scanner_controller.dart` /
  `lib/src/widgets/supy_barcode_scanner_controller.dart` — per-view method channels.
- `lib/src/channel/supy_document_event_channel.dart` /
  `lib/src/channel/supy_event_channel.dart` — per-view EventChannels.
- `android/src/main/kotlin/io/supy/scanner/**` and `ios/Classes/**` — the native handlers.

## Layers

```
retailer app
   │  (Scanbot-compat façade lives in compat/)
   ▼
lib/ public API  ──  Supy* Dart types, streams, ChangeNotifier controllers
   │
lib/src/channel/ ──  the ONLY place Map<String,dynamic> / dynamic is allowed
   │                 (arg encoding + PlatformException → SupyScanError)
   ▼
MethodChannel / EventChannel  ── io.supy.scanner/v1  (versioned wire)
   │
native plugins
   ├─ Android  io.supy.scanner.*  (CameraX + ML Kit, LifecycleCameraController)
   └─ iOS      SupyScanner        (AVFoundation + Vision)
        │
        └─ shared C++ core (core/, zxing-cpp)  ── SUPY_CORE_ABI_VERSION 5
```

Rules that constrain everything below (see `CLAUDE.md`):

- The channel name is **versioned** — `io.supy.scanner/v1`. A `v2` is a parallel
  surface, never an in-place mutation of `v1`.
- No `dynamic` / `Map<String, dynamic>` leaks out of `lib/src/channel/`.
- Detection never blocks the main thread (Android analyzer thread; iOS
  background `DispatchQueue`, marshalled to main only at the result boundary).

## Channel topology

| Channel | Name | Kind | Scope |
|---|---|---|---|
| Global methods | `io.supy.scanner/v1` | MethodChannel | Process-wide one-shots (full-screen scanners, probes, permissions). |
| Document view methods | `io.supy.scanner/v1/document/<viewId>` | MethodChannel | Per embedded document PlatformView. |
| Document view events | `io.supy.scanner/v1/document/<viewId>/events` | EventChannel | Per-view frame/guidance stream. |
| Barcode view methods | `io.supy.scanner/v1/barcode/<viewId>` | MethodChannel | Per embedded barcode PlatformView. |
| Barcode view events | `io.supy.scanner/v1/barcode/<viewId>/events` | EventChannel | Per-view live barcode stream. |
| Data-capture view methods | `io.supy.scanner/v1/datacapture/<viewId>` | MethodChannel | Per embedded live text-pattern PlatformView. |
| Data-capture view events | `io.supy.scanner/v1/datacapture/<viewId>/events` | EventChannel | Per-view per-frame OCR-geometry stream. |

PlatformView type IDs (registered in the view factories):
`io.supy.scanner/v1/document_view`, `io.supy.scanner/v1/barcode_view`,
`io.supy.scanner/v1/datacapture_view`.

## Global method table — `io.supy.scanner/v1`

Wrapper: `SupyScannerChannel` (`lib/src/channel/supy_scanner_channel.dart`).

| Method | Arg keys | Returns | Dart wrapper |
|---|---|---|---|
| `scanDocument` | `SupyDocumentScanOptions.toWire()` | `Map` → `SupyDocumentData` (or `null` if cancelled) | `scanDocument()` |
| `scanBarcodesBatch` | `SupyBatchBarcodeScanOptions.toWire()` | `Map` → `SupyBatchBarcodeResult` (or `null` if cancelled) | `scanBarcodesBatch()` |
| `importDocumentImage` | `SupyDocumentScanOptions.toWire()` (optional; `null` → native defaults) | `{uri: String, width: int, height: int, quality?: String, qualityScore?: double}` → `SupyDocumentPage` (or `null` if the picker was dismissed) | `importDocumentImage([options])` |
| `recognizeText` | `{imagePath: String, languages: List<String>, includeElements: bool}` | `{fullText: String, blocks: [{text, boundingBox, lines: [{text, boundingBox, elements: [{text, boundingBox}]}]}]}` → `SupyRecognizedText` | `recognizeText()` |
| `decodeImage` | `{imagePath: String, formats: List<String>, useNativeCore: bool}` | `[{rawValue: String, format: String, boundingBox?: {left, top, width, height}}, …]` → `List<SupyBarcode>` | `decodeImage()` |
| `prewarm` | — | `void` | `prewarm()` |
| `nativeCoreProbe` | — | `{version: String, abiVersion: int, gmsDocumentScannerAvailable: bool}` → `SupyNativeCoreProbe` | `nativeCoreProbe()` |
| `getDeviceTier` | — | `{tier: 'high'\|'mid'\|'low'}` → `SupyDeviceTier` | `getDeviceTier()` |
| `debugForceTier` | `{tier: 'high'\|'mid'\|'low'\|null}` | `void` (debug builds only; no-op in release) | `debugForceTier()` |
| `requestCameraPermission` | — | `{status: 'granted'\|'denied'\|'permanentlyDenied'}` → `SupyCameraPermissionStatus` | `requestCameraPermission()` |

### `scanDocument` result shape

```
{
  pages: [ { uri, width, height, quality?, qualityScore? }, … ],
  ocrText: String,
  resolvedBackend: 'gms' | 'cameraX',   // iOS always 'gms'
  pdfUri?: String,                      // present for outputFormat 'pdf' and 'searchablePdf'
  tiffUri?: String,                     // present only for outputFormat 'tiff'
}
```

`pages[].uri` is always a JPG (or PNG for `outputFormat: png`) regardless of the
assembled artifact — `tiff`/`searchablePdf` still persist per-page JPGs and add
the assembled file on `tiffUri`/`pdfUri`. v1.2 / Phase DC8:
- `outputFormat: 'tiff'` → multi-page baseline TIFF. iOS uses ImageIO
  (`CGImageDestination`, `public.tiff`); Android uses the pure-Kotlin
  `TiffAssembler` (uncompressed baseline RGB — no `libtiff`, no ABI bump).
- `outputFormat: 'searchablePdf'` → a PDF carrying an invisible (alpha-0 /
  `UIColor.clear`) but selectable OCR text layer, built from a single OCR pass's
  word boxes. Surfaced on `pdfUri` (same field as image-only `pdf`). GMS's
  native PDF is never used here — the searchable PDF is always self-assembled
  from the page images + word boxes.

### `scanDocument` nested `processing` args (Phase DPX)

`SupyDocumentScanOptions.toWire()` may carry an optional nested `processing` map
that tunes the shared native `DocumentProcessor` enhancement pipeline. The key is
**omitted entirely** when the caller leaves `SupyDocumentScanOptions.processing`
null — native then falls back to `DocumentProcessingOptions.default` (the full
pipeline), so existing Scanbot-compat call sites are unchanged and drop-in-safe.

```
processing: {
  detectDocument: bool,          // stage 1: document detection
  perspectiveCorrection: bool,   // stage 3: perspective warp from the quad
  autoCrop: bool,                // stage 4: crop to the document + cropMargin
  cropMargin: double,            // fractional margin kept around the crop (0.02 default)
  deskew: bool,                  // stage 5: small-angle straighten
  shadowRemoval: bool,           // stage 6: illumination flatten
  backgroundWhitening: bool,     // stage 7: color-safe paper whitening
  denoise: bool,                 // stage 10: edge-preserving denoise
  sharpen: bool,                 // stage 10: halo-safe unsharp mask
  maxDimension: int,             // stage 9: longest-edge export cap in px (2200 default; 0 = no resize)
  enhancement?: 'color'|'grayscale'|'blackAndWhite'|'original',  // stage 8 filter; omitted → falls back to outer `filter`
  quality?: int,                 // JPEG quality; omitted → falls back to outer `jpegQuality`
}
```

Native parsing lives in `DocumentProcessor.parse(_:fallbackFilter:fallbackQuality:)`
(iOS): a missing `processing` map or any missing key falls back to `.default`;
`enhancement`/`quality` fall back to the top-level `filter`/`jpegQuality` when
absent. The same nested block is accepted by the embedded document-view methods
`captureAndRectify` / `captureFullFrame` (see the document view method table).

### `decodeImage` result shape

A one-shot, camera-less decode over a file already on disk — the deterministic
counterpart to the live `SupyBarcodeScannerView` (used by the example-app
benchmark to decode a fixed fixture set identically across libraries). Each
element is the same wire shape a live detection emits
(`DetectedBarcode.toMap()` on iOS; `emitDetections` on Android):

```
[ { rawValue: String, format: String, boundingBox?: {left, top, width, height} }, … ]
```

`boundingBox` is in **source-image pixel space, origin top-left** (an empty list
means no barcode of a requested format was found — never `null`). `format`
defaults to the ML Kit (Android) / Vision (iOS) decoder; `useNativeCore: true`
switches to the bundled zxing-cpp core, which covers the full 18-format set
(including the five native-core-only symbologies) and applies `tryHarder`.
Falls back to the platform decoder when the core is not linked into the build.

## Document view method table — `io.supy.scanner/v1/document/<viewId>`

Wrapper: `SupyDocumentScannerController`.

| Method | Arg keys | Returns |
|---|---|---|
| `pause` | — | `void` |
| `resume` | — | `void` |
| `setTorch` | `{on: bool}` | `void` |
| `captureAndRectify` | optional nested `processing` map (see `scanDocument`) | `Map` → `SupyDocumentCapture` (perspective-warped JPEG) |
| `captureFullFrame` | optional nested `processing` map (see `scanDocument`) | `Map` → `SupyDocumentCapture` (no rectification fallback) |

Native declines a capture with `PlatformException(code: 'UNIMPLEMENTED')`, which
the controller maps to `StateError('captureUnsupported: …')`.

## Shared document-processing pipeline (Phase DPX)

Both iOS document paths — the VisionKit full-screen scanner
(`DocumentScannerPresenter`) and the embedded AVFoundation PlatformView
(`SupyDocumentScannerView`) — funnel their captured frames through one shared
`DocumentProcessor` enum so enhancement is identical regardless of entry point.
`DocumentProcessor` is a decode-once/encode-once orchestrator over the 11-stage
pipeline; the per-stage Core Image work lives in `DocumentEnhancer` (illumination
flatten, tone curve, unsharp mask, color-safe whitening, Lanczos resize, denoise,
and Accelerate-backed Sauvola binarization for the B&W filter).

| Entry point | Native caller | When |
|---|---|---|
| `DocumentProcessor.process(_:seedQuad:analyzerSize:options:)` | VisionKit pages; embedded `captureFullFrame` | Full pipeline incl. detect + perspective warp. |
| `DocumentProcessor.enhanceOnly(_:options:)` | Embedded `captureAndRectify` | Enhance + resize tail only; the caller's `DocumentRectifyPipeline` quad stays authoritative, so detection/warp are skipped. |
| `DocumentProcessor.render(_:like:context:)` | Internal fallback | Encode a `CIImage` back to `UIImage` with no enhancement. |

Options are parsed from the nested `processing` wire map by
`DocumentProcessor.parse(_:fallbackFilter:fallbackQuality:)`; a null map yields
`DocumentProcessingOptions.default` (full pipeline). All heavy Core Image work
runs off the main thread on `DispatchQueue.global(qos: .userInitiated)` and is
marshalled to main only at the `FlutterResult` boundary, and all filters share
`DocumentEnhancer.sharedContext` (one `CIContext`).

Capture resolution (Phase DPX): the embedded view's `AVCaptureSession` uses
`sessionPreset = .photo` and opts into the device's
`supportedMaxPhotoDimensions` via `photoOutput.maxPhotoDimensions` /
`AVCapturePhotoSettings.maxPhotoDimensions`, so the smart-resize stage
(`maxDimension`) down-samples from a full-resolution source rather than a
preview-grade frame. These APIs are all available at the iOS 16 deployment
target — no `if #available(iOS 17)` branch.

### Android side (Phase DPX)

Android reaches parity in pure Kotlin (no C++/ABI change). Detection,
perspective correction and cropping happen **upstream** — GMS's document scanner
(`scanDocument`) or the `CameraX*` fallback / embedded `DocumentRectifyPipeline`
(`captureAndRectify`) own the quad and the warp. The nested `processing` map is
parsed once by `DocumentProcessingOptions.parse(...)`
(`document/DocumentProcessingOptions.kt`), the shared parse point for the
launcher (`DocumentScannerLauncher`, both GMS and CameraX result paths) and the
embedded view (`SupyDocumentScannerView.rectifyCapturedStill`).

The shared tail runs in `PageReencoder`: **smart resize (`maxDimension`) →
native enhance → output `filter`** (color = keep enhanced pixels, grayscale =
Rec.601 luma, blackAndWhite = global Otsu threshold, original = bypass). The
native enhance is the single bundled `SupyNativeCore` `EnhanceMode`, not
per-stage filters, so `shadowRemoval`/`backgroundWhitening`/`denoise`/`sharpen`
collapse onto it: all-off (or the `original` filter) → `EnhanceMode.OFF`, else
the base mode. The upstream `detectDocument`/`perspectiveCorrection`/`autoCrop`/
`cropMargin`/`deskew` fields are parsed for wire parity but owned by GMS and not
individually toggleable. Heavy decode/warp/enhance/encode run off-main
(`rectifyExecutor` / ML Kit executors); the result is posted back via
`mainHandler`.

**Known gap:** the embedded `captureFullFrame` fast path returns the raw frame
(`{path, widthPx, heightPx}`) **without** the `processing` tail — it's the
no-rectification fallback. Callers wanting enhanced/resized output on Android
must use `captureAndRectify` (or `scanDocument`).

## Barcode view method table — `io.supy.scanner/v1/barcode/<viewId>`

Wrapper: `SupyBarcodeScannerController`.

| Method | Arg keys | Returns |
|---|---|---|
| `pause` | — | `void` |
| `resume` | — | `void` |
| `setTorch` | `{on: bool}` | `void` |
| `setZoom` | `{factor: double}` | `{zoom: double}` (clamped applied value) |
| `flipCamera` | — | `{position: 'back'\|'front'}` |
| `setFormats` | `{formats: List<String>}` (wire format names) | `void` |
| `setMinFocusDistanceLock` | `{on: bool}` | `void` (native may decline with `unsupported_operation`) |

## Data-capture view method table — `io.supy.scanner/v1/datacapture/<viewId>`

Wrapper: `SupyTextPatternScannerController`.

| Method | Arg keys | Returns |
|---|---|---|
| `pause` | — | `void` |
| `resume` | — | `void` |
| `setTorch` | `{on: bool}` | `void` |

No barcode-only controls (zoom/flip/formats/focus) — the data-capture view is a
plain OCR-geometry preview. Pattern matching is pure Dart
(`SupyTextPatternMatcher`), so there is no native `setPatterns`.

## EventChannel payloads

All three event streams ship native geometry; Dart owns the interpretation
(state machine, matcher). Payloads are `Map`s decoded in
`lib/src/channel/supy_*_event_channel.dart`.

- **Document** (`…/document/<viewId>/events`) → typed as `SupyDocumentEvent` in
  `supy_document_event_channel.dart`. Event `type`s:
  - `preview_started` — `{flashAvailable: bool}`.
  - `error` — `{code: 'permission_denied'|'camera_unavailable'|'unknown', message: String}`.
  - `frame_metrics` — one detector frame. Native ships **raw measurement only**;
    Dart owns classification into `SupyDocumentFrameState` (+ `SupyDocumentNudge`)
    via `SupyDocumentStateMachine`, decoding the keys below into
    `SupyDocumentFrameMetrics`. This is the **live-guidance signal contract**
    (D3-1) — the five aim signals map to `quad` (document outline), `blurScore`
    (sharpness), `meanLuma` (too-dark), `coverageRatio` (distance/too-far), and
    `clipsEdge` (in-frame). All keys are optional; a missing key defaults per the
    table so a stale native build never crashes the consumer.

    | Key | Type | Range | Meaning |
    |---|---|---|---|
    | `quad` | `[{x,y}]` | 4 pts, `[0..1]` | Document outline, TL/TR/BR/BL. Absent/≠4 → empty (no document). |
    | `coverageRatio` | `num` | `[0..1]` | Quad area ÷ preview area. **Distance signal.** |
    | `tiltDegrees` | `num` | `≥0` | Tilt from head-on; `0` is square. |
    | `meanLuma` | `num` | `[0..255]` | Mean luma inside the quad. **Too-dark signal.** |
    | `blurScore` | `num` | `≥0` | Variance-of-Laplacian; higher = sharper. **Sharpness signal.** |
    | `clipsEdge` | `bool` | — | Quad touches the preview edge. **In-frame signal.** |
    | `quadStability` | `num` | `[0..1]` | Quad drift over recent frames; `1` = rock-solid. |
    | `interiorVariance` | `num` | `≥0` | Texture inside the quad; rejects blank surfaces. |
    | `glareRatio` | `num` | `[0..1]` | Specular-highlight fraction inside the quad. |
    | `cornerVelocity` | `num` | `≥0` | Normalized vertex motion vs. previous frame. |
    | `centerOffsetX` | `num` | `[-1..1]` | Signed horizontal centroid offset; `+` = right of center. |
    | `centerOffsetY` | `num` | `[-1..1]` | Signed vertical centroid offset; `+` = below center. |
    | `perCornerStability` | `[num]` | 4×`[0..1]` | Per-corner steadiness, order matches `quad`. |
    | `liveQualityScore` | `num?` | `[0..1]` | **Optional** aggregate; C++-classifier only. iOS emits, Android omits (→ `null`). |
    | `state` | `int?` | wire index | **Optional** native classification ordinal (`kSupyDocumentFrameStateWireIndex`). iOS emits; Android omits → Dart FSM classifies. Out-of-range → ignored. |

    The two optional derived fields (`state`, `liveQualityScore`) are an
    iOS-only native-classification fast path; the raw signals above are at full
    iOS/Android parity. Reconciling the two classifiers so guidance *state* is
    identical on both platforms is D3-2, not part of this raw-signal contract.
- **Barcode** (`…/barcode/<viewId>/events`) → decoded `SupyBarcode` frames.
- **Data-capture** (`…/datacapture/<viewId>/events`) → `SupyDataCaptureEvent`
  (decoded in `supy_datacapture_event_channel.dart`). Event `type`s:
  - `preview_started` — `{flashAvailable: bool}`.
  - `frame_text` — the full `SupyRecognizedText` tree
    (`{fullText, blocks: [{text, boundingBox, lines: [{text, boundingBox,
    elements: [{text, boundingBox}]}]}]}`, boxes normalized `[0..1]`,
    top-left origin) — identical shape to `recognizeText`. Dart runs the
    regex matcher over it → `SupyTextPatternMatch`.
  - `error` — `{code: 'permission_denied'|'camera_unavailable'|'unknown', message: String}`.

  Android runs ML Kit `TextRecognizer` on the analyzer thread (Latin-only — no
  Arabic); iOS runs `VNRecognizeTextRequest` per frame on a background queue
  (covers `ar`). See `docs/MIGRATION.md`.

## Error model

Native failures cross as `PlatformException`; `SupyScannerChannel._wrap`
translates the `code` into a `SupyScanErrorCode` (see
`lib/src/models/supy_scan_error.dart`). Every native handler must use one of
these wire codes:

| Wire code | `SupyScanErrorCode` | Meaning |
|---|---|---|
| `cancelled` | `cancelled` | User dismissed the scanner without a result. |
| `permission_denied` | `permissionDenied` | Camera permission denied by the user. |
| `camera_unavailable` | `cameraUnavailable` | No usable camera on the device. |
| `model_unavailable` | `modelUnavailable` | A required on-device model (OCR / doc scanner) is missing. |
| `format_unsupported` | `formatUnsupported` | A requested barcode format isn't supported on this platform. |
| *(any other)* | `unknown` | Catch-all for unexpected native failures. |

## Adding a channel method

Follow `supy-scanner:add-channel-method`. In short, in one PR: add the row to
this table, the typed Dart wrapper in `lib/src/channel/supy_scanner_channel.dart`,
**both** native handlers (`SupyScannerPlugin.kt` `when (call.method)` + the iOS
`FlutterMethodChannel` handler), and a mocked Dart test in
`test/channel/supy_scanner_channel_test.dart`. Never bump the `v1` channel name
for an additive method.

## iOS build integration — CocoaPods (default) + Swift Package Manager

The plugin ships **two parallel iOS build paths**; both compile the same
first-party sources, no third-party or paid SDK either way.

- **CocoaPods** (`ios/supy_scanner.podspec`) — the default, still fully
  supported.
- **Swift Package Manager** (`ios/supy_scanner/Package.swift`) — opt-in, added
  because Flutter now warns that plugins without SPM support will break once SPM
  becomes mandatory. SPM forbids mixing Swift and C/C++/ObjC in one target, so
  the manifest uses a **2-target split**: a clang target `supy_scanner_objc`
  (native core + ObjC bridge; `publicHeadersPath: "bridge"`; C++17; header
  search paths into `native/{include,barcode,document,quality,enhance}`) and a
  Swift target `supy_scanner` (the plugin surface incl. `SupyScannerPlugin`,
  depending on the clang target + the Flutter framework). The product is
  `.library(name: "supy-scanner", targets: ["supy_scanner"])`; the package
  `name` must stay `supy_scanner` (Flutter's umbrella-naming contract). Platform
  floor is `.iOS("16.0")`, matching the deployment target — a consuming app must
  therefore set `IPHONEOS_DEPLOYMENT_TARGET ≥ 16.0` (the example app does).

**Local `path:`-dependency caveat.** SwiftPM derives a package's identity from
its **checkout folder basename**. If the checkout folder is dash-named
(`supy-scanner`) while the package `name` is underscore (`supy_scanner`), a local
`path:` example build fails to resolve:

> unable to override package 'supy_scanner' because its identity 'supy-scanner'
> doesn't match override's identity (directory name) 'supy_scanner'

Real consumers (git / hosted deps) land in the pub-cache under `supy_scanner…`
and are **unaffected**. Only local `path:` builds are — so for those the
**checkout folder basename must equal the package name `supy_scanner`**.
