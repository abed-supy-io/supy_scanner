# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — Document scanner smart guidance

Smart-guidance + auto-snap + interior-variance false-positive gate for the
embedded `SupyDocumentScannerView`. Channel stays `io.supy.scanner/v1`
(additive only). Drop-in for v1.0.x / v1.1 retailer consumers.

### Added
- `SupyDocumentFrameState.holdSteady` — new FSM state between failing states and `ready`. Entered when all failure checks pass but `quadStability < readyStabilityFloor`; exits to `ready` after `holdSteadyFrames` (default 6) consecutive stable frames.
- `quadStability` (Double 0–1) and `interiorVariance` (Double) fields on `SupyDocumentFrameMetrics` and the `frame_metrics` EventChannel payload. Old consumers that ignore unknown map keys are unaffected.
- `holdSteady` guidance state hint copy (`"Hold steady…"`) in `SupyDocumentGuidanceHints`.
- `captureAndRectify` MethodChannel method — iOS: `CIPerspectiveCorrection` against the last smoothed quad + `AVCapturePhotoOutput` JPEG write to `NSTemporaryDirectory()`. Returns `{ path, widthPx, heightPx, quad }`. Android returns `UNIMPLEMENTED` until Sprint 4 `warpPerspective` lands.
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
- Channel name unchanged: `io.supy.scanner/v1`. New methods (`captureAndRectify`, `captureFullFrame`) and new `frame_metrics` keys (`quadStability`, `interiorVariance`) are additive.

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
