# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- iOS: on-still quad refinement for `captureAndRectify` — the preview quad is
  aspect-mapped into the captured still and re-detected on it; the re-detection
  is accepted at IoU ≥ 0.8, otherwise the mapped preview quad is used. The
  result payload gains an additive `quadSource` key (`refined` | `preview`),
  surfaced on `SupyDocumentCapture.quadSource`.

### Fixed
- iOS: `captureAndRectify` applied the analyzer-stream quad to the still with
  no aspect mapping, mis-cropping whenever the analyzer and photo aspect
  ratios differ (e.g. 16:9 stream vs 4:3 still).
- Document scan output sharpness on iOS (`DocumentScannerPresenter`) regressed visibly vs. the legacy Scanbot SDK on the same camera. VisionKit already returns the deskewed, enhanced page at native resolution — the only quality loss in our pipeline was the JPEG re-encode at the v1.0 default of 85, which produced softness and mosquito-noise around small text. Raised the default `SupyDocumentScanOptions.jpegQuality` from `85` to `95` (matches Scanbot's perceived output quality) and lifted the LOW device-tier cap from `75` to `88` on both platforms (`SupyDeviceTier.jpegQuality` / `DeviceTier.jpegQuality`) so low-end hardware no longer torches text legibility. The native fallback default in `DocumentScannerPresenter.swift` was bumped in lockstep so calls that omit the key get the new default too. On Android this also auto-unlocks the existing GMS JPEG passthrough fast-path in `PageReencoder` (no re-encode when `jpegQuality >= 95` and `enhanceMode == off`) — smaller temp files, fewer Bitmap decodes, no code change required there. Callers that explicitly set a lower quality (e.g. the `jpegQuality: 70` scenario in `docs/QA.md`) are unaffected.

### Added
- Advanced document enhancement stages — real `max` mode (v1.1 Sprint 4 Phase B). `SUPY_ENHANCE_MAX` is no longer an alias of `BALANCED`; it now layers three new OpenCV-free, hand-rolled stages on top of the balanced stack: specular/glare clamp (`suppressSpecular` in `native/enhance/illumination.cpp` — morphological-opening diffuse estimate, caps near-white hotspots toward `diffuse + 24`), morphological top-hat background flatten (`native/enhance/tophat.{h,cpp}` — closing with an SE larger than the largest glyph, lifts the local paper deficit), and tile-based CLAHE (`native/enhance/clahe.{h,cpp}` — 8×8 clipped-histogram grid with bilinear inter-tile interpolation). A shared separable morphology helper (`native/enhance/morphology.{h,cpp}`, monotonic-deque O(n) min/max) backs the new stages and is reused by illumination. New stage bits `SUPY_ENHANCE_STAGE_SPECULAR/TOPHAT/CLAHE` (`0x10/0x20/0x40`) surface on `SupyDocumentPage.enhancedStages`. Full `max` order: gate → illumination → specular → top-hat → tone → CLAHE → unsharp. OCR input policy unchanged (denoised/deskewed grayscale, never binarized). No public Dart API or channel change — `enhanceMode: 'max'` already flowed end-to-end. Host GoogleTest coverage extended in `native/enhance/enhance_test.cpp`; benched in `native/enhance/bench_enhance.cpp` (heaviest mode, ~2–2.5× `balanced`).
- Hand-rolled perspective warp + Android `captureAndRectify` (v1.1 Sprint 4 Phase A). New OpenCV-free native module `native/document/perspective_warp.{h,cpp}` solves the 8-DOF homography from four quad corners (Gaussian elimination on the 8×8 system) and inverse-map bilinear-samples to a flat rectangle, exposed over the C ABI (`supy_core_warp` family; `SUPY_CORE_ABI_VERSION` → 5) and JNI (`nativeWarpPerspective` → packed RGBA + `[w,h]`). Android's previously-`UNIMPLEMENTED` `captureAndRectify` now decodes the full-res still, scales the last smoothed `DocumentFrameAnalyzer` quad into pixel space, warps to a flat page off the main thread, and runs `PageReencoder.reencodeBitmap` (decode-free enhance + score + encode), returning `{ path, widthPx, heightPx, quad }` to match the iOS payload. No quad detected → `captureUnsupported` so the Dart widget still falls back to `captureFullFrame`. iOS stays on `CIPerspectiveCorrection` (geometry-equivalent; sharing the native warp is a deferred optional follow-up — divergence noted in `docs/ARCHITECTURE.md`). Channel additive — no `v1` bump, no public Dart API change.
- iOS guidance-classifier bridge parity (v1.2 P2, `core-cxd-ios-guidance-bridge`). Brings iOS to the same native guidance surface Android already has: the C++ document guidance state machine (`native/document/document_guidance_classifier.{h,cpp}`, commit `c4e4650`) is now reachable from Swift via a stateful Obj-C++ bridge (`SupyDocumentGuidance` in `SupyNativeCoreBridge.{h,mm}`) and a Swift facade (`GuidanceClassifier` + `GuidanceFrameState` / `GuidanceConfig` / `GuidanceFrameMetrics` / `GuidanceClassifyResult` in `SupyNativeCore.swift`). The bridge owns a heap-allocated `GuidanceState` for its lifetime (freed in `-dealloc`) — the ARC-safe iOS equivalent of Android's Kotlin-owned `jlong` handle; the 18-float config packing and `[stateOrdinal, liveQualityScore]` return mirror the JNI shim (`supy_scanner_core_jni.cpp#nativeGuidanceClassify`) byte-for-byte. Internal native bridge only — no channel method, no `v1` bump, no public Dart/Swift API change. The auto-snap loop in `DocumentScannerPresenter` stays on VisionKit (deferred). New XCTest `ios/Tests/nativecore/SupyGuidanceClassifierTests.swift` pins the Swift→Obj-C++→C++ marshalling.
- iOS embedded-view native guidance (v1.2 P2, `core-cxd-ios-guidance-embedded`). Wires the iOS `GuidanceClassifier` (above) into the embedded streaming preview `SupyDocumentScannerView` so on-device guidance is computed by the shared C++ core instead of the Dart FSM. The Dart widget serializes its `SupyDocumentGuidanceConfiguration` to the 18-float wire order via new `toConfigFloatArray()` and hands it to the `UiKitView` as a `guidanceConfig` creation param; `SupyDocumentScannerView.swift` parses it (`GuidanceConfig(wireArray:)`), classifies each frame on the detector's analyzer queue in `emitFrameMetrics`, and adds `state` (wire-stable ordinal 0–11) + `liveQualityScore` to the existing internal `frame_metrics` EventChannel payload. `SupyDocumentEvent.fromMap` decodes the new optional `state` into `SupyDocumentFrameMetricsEvent.nativeState` via `kSupyDocumentFrameStateWireIndex` (out-of-range → `null`), and the widget consumes `nativeState` when present, falling back to the Dart `SupyDocumentStateMachine` only when it is absent. `GuidanceClassifier.reset()` runs on `resume`. Net effect on iOS: the three documented Dart-FSM hysteresis quirks (glare / occluded / handShake not un-latching via exit-margin) are gone, since the C++ classifier implements exit-margins correctly. Additive and backward-compatible — internal channel only, no public Dart/Swift API change, no `v1` bump. **Temporary divergence:** the Android embedded `SupyDocumentScannerView` still runs the Dart FSM (emits no `state`); routing it through its JNI `GuidanceClassifier` for full parity is a deferred follow-up.
- CameraX document fallback auto-snap (v1.2 P2, `core-cxd-auto-snap` / CXD-AS1). `CameraXDocumentScannerActivity` now drives auto-capture from the C++ guidance state machine (`native/document/document_guidance_classifier.{h,cpp}`, commit `c4e4650`) through a new JNI surface (`nativeGuidanceCreate/Destroy/Reset/Classify`) and Kotlin facade (`SupyNativeCore.guidance*`, plus `GuidanceFrameMetrics` / `GuidanceConfig` / `GuidanceFrameState`). The activity migrated from `ProcessCameraProvider` to `LifecycleCameraController` bound to the host `Activity` lifecycle (no `FragmentActivity` cast); `IMAGE_CAPTURE | IMAGE_ANALYSIS` enabled with `KEEP_ONLY_LATEST` backpressure. `DocumentFrameAnalyzer` is attached on a dedicated `supy-cxd-analyzer` executor only when `SupyDocumentScanOptions.autoCaptureDelayMs > 0`; `autoCaptureDelayMs == 0` keeps capture purely manual. Tier-aware dwell via `GuidanceConfig.readyStableFrames` = 18 / 12 / 9 for LOW / MID / HIGH (iOS device tier still returns `unknown` → MID fallback; tracked in S3-05), plus a tier-aware ms floor on the consumer-supplied `autoCaptureDelayMs` (`max(autoCaptureDelayMs, 1200 / 800 / 600)` for LOW / MID / HIGH) so low-end devices can't fire a sub-floor dwell even if the caller asks for one. A new on-preview `hintLabel` renders bilingual (en / ar) guidance copy for the 8 `GuidanceFrameState` values; the activity locale is wired through `EXTRA_LOCALE` from `DocumentScannerLauncher`. Channel additive — no `v1` bump; no new public scan option (existing `autoCaptureDelayMs` is the off switch).
- iOS temporal-median-of-3 Data Matrix ROI fusion (v1.1 P1, `core-temporal-median-fusion` / V1-S2-06.3 iOS). Mirrors the Android V1-S2-06.1/.2 path on iOS. New per-`BarcodeDetector` `DatamatrixTemporalRing` (`ios/Classes/barcode/DatamatrixTemporalRing.swift`) holds the last two libdmtx-located frames + their full luma. In `tryNativeDecode`, before falling through to the raw-crop `decodeDmRegion`, each located region is matched against prior frames by IoU ≥ 0.5; on a hit the union bbox is cropped from all three frames into pooled scratch buffers and fused via the new `supy_core_temporal_median_luma` C ABI. The fused crop is Sauvola-binarized and DM-decoded with corner translation by `(srcX0, srcY0)`. Misses fall through to the existing raw-crop path; end-of-frame the ring is pushed with the full luma + all per-region bboxes (frames without locator hits are not pushed, preserving held-region streaks). New Obj-C bridge entry point (`SupyNativeCoreBridge +temporalMedianLuma3:frame1:frame2:out:width:height:rowStride:`) and Swift facade (`SupyNativeCore.temporalMedianLuma3(...)`) round out the surface.
- iOS Sauvola adaptive binarization on the Data Matrix ROI crop (v1.1 P1, `core-adaptive-binarization` / V1-S2-05.1 iOS). Mirrors the Android V1-S2-05.1 wire-through: between the `cropBuffer` luma fill and the DM-only `supy_core_decode` re-entry in `BarcodeDetector.decodeDmRegion`, the crop is in-place binarized via `supy_core_binarize_luma(SAUVOLA_2D)` (integral-image, window `clamp(min(w,h)/16,5,25)`, k=0.34, R=128). A `false` return falls through to a raw-luma decode rather than dropping the frame. New Obj-C bridge entry point (`SupyNativeCoreBridge +binarizeLumaInPlace:width:height:rowStride:mode:`) and Swift facade (`SupyNativeCore.BinarizeMode { sauvola2D, wolfJolion1D }`, `binarizeLumaInPlace(luma:width:height:rowStride:mode:)`) round out the surface. Sauvola is matrix-code-only; the 1D Wolf-Jolion path stays reserved for a later 1D assist.
- iOS libdmtx Data Matrix ROI-assist path (v1.1 P1, `core-libdmtx-ios-bridge` / V1-S2-04b). Mirrors the Android V1-S2-04a/.2/.3 path on iOS: when `useNativeCore` is on, `SupyNativeCore.hasLibdmtx()` is true, and Data Matrix is in the requested format mask, `BarcodeDetector.tryNativeDecode` first runs `supy_core_locate_datamatrix` against the CVPixelBuffer Y-plane, axis-aligned-bbox-crops each region (~6% padding clamped, ≥12×12 min) into a reusable per-detector `cropBuffer` (grown ×1.5), re-enters `supy_core_decode` on the crop with a DM-only mask and `tryHarder=true`, then translates corners back to input pixel space. Full-frame decode still runs for the non-DM portion of the mask — skipped only when DM was the sole requested format and the locator pass ran. New Obj-C bridge entry points (`SupyNativeCoreBridge +hasLibdmtx`, `+locateDatamatrixFromLuma:...`) and Swift facade additions (`SupyNativeCore.hasLibdmtx()`, `locateDatamatrix(luma:width:height:rowStride:maxRegions:timeoutMs:)`, `includesDataMatrix`, `maskWithoutDataMatrix`) round out the surface.
- iOS zxing-cpp barcode decode path (v1.1 P1, `core-zxing-ios-bridge` / V1-S2-03b). Mirrors the Android `nativeCoreEnabled` route: when `useNativeCore` is passed via PlatformView creation params or `BatchBarcodeScannerActivity`-equivalent args AND `SupyNativeCore.hasZxing()` returns true, `BarcodeDetector` short-circuits Vision per frame and runs `supy_core_decode` against the CVPixelBuffer Y-plane. Caller-side `CVPixelBufferLockBaseAddress` + `defer { unlock }` keeps the buffer leak-free; non-planar pixel formats fall through to Vision. New Obj-C bridge entry points (`SupyNativeCoreBridge +hasZxing`, `+decodeBarcodesFromLuma:...`) and a `SupyFormatMask` Swift OptionSet mirror Android's `FormatMapper` wire-name table — `docs/SYMBOLOGIES.md` remains the single source of truth.
- CameraX document backend availability gate (v1.2 P2, `core-cxd-availability-gate`):
  - New `SupyDocumentScannerBackend { gms, cameraX, unknown }` enum (`lib/src/models/supy_document_scanner_backend.dart`) re-exported from `supy_scanner.dart`.
  - Optional `SupyDocumentScanOptions.preferredBackend` (Android only, hint) — `null` keeps the existing auto-detect, `cameraX` forces the fallback even when GMS is usable (tests, dogfood, opt-out), `gms` requests GMS but falls through when unavailable.
  - `SupyDocumentData.resolvedBackend` (always populated) reports which backend actually produced the result. Older Dart builds reading a v1.1 payload get `SupyDocumentScannerBackend.unknown` via the `fromWire` fallback.
  - `SupyNativeCoreProbe.gmsDocumentScannerAvailable` (defaults to `false` when omitted) exposes `GmsAvailability.isUsable(context)` to retailer code that wants to pre-flight the GMS path. iOS always reports `false`.
- Perfgate enhance bench (v1.2 P2, `core-document-image-enhance-bench` / DIE6). The existing host harness `native/enhance/bench_enhance.cpp` learns `--json` and `--tier {low,mid,high}` flags so its stdout matches the `BENCH_TIER` / `BENCH_RESULT { "metric": "enhance_<mode>_ms", ... }` line protocol consumed by `tools/perfgate/lib/baseline_compare.dart`. A new Dart driver `tools/perfgate/enhance/run_enhance_bench.dart` builds it via CMake (`-DSUPY_BUILD_TOOLS=ON`) and runs it with the requested tier. CI gains an `enhance-bench-low` job on `ubuntu-latest` (mirrors `perfgate-emulator`, `continue-on-error: true`); MID and HIGH tiers are deferred to `infra-device-runner-matrix` (P3). Parser coverage lives in `tools/perfgate/test/enhance_bench_test.dart`. Initial LOW-tier baselines under `tools/perfgate/baselines/low/enhance_*.json` will be promoted from the first green CI run via `tools/perfgate/regen-baselines.dart`.
- PDF output on the CameraX document fallback (v1.2 P2, `core-cxd-camerax-activity` / CXD2). New internal `PdfAssembler` (`android/src/main/kotlin/io/supy/scanner/document/PdfAssembler.kt`) walks the re-encoded JPEG pages through Android's `PdfDocument` so `outputFormat=pdf` no longer silently degrades on non-GMS devices — `pdfUri` is now populated on both backends. Pages retain their native pixel dimensions; the assembler is a pure I/O helper with no PDF-format knobs exposed to retailer code. The stale launch-time "JPEG only" log line is removed.
- `SupyScannerChannel.debugForceTier(SupyDeviceTier?)` (channel method `debugForceTier`, v1.1, debug-only) — pins the native device-tier heuristic to `high|mid|low` (or clears with `null` / `SupyDeviceTier.unknown`). Used by perfgate CI matrices and engineers reproducing tier-low bugs on flagships. Dart wrapper is a no-op when `!kDebugMode`; Android handler gates on `ApplicationInfo.FLAG_DEBUGGABLE`; iOS handler is wrapped in `#if DEBUG`. Override is a sibling `@Volatile` static on `io.supy.scanner.perf.DeviceTier` / `SupyDeviceTier` so the cached tier is untouched. Example app's `SupyDebugHud` panel header surfaces an AUTO / HIGH / MID / LOW popup picker.
- Document image enhancement pipeline (Phase DIE). Shared native C++ post-processing applied to captured pages before persistence / OCR / PDF assembly:
  - `SupyDocumentEnhanceMode` enum (`off` / `fast` / `balanced` / `max`) re-exported from `supy_scanner.dart`.
  - Optional `SupyDocumentScanOptions.enhanceMode` — `null` (default) lets each platform pick (`balanced` on Android, `off` on iOS where VisionKit already enhances).
  - Per-page `SupyDocumentPage.enhancedStages` (bitmask) and `enhanceMs` (wall-clock) diagnostics.
  - C ABI in `native/include/supy_scanner_enhance.h` — blur-rejection gate (variance-of-Laplacian), separable morphological illumination flatten, gamma + S-curve tone LUT, separable unsharp mask. No OpenCV dependency.
  - Android: JNI bridge + `PageReencoder` integration (decode → enhance → tier-aware re-encode).
  - iOS: Obj-C++ shim over the C ABI; `DocumentScannerPresenter` runs the pipeline between `UIImage` delivery and `jpegData`.
  - Host GoogleTest suite at `native/enhance/enhance_test.cpp`; design doc at `docs/ENHANCEMENT.md`.
- `SupyDocumentFrameState.holdSteady` — new FSM state between failing states and `ready`. Entered when all failure checks pass but `quadStability < readyStabilityFloor`; exits to `ready` after `holdSteadyFrames` (default 6) consecutive stable frames.
- `quadStability` (Double 0–1) and `interiorVariance` (Double) fields on `SupyDocumentFrameMetrics` and the `frame_metrics` EventChannel payload. Old consumers that ignore unknown map keys are unaffected.
- `holdSteady` guidance state hint copy (`"Hold steady…"`) in `SupyDocumentGuidanceHints`.
- `captureAndRectify` MethodChannel method — iOS: `CIPerspectiveCorrection` against the last smoothed quad + `AVCapturePhotoOutput` JPEG write to `NSTemporaryDirectory()`. Returns `{ path, widthPx, heightPx, quad }`. (Android landed in Sprint 4 Phase A via the hand-rolled native warp — see the Phase A entry above.)
- `captureFullFrame` MethodChannel method — always available on both platforms. iOS: `AVCapturePhotoOutput`. Android: CameraX `ImageCapture` writing to `context.cacheDir`. Returns `{ path, widthPx, heightPx }`.
- Auto-capture countdown owned by `SupyDocumentScannerView`: when `guidance.autoCapture == true` (default), a 600 ms countdown ring sweeps on first `ready`; on completion calls `captureAndRectify`, catching `UNIMPLEMENTED` and retrying via `captureFullFrame` when `guidance.allowUnrectifiedFallback == true`. Countdown cancels if the FSM drops below `holdSteady`.
- `SupyDocumentCountdownRing` widget — exported from `supy_document_scanner_view.dart`; animates an arc from −π/2 sweeping clockwise over `duration`; fires `onComplete` once.
- Android native C++ document-edge detector (`native/document/document_edge_detector.{h,cpp}`) in the `supy_scanner_core` JNI scaffold — adaptive Canny + Hough pipeline at a 256 px working size. `DocumentFrameAnalyzer` wires the JNI call with a graceful fallback to the luma/blur-only v1 path on load failure.
- `SupyScannerPalette.warning` color token (default `#FF4D4D`) — used by the document overlay for failure-state corner brackets and reticles.
- `SupyDocumentGuidanceConfiguration` extensions: `readyStabilityFloor`, `interiorVarianceFloor`, `holdSteadyFrames`, `autoCapture`, `autoCaptureDelay`, `allowUnrectifiedFallback`, `warningColor`.

### Changed
- `SupyDocumentFrameMetrics` schema extended with `quadStability` and `interiorVariance` (both default `0.0`; backwards-compatible with existing `fromMap` callers).
- iOS document detector hardened: `VNDetectRectanglesRequest.minimumConfidence = 0.7`, `quadratureTolerance = 30°`, `minimumAspectRatio = 0.4`, `maximumAspectRatio = 1.0`; interior-variance gate rejects laptop-screen false positives (`interiorVariance < 5.0` → treat as no document); `QuadStabilityTracker` ring-buffer now tracks last 6 quads and exports `quadStability`.
- Document overlay redesigned: corner reticles pulse when no quad is found; corner brackets (not full outline) track the detected quad with color ramping red → amber → green across failure → holdSteady → ready states; ring countdown visible during auto-snap; 80 ms white flash + haptic on capture. All literals route through `SupyScannerPalette` — no hardcoded colors.
- Default hint copy updated for clarity: `noDocument` → `"Searching for document…"`, `tooDark` → `"Move to a brighter spot"`, `tooClose` → `"Move farther back"`, `tooFar` → `"Move closer"`, `tooSkewed` → `"Hold the camera flat"`, `blurry` → `"Hold steady"`, `ready` → `"Don't move"`.

### Channel
- Channel name unchanged: `io.supy.scanner/v1`. New methods (`captureAndRectify`, `captureFullFrame`) and new `frame_metrics` keys (`quadStability`, `interiorVariance`) are additive. v1.2 P2 adds two more additive keys: `scanDocument` accepts `preferredBackend` and returns `resolvedBackend`; `nativeCoreProbe` returns `gmsDocumentScannerAvailable`.

---

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

## [1.0.1] — 2026-06-14

Hardening, observability, and release-ops sprint. **No public API changes** — Dart, MethodChannel (`io.supy.scanner/v1`), and native error-code surface are byte-for-byte compatible with v1.0.0. Retailer consumers upgrade without code changes.

### Hardened
- Channel error-code surface normalized to exactly `{cancelled, permission_denied, camera_unavailable, model_unavailable, unknown}` across Android + iOS — four pre-existing strays (`SupyScannerPlugin.nativeCoreProbe` on both platforms; `SupyBarcodeScannerView.setZoom`; `SupyDocumentScannerView.onError`) folded to canonical `unknown` with detail preserved in `message`. `format_unsupported` reserved for future use.
- MethodChannel argument validation: every handler gates malformed payloads through `expectMapArgs` (Android Kotlin) / `expectMapArgs` (iOS Swift). Non-`Map` payloads now surface canonical `unknown` naming the method + runtime type instead of being silently dropped.
- `EventChannel.EventSink` discipline: both platform views signal `endOfStream` / `FlutterEndOfEventStream` on dispose so Dart subscribers see a clean `onDone` instead of a silent drop. iOS marshals end-of-stream to `.main` from `deinit` if needed.

### Testing
- Android JVM unit suite (Robolectric + JUnit 4): `FormatMapperTest` + `DeviceTierTest`. Runs in CI via `./gradlew :supy_scanner:testDebugUnitTest`. UI/AVCapture-bound classes deferred.
- iOS XCTest unit suite: `SymbologyMapperTests` + `SupyDeviceTierTests`. Wired via `s.test_spec 'Tests'` in the podspec.
- Dart property-based fuzz at the channel boundary (`test/channel/fuzz_test.dart`): 10k frames with deterministic seed `0xDEC0DE` covering `fromMap` round-trip + single-mutation malformed payloads. Malformed-input invariant: only `TypeError` / `ArgumentError` / `SupyScanError` may escape.
- Widget structural-test backfill for Sprint 1.5 widgets (`supy_top_bar`, `supy_user_guidance_card`, `supy_action_bar`, `supy_barcode_scanner_view`) — recording-canvas style, no pixel goldens.
- Integration-test harness scaffolded under `example/integration_test/` with one driver per use-case (single / batch / embedded / document); headless `navigate:` cases compile and pass in CI, `device-only:` cases gated behind `SUPY_SCANNER_DEVICE_TEST=true` for emulator/device runners.
- Coverage gates wired in CI: Dart lcov line coverage gated at ≥ 70% (current baseline 76.34%); Kover XML report for Android and `xccov` JSON for iOS uploaded as artifacts (native thresholds deferred until CI-observed baselines).

### Observability
- `SupyLogSink` Dart facade (`lib/src/log/supy_log.dart`) with `SupyLogLevel`, immutable `SupyLogRecord`, `SupyDebugPrintLogSink` (release-mode no-op), `SupyNullLogSink`, and a static `SupyLog` facade (`installSink` / `debug` / `info` / `warn` / `error`). Exported from `package:supy_scanner/supy_scanner.dart`. Consumers can install their own sink to route library logs into Sentry / Crashlytics / etc.
- Native log parallels: `io.supy.scanner.log.SupyLog` (Kotlin object over `android.util.Log`, `@JvmStatic @Volatile enabled` toggle) and `SupyLog` (Swift `os.Logger` with per-tag cache + `privacy: .public`). All four pre-existing native log sites rerouted through these. Native→Dart channel-forwarded sink override is a deferred follow-up.
- Example-app debug HUD (`example/lib/debug/supy_debug_hud.dart`) — overlay panel showing the last 200 `SupyLogRecord`s; togglable via AppBar action; debug-only via `SupyDebugHudScope` so the entire HUD path tree-shakes out of release builds.

### Tooling
- `tools/release.sh <version>` — automated version bump + gates + commit + annotated tag. Pre-flight: semver shape, `main` branch, clean tree, tag absent, CHANGELOG entry present. Bumps `pubspec.yaml` / `ios/supy_scanner.podspec` / `android/build.gradle` in lock-step. Runs `flutter analyze --fatal-infos` + `flutter test`. Idempotent on re-run. Does NOT push and does NOT publish — operator runs those manually.
- `docs/RELEASE.md` — release runbook + symbolication contract. Per-release retention requirements for retailer-side R8 mapping, un-stripped Android `.so`s, iOS dSYMs, and Flutter `--split-debug-info` symbols (≥ 12-month retention). Post-hoc symbolication recipe (`llvm-addr2line` / `atos` / `flutter symbolize`). v1.1 native-core `-g -O2 -fno-omit-frame-pointer` parity rule.
- CI matrix expansion (`.github/workflows/ci.yml`): workflow-level `concurrency` group cancels superseded PR runs; least-privilege `permissions: contents: read`; explicit `timeout-minutes` per job. Two non-blocking canary jobs added — `analyze-and-test-stable-canary` (Flutter `stable` channel) and `android-native-test-jdk21-canary` (JDK 21) — to surface upstream regressions before they bite the pinned floor.

### Docs
- `docs/SECURITY.md` — 12-section channel-boundary security review covering threat model, full channel surface, in/outbound arg validation, zero-network posture, permission inventory, filesystem surface, sensitive-data rules, dep pinning, known gaps.
- `docs/DEPENDENCIES.md` — 9-section dep audit: exact pins for Dart / Android / iOS / native / CI, CVE scan log, license inventory (no copyleft), update cadence, follow-ups (SHA-pin actions, GMS DocScan beta1 bump, SBOM automation).
- `docs/REPRODUCIBLE_BUILDS.md` — 9-section reproducibility doc scoping the 4 claims (pinned sources, pinned toolchain, deterministic plugin outputs, deterministic test outputs — explicitly NOT byte-identical host APK/IPA), manual repro procedure, accepted nondeterminism, verification log.

### Channel
- Channel name unchanged: `io.supy.scanner/v1`. No method-set or argument-shape changes.

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
