# Document Scanner — Smart Guidance & Interface Polish

**Date:** 2026-06-14
**Owner:** abed@supy.io
**Scope:** Embedded `SupyDocumentScannerView` only. System VisionKit/GMS launchers untouched.
**Status:** Draft — pending user review.

## 1. Problem

The current embedded document scanner does not feel "smart" against the Scanbot baseline it replaces. Three concrete failure modes:

1. **Android has no edge detection.** `DocumentFrameAnalyzer.kt` emits luma + blur only; `quad` is always empty. The Dart state machine therefore degenerates to `noDocument` / `tooDark` / `blurry` and the overlay never shows a found document. The downstream FSM, smoother, and overlay pipeline are wasted.
2. **iOS detector is too permissive.** A laptop screen presenting any rectangular content reads as a document (false positive; see 2026-06-14 screenshot, "Orientation mismatch" pinned on a laptop). `VNDetectRectanglesRequest` uses default thresholds and no aspect/interior gate.
3. **No auto-snap.** `captureAndRectify` is stubbed on both platforms, so the FSM can reach `ready` but nothing fires. The user has to tap manually, and there is no visual countdown cue confirming the system "saw" the document.

Secondary gap — the overlay is a single full-quad outline + pill hint, lacking the corner reticles, ring countdown, capture flash, and copy register that make Scanbot's flow feel responsive.

## 2. Non-goals

- VisionKit / GMS launcher polish (the user picked "embedded view only").
- Sprint 7 native quality scorer (per-page DoQA gate).
- Sprint 8 owned multi-page review screen.
- Android `captureAndRectify` body — waits on Sprint 4 `warpPerspective` in `supy_scanner_core`. iOS lands now.
- Any cloud OCR, paid SDK, or new channel-version bump.

## 3. Architecture

### 3.1 Android edge detection — native C++ in `supy_scanner_core`

Implement a dedicated document-edge detector in the existing JNI-bridged C++ core. `android/src/main/cpp/supy_scanner_core_jni.cpp` already loads via `SupyNativeCore.kt` (Sprint 1 of the v1.1 plan landed the scaffold). New unit:

```
supy_scanner_core/
  document_edge_detector.{h,cpp}   // pure C++, no Android deps
  supy_scanner_core_jni.cpp        // + new Java_..._detectQuad binding
```

**Pipeline (per analyzer frame):**
1. JNI receives the Y plane (`ByteBuffer` direct), width, height, row stride.
2. Center-crop + bilinear downsample to a fixed working width (~256px long-edge). Bounds analyzer cost at ~1.6ms on a mid-tier device.
3. Gaussian blur (3×3 separable) → Sobel gradient magnitude.
4. Adaptive Canny thresholds derived from gradient median (Otsu-style).
5. Probabilistic Hough lines (custom, no OpenCV).
6. Cluster lines into 4 dominant angles; intersect to candidate quads.
7. Score candidates by: area within `[minCoverage, maxCoverage]`, aspect in `[0.5, 2.0]`, edge-energy along sides, corner orthogonality.
8. Return the winning quad in **normalized image coordinates** (top-left origin), matching the iOS wire shape.

**Performance budget:** ≤ 8ms median on Pixel 6a (mid-tier) at the 256px working size; skip frames via `ThermalGovernor` when thermal state > nominal.

**Threading:** runs on the CameraX analyzer thread; the analyzer never blocks the main thread. JNI call is synchronous within the analyzer callback; results marshalled to main only when the EventChannel sink fires (already handled by `SupyDocumentScannerView.kt`).

### 3.2 iOS detector hardening

In `ios/Classes/document/DocumentDetector.swift`:

- Raise `VNDetectRectanglesRequest.minimumConfidence` from default to `0.7`.
- Set `quadratureTolerance = 30°` and `minimumAspectRatio = 0.4`, `maximumAspectRatio = 1.0` (Vision uses min-side / max-side, so paper ≈ A4/Letter both fit comfortably).
- **Screen-rejection heuristic:** compute variance-of-Laplacian on the Y-plane region *inside* the candidate quad (downsampled, same path the global blur metric uses). Reject if `interiorVariance < interiorVarianceFloor` — printed documents have text → high interior variance; clean screens showing a single image / solid colour are low.
- Stability tracker: maintain a ring buffer of the last 6 smoothed quads. Compute centroid drift + max-corner drift; export `quadStability` ∈ `[0, 1]` (1 = rock-still).

Same checks added to the iOS-17 `VNDetectDocumentSegmentationRequest` path (post-process the returned observation against the same gates so behaviour is consistent).

### 3.3 Channel wire format — additive only

Channel name stays `io.supy.scanner/v1`. `frame_metrics` payload gains two optional fields, both `Double`:

| Key | Range | Meaning |
|---|---|---|
| `quadStability` | 0.0 – 1.0 | 1 = no corner drift across stability window. Absent on platforms that don't yet compute it (Android falls back to centroid drift only in v1, full corner drift later). |
| `interiorVariance` | ≥ 0 | Variance-of-Laplacian inside the detected quad. Absent when `quad` is empty. |

Old consumers ignore unknown keys — Scanbot-compat API surface unchanged. `docs/ARCHITECTURE.md` table updated in the same PR.

New methods on the per-view MethodChannel:
- `captureAndRectify` → returns `{path: String, widthPx: Int, heightPx: Int, quad: List<{x, y}>}`. iOS uses `CIPerspectiveCorrection` with the most recent smoothed quad; writes JPEG to the plugin's temp dir. Android returns `FlutterError("UNIMPLEMENTED", ...)` until Sprint 4 `warpPerspective` lands.
- `captureFullFrame` → returns `{path: String, widthPx: Int, heightPx: Int}`. Always available on both platforms — iOS triggers `AVCapturePhotoOutput`, Android uses CameraX `ImageCapture`. Used by the widget as the Android fallback when `captureAndRectify` returns UNIMPLEMENTED, and by consumers who want a raw capture independent of detection.

The Dart wrapper translates `captureAndRectify` UNIMPLEMENTED into `SupyScanError.captureUnsupported`; the widget's default auto-snap handler catches that error and silently retries via `captureFullFrame` so the user always gets *some* image. Consumers who prefer "rectified or nothing" pass `guidance.allowUnrectifiedFallback: false` to disable the retry.

### 3.4 FSM extension — `holdSteady` + auto-snap

Two changes in `lib/src/document/supy_document_state_machine.dart`:

1. **New state `SupyDocumentFrameState.holdSteady`** between failing and `ready`. Priority sits between `blurry` and `ready` (slot 5.5). Entered when all failure checks pass but `quadStability < readyStabilityFloor`. Exits to `ready` once stable for `holdSteadyFrames` (default 6 ≈ 200ms at 30fps).
2. **Auto-capture countdown**, owned by `SupyDocumentScannerView` (Dart widget), not the FSM. When `onReady` first fires and `guidance.autoCapture == true`, the widget starts a 600ms countdown timer. The FSM moves to `capturing` only at completion. If the FSM drops below `holdSteady` during countdown, cancel and reset.

Why widget, not FSM: timing belongs to the UI layer (cancellable, animatable, framework-aware); the FSM stays pure and unit-testable.

### 3.5 Overlay polish

`SupyDocumentScannerView` Dart painter rewrite:

- **No quad found:** four growing corner reticles at frame corners (Scanbot's "searching" cue). Animated alpha pulse, 1.2s loop.
- **Quad found:** four corner brackets (not the full outline) on the detected quad. Stroke colour transitions red → amber → green across `noDocument` → `holdSteady` → `ready`.
- **Ready + countdown active:** circular ring countdown around the capture button (or centered if no action bar). 600ms sweep, eased.
- **Capture moment:** 80ms white flash overlay + system shutter sound (haptic on iOS via `UIImpactFeedbackGenerator`, vibrate on Android).
- **Scrim:** unchanged (path-difference cutout already does the right thing).

### 3.6 Hint copy

Drop technical labels. New defaults in `SupyDocumentGuidanceConfiguration`:

| State | Old (sample) | New |
|---|---|---|
| `noDocument` | "Position the document in view" | "Searching for document…" |
| `tooDark` | "Low light" | "Move to a brighter spot" |
| `tooClose` | "Too close" | "Move farther back" |
| `tooFar` | "Too far" | "Move closer" |
| `tooSkewed` | "Orientation mismatch" | "Hold the camera flat" |
| `blurry` | "Too blurry" | "Hold steady" |
| `holdSteady` | — | "Hold steady…" |
| `ready` | "Ready to scan" | "Don't move" |
| `capturing` | "Capturing" | "Capturing…" |

Copy is configuration, not constants — consumers can override via `SupyDocumentGuidanceConfiguration.copy`.

## 4. Data flow (per frame)

```
Camera frame
  └─ Android: CameraX analyzer thread          iOS: AVCaptureVideoDataOutput queue
       └─ DocumentFrameAnalyzer.analyze()           └─ DocumentDetector.captureOutput
            └─ JNI → detectQuad() (C++ pipeline)         └─ VNRequest → quad + interior gate
                 └─ DocumentFrameMetrics(quad,                └─ DocumentFrameMetrics(quad,
                    coverage, tilt, luma, blur,                  coverage, tilt, luma, blur,
                    clipsEdge, interiorVariance,                clipsEdge, interiorVariance,
                    quadStability)                              quadStability)
                      └─ EventChannel.send (main thread marshalled)
                           └─ Dart: SupyDocumentMetricsSmoother.add (EMA)
                                └─ SupyDocumentStateMachine.tick
                                     └─ SupyDocumentGuidanceFrame { state, smoothed, framesAtState }
                                          └─ Widget setState → painter + hint card
                                          └─ onReady? → start 600ms countdown
                                               └─ countdown done & still ready
                                                    └─ controller.capture()
                                                         └─ MethodChannel "captureAndRectify"
                                                              └─ iOS: CIPerspectiveCorrection → JPEG
                                                              └─ Android: UNIMPLEMENTED (Sprint 4)
```

## 5. Error handling

- **Android `captureAndRectify` UNIMPLEMENTED**: surfaces as `SupyScanError.captureUnsupported`. Widget falls back to manual capture (full-frame photo via CameraX `ImageCapture`) so the user is never stuck — they get a less-rectified scan, not a dead button.
- **iOS `CIPerspectiveCorrection` failure**: writes a `captureFailed` error event; widget keeps the camera running.
- **JNI library load failure on Android**: caught by `SupyNativeCore.ensureLoaded()`. Analyzer logs once and falls back to the v0 luma-only path (current behaviour). The user sees the no-quad reticles indefinitely — degraded but not crashed.
- **Detector exception (either platform)**: existing `onError` path already emits `unknown` to the event sink. Unchanged.

## 6. Testing

- **Dart unit tests** (no platform):
  - FSM: `holdSteady` entry/exit on `quadStability` crossings; countdown cancellation when state drops; preemption rules unchanged for other states.
  - Smoother: unchanged path coverage stays green.
  - Channel: new `captureAndRectify` wrapper in `lib/src/channel/`; mocked happy + UNIMPLEMENTED + error paths.
- **Native C++** (Android): GoogleTest target in `android/src/main/cpp/`. Synthetic 256×256 Y-plane fixtures: clean A4 on dark surface (should detect), pure noise (should not), screen-like uniform rectangle (should reject post-interior-variance gate when integrated with analyzer).
- **iOS unit tests**: `Tests/DocumentDetectorTests.swift` — interior-variance gate on synthetic CVPixelBuffers; aspect-ratio rejection; stability tracker on scripted quad sequences.
- **Manual QA** (`docs/QA.md` additions):
  - Pixel 6a + iPhone 13: invoice on desk, invoice held in hand (motion), invoice on laptop screen (must reject), invoice partially off-frame (must show `tooClose` clipsEdge), low-light, tilted 30°.
  - Auto-snap timing: ring countdown visible; cancellable by tilting; fires capture; manual button still works while countdown not active.

## 7. Build sequence

Implementable in this order, each step independently verifiable:

1. iOS detector hardening (confidence + aspect + interior variance + stability) → manual test on laptop-screen false positive. No FSM changes yet.
2. FSM: add `holdSteady` state + countdown widget logic. Defaults to disabled (`autoCapture: false`) so behaviour unchanged for existing consumers.
3. iOS `captureAndRectify` implementation (CIPerspectiveCorrection + JPEG write).
4. Overlay polish (reticles, brackets, ring countdown, flash, copy).
5. Android native C++ document-edge detector + JNI binding.
6. Android `DocumentFrameAnalyzer` wires the new JNI call; falls back gracefully on load failure.
7. Manual QA on both devices against `docs/QA.md` Phase scenarios.
8. Update `docs/ARCHITECTURE.md` (channel table) + `docs/SYMBOLOGIES.md` N/A + `TODO.md` (check off V1-S6-02 iOS half, V1-S6-03 already done) + `CHANGELOG.md`.

Sprint 4 `warpPerspective` and Android `captureAndRectify` body stay as separate work items.

## 8. Brand parity

`docs/internal/BRANDING_PARITY.md` is the SSOT for native chrome literals; it currently excludes the document scanner because VisionKit/GMS were vendor-owned. This spec moves the embedded document overlay into parity scope.

**Rules:**
- All overlay colours, radii, and typography read from `SupyScannerPalette` (default: `scanbotDark` — primary `#1AC0E5`, on-primary `#FFFFFF`, scrim black @ 0.55) through `SupyDocumentGuidanceConfiguration`. **No hardcoded `#6448C3` or any other purple in the library.** The purple seen in the prior screenshot is the consumer/example-app theme override and stays in the example app, not the library defaults.
- The ring countdown stroke uses `palette.primary`; the corner brackets in `ready` state use `palette.primary`; failure-state brackets use a palette-defined `warning` colour (added to `SupyScannerPalette`, default `#FF4D4D`).
- Hint card scrim alpha matches the batch barcode counter (`black @ 0.55`) for cross-surface consistency.
- Capture button (if/when the overlay owns one — currently provided via `footer` slot) follows the Done-chip recipe from BRANDING_PARITY.md §Layout parity: pill, radius 22, `palette.primary` bg, white semibold 17pt.

**Doc updates required in the same PR:**
- Add a "Document Scanner" section to `BRANDING_PARITY.md` mirroring the Batch table once the overlay lands, with rows for: counter (if present), corner reticles, corner brackets, ring countdown, capture-flash colour/timing, hint pill.
- Note in BRANDING_PARITY that document overlay literals come from `SupyScannerPalette` via the channel-supplied palette (unlike batch barcode, which hardcodes — because the document widget IS Flutter, not native chrome, so it can read the palette directly from Dart).

## 9. Open questions for review

1. **Auto-capture default** — should `autoCapture` default to `true` (Scanbot behaviour) or stay `false` to preserve current consumer behaviour? Recommendation: `true` for new consumers; existing example app explicitly opts in to avoid surprising in-flight integration. *(Author's pick: default `true`.)*
2. **Manual capture fallback on Android** — full-frame JPEG without perspective rectification. Acceptable interim, or should we block auto-snap entirely on Android until Sprint 4? Recommendation: ship the fallback. Users still get a usable scan, just not crop-corrected. *(Author's pick: ship fallback.)*
3. **Interior-variance threshold tuning** — depends on physical testing. v1 ships with a conservative floor (`5.0` on a 0–~250 scale) and we tune on real device samples during QA.
