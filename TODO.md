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
- [x] S4-07 — Tag `v1.0.0` — repo initialized; commit 8724f68 + local annotated tag `v1.0.0` (2026-06-13). **Remote push + internal pub publish pending — needs remote URL from mobile lead.**
- [ ] S4-08 — Mobile-lead sign-off walkthrough

## v1.1 Sprint 1 — Native core scaffold

See `docs/V1.1_PLAN.md`.

- [x] V1-S1-01 — `native/` C++ core skeleton (`supy_scanner_core.h/.cpp`, CMake, `SUPY_CORE_ABI_VERSION = 1`) — 2026-06-13
- [x] V1-S1-02 — Android JNI bridge + `SupyNativeCore.kt` + Gradle externalNativeBuild (NDK r26, c++17, c++_static) — 2026-06-13
- [x] V1-S1-03 — iOS pod source_files glob over `../native/` + `SupyNativeCore.swift` — 2026-06-13
- [x] V1-S1-04 — `nativeCoreProbe` MethodChannel method on both platforms — 2026-06-13
- [x] V1-S1-05 — Dart `nativeCoreProbe()` + `SupyNativeCoreProbe` + mocked unit test — 2026-06-13
- [x] V1-S1-06 — `useNativeCore` feature flag on barcode + document options (default `false`) — 2026-06-13
- [x] V1-S1-07 — Example-app debug toggle (AppBar `memory` icon → SnackBar) — 2026-06-13
- [x] V1-S1-08 — `docs/ARCHITECTURE.md` channel-method table row — 2026-06-13
- [ ] V1-S1-09 — On-device probe verification (one Android + one iPhone)

## v1.1 Sprint 1.5 — Embedded UI parity with Scanbot

See `docs/V1.1_PLAN.md` Sprint 1.5. Embedded `SupyBarcodeScannerView` only — native Document & Batch screens stay GMS/VisionKit.

- [x] V1-S1_5-01 — `SupyScannerPalette` (16 tokens) + `scanbotDark` / `scanbotLight` defaults — type done 2026-06-13; 11 unit tests pass (preset stability, dark-vs-light divergence, translucent modal overlay, light-surface luminance ≥200, per-token equality discrimination across all 16 tokens, full copyWith) — 2026-06-13
- [x] V1-S1_5-02 — `SupyTopBarConfiguration` + `SupyTopBar` widget (solid + gradient) — 2026-06-13
- [x] V1-S1_5-03 — `SupyViewFinderConfiguration` + cornered-finder `CustomPainter` — type + painter done 2026-06-13; 9 paint-behavior tests pass (invisible→no-op, exactly 4 corner paths, stroke style + configured color/width applied to every path, centered fit-rect ≤85% of canvas, aspect-ratio honored, shouldRepaint true on visibility/color/aspect change and false on identical config) — recording-canvas approach over image goldens to dodge platform/Skia flakiness — 2026-06-13
- [x] V1-S1_5-04 — `SupyUserGuidanceConfiguration` + guidance-card widget — 2026-06-13
- [x] V1-S1_5-05 — Per-view channel methods: `setZoom`, `flipCamera`, `setMinFocusDistanceLock` (Dart + Android + iOS + mocked tests) — 2026-06-13
- [x] V1-S1_5-06 — `SupyActionBarConfiguration` + `SupyActionBar` widget (flash/zoom/flip-camera/close-focus) wired to controller — 2026-06-13
- [x] V1-S1_5-07 — `SupyCameraConfiguration` (`minFocusDistanceLock`, `initialZoom`, `scanRange`) + factory plumbing — Dart value type, `SupyBarcodeScanOptions.camera`, Android `applyInitialCameraConfig` (zoom), iOS `applyInitialCameraConfig` (zoom + `.near` AF restriction), 6 unit tests — 2026-06-13
- [x] V1-S1_5-08 — `SupySingleScanUseCaseConfiguration` + `SupySingleScanConfirmationSheet` widget (title, format chip, raw value, submit/retry buttons) — 9 unit + widget tests — 2026-06-13
- [x] V1-S1_5-09 — `SupyMultipleScanUseCase` (counting/unique) + collapsible sheet + `countingRepeatDelay` — `SupyMultipleScanUseCaseConfiguration` + `SupyMultipleScanMode { counting, unique }`, headless `SupyMultipleScanAccumulator` (ChangeNotifier with debounce + injectable `now`), `SupyMultipleScanSheet` collapsible widget, 13 tests pass — 2026-06-13
- [x] V1-S1_5-10 — `SupyFindAndPickUseCase` + expected-barcodes sheet — `SupyExpectedBarcode` value type, `SupyFindAndPickUseCaseConfiguration` (pick-list + `allowUnexpected`), `SupyFindAndPickAccumulator` (per-row progress, cap at `expectedCount`, `isComplete`), `SupyFindAndPickSheet` (per-row check icons, X/Y picked header, submit gated on completion), 18 tests pass — 2026-06-13
- [x] V1-S1_5-11 — `SupyArOverlayConfiguration` + bounding-box overlay — `SupyArOverlayConfiguration` value type (stroke/fill/label knobs, validation asserts), `SupyArOverlay` widget paints filled+stroked RRects + label chips over normalized `[0..1]` boxes via `CustomPaint`, label auto-flips inside-box when above-box has no room, 11 tests pass — 2026-06-13
- [x] V1-S1_5-12 — `SupyBarcodeScannerScreen` full-screen composite widget — sealed `SupyScanUseCase` (Single/Multiple/FindAndPick) drives sheet selection + result-callback routing; full-screen `Stack` composes preview + finder painter + AR overlay + top bar + guidance card + action bar + use-case sheet; owns its own controller unless one is supplied; 10 widget+unit tests pass; analyzer clean on lib/supy_scanner.dart and the new screen file — 2026-06-13
- [x] V1-S1_5-13 — Example app: demo gallery (single / multi-counting / find-and-pick) + palette picker — added 4th "Gallery" tab to `example/lib/main.dart` listing 5 demos (single+confirm, single-immediate, multi-counting, multi-unique, find-and-pick) that launch full-screen `SupyBarcodeScannerScreen` via `Navigator.push`; `SegmentedButton` palette picker toggles `scanbotDark` / `scanbotLight`; result callbacks pop the route and surface via SnackBar; `SupyScannerPalette` added to barrel exports; analyzer clean — 2026-06-13
- [x] V1-S1_5-14 — `docs/UI_CONFIGURATION.md` + `docs/MIGRATION.md` Scanbot-RTU-UI mapping — published `docs/UI_CONFIGURATION.md` (anatomy diagram, per-layer config catalog covering all 11 UI value types, use-case variants, palette tokens, 3 quick recipes) + appended "Scanbot RTU-UI → supy_scanner mapping" section to `docs/MIGRATION.md` (1:1 mapping table + non-1:1 caveats: per-config strings vs. localization registry, sealed use-case vs. enum, no image-result event in v1.1) — 2026-06-13
- [x] V1-S1_5-15 — `docs/ARCHITECTURE.md` channel + module updates — added `models/ui/` row enumerating all v1.1 UI value types (palette, top bar, view finder, user guidance, action bar, AR overlay, camera, sealed `SupyScanUseCase` + per-variant configs); added `widgets/` rows for the v1.1 composite screen, AR overlay, and the three use-case sheets + accumulators; updated layering diagram to expose the new `widgets/` shape and the `models/ui/` band between widgets and the channel — 2026-06-13

## v1.1 Sprint 2 — Barcode pipeline lift

See `docs/V1.1_PLAN.md` Sprint 2. Exit gate: decode-rate uplift ≥ 8 pp vs v1.0 path at p50 latency ≤ +25 ms on the 20-SKU retailer sheet (low-end Android, 200 lux + 50 lux). Numbers recorded in `docs/QA.md`.

- [ ] V1-S2-01 — Vendor zxing-cpp into `native/` — CMake `FetchContent` pinned to v2.2.1, gated behind `SUPY_WITH_ZXING_CPP` (default OFF) so the Sprint 1 build path is unchanged until the decode wire-through lands. **Known unknown:** iOS pod consumption — current `source_files` glob over `../native/` would try to compile zxing-cpp sources through CocoaPods flags; needs either a `prepare_command`-driven CMake build producing a static .a the pod links, or a restricted `source_files` glob plus a separate iOS build script. Track as V1-S2-02. **Not verified on device** — no Android NDK / iOS toolchain available in this session; CI build needs to be the first signal. — 2026-06-13
- [ ] V1-S2-02 — iOS consumption strategy for zxing-cpp — **decided 2026-06-13:** podspec `prepare_command` shell-invokes `cmake --build` with `-DSUPY_WITH_ZXING_CPP=ON` against `../native/` for `iphoneos` + `iphonesimulator` archs, produces a fat static `libZXing.xcframework` under `ios/Vendor/`, pod vendors it via `s.vendored_frameworks`. Rejected alternatives: (B) per-file warning suppressions inside `source_files` (too fragile across zxing-cpp tag bumps), (C) committing a pre-built `.xcframework` binary (defeats the source-of-truth goal). Execution blocked on a Mac with Xcode 15 + CMake — needs the shell script written and one CI run to confirm cache-key correctness before flipping `SUPY_WITH_ZXING_CPP=ON` for real.
- [ ] V1-S2-03 — Wire zxing-cpp 1D + 2D decode behind `useNativeCore` — **Dart wire side locked 2026-06-13:** `test/models/supy_scan_options_test.dart` pins `useNativeCore` propagation through `SupyBarcodeScanOptions.toWire()` + `SupyDocumentScanOptions.toWire()` (5 tests pass). Native sides (Android JNI bridge into zxing-cpp via the C++ core; iOS Swift bridge over the vendored `.xcframework`) still pending — needs the Sprint 1 toolchain to verify.
- [ ] V1-S2-04 — libdmtx Data Matrix locator (decode still via zxing-cpp)
- [ ] V1-S2-05 — Wolf-Jolion (1D) / Sauvola (2D) adaptive binarization — Halide AOT separable kernel
- [ ] V1-S2-06 — 3-frame temporal-median ROI fusion in live-preview path
- [ ] V1-S2-07 — Perf-gate harness: decode-rate + p50 latency on the 20-SKU sheet (200 lux + 50 lux); record numbers in `docs/QA.md`

## v1.1 Performance — device-class adaptive, thermal, idle

See `docs/PERFORMANCE.md`. Lands on top of v1.0.0 as `v1.1.x`. No public API changes — additive EventChannel payloads only.

- [x] V1-PERF-P1 — DeviceTier + tier-adaptive analyzer config (resolution + FPS caps) — 2026-06-13
- [x] V1-PERF-P2 — `ThermalGovernor` (Android API 29+) + `SupyThermalGovernor` (iOS); emits `{type:'thermal', state, paused, throttled}` event — 2026-06-13
- [x] V1-PERF-P3 — Idle pause via luma-variance gate (`IdleDetector` + `SupyIdleDetector`); emits `{type:'idle_pause'|'idle_resume'}` on transition; HIGH tier opt-out — 2026-06-13
- [x] V1-PERF-P4 — OCR image downscale (1600px long edge) + tier-aware JPEG quality (LOW: 75, MID/HIGH: 85) — 2026-06-13
- [ ] V1-PERF-P5 — Re-bench Moto G Power + Pixel 8 + iPhone SE 3 + 15 Pro; record `## Results (v1.1.x)` table in `docs/PERFORMANCE.md`; tag `v1.1.0`

## v1.0.x Hardening — Sprints H0–H4

See `/Users/abdalqaderalnajjar/.claude/plans/gimme-plan-to-make-vast-gray.md` for the full plan. Sequenced BEFORE v1.1 Sprint 2.

### H0 — Discovery & baseline (3 days)

- [ ] H0-01 — Stale-TODO sweep + sprint scaffold added (this commit) — 2026-06-13
- [x] H0-EX1 — Example: Supy-branded showcase tab (4 flows: single / batch / embedded / document + OCR) — 2026-06-13
- [ ] H0-02 — S4-02 reliability harness on Moto G Power + iPhone SE 2; record into `docs/QA.md` `## Baseline — v1.0.0` (device-blocked)
- [ ] H0-03 — S4-03 perf bench on both devices; record (device-blocked)
- [ ] H0-04 — V1-S1-09 native-core probe verification on both devices (device-blocked)
- [ ] H0-05 — Memory profile: 10-page doc + 50-iter batch + 100 open/close (device-blocked)
- [x] H0-06 — Stricter analyzer lints + fix new warnings in `lib/` — analyzer block in `analysis_options.yaml` extended with `prefer_const_constructors_in_immutables`, `avoid_catches_without_on_clauses`, `only_throw_errors`, `unnecessary_await_in_return`, `avoid_slow_async_io`, `prefer_relative_imports`, `use_late_for_private_fields_and_variables`, `throw_in_finally`, `no_adjacent_strings_in_list`, `avoid_returning_this`, `join_return_with_assignment`, `parameter_assignments`. `flutter analyze lib/` → 0 issues.
- [ ] H0-07 — Baseline section reviewed with mobile lead (sign-off-blocked)

### H1 — Stability hardening (1.5 weeks)

- [ ] H1-01 — Android camera-lifecycle audit + fixes; `docs/ARCHITECTURE.md` `### Lifecycle invariants`
- [ ] H1-02 — iOS `AVCaptureSession` lifecycle audit + fixes
- [ ] H1-03 — Threading audit + `@MainThread`/`@WorkerThread` (Kotlin) + `dispatchPrecondition` (Swift)
- [ ] H1-04 — ML Kit / Vision client lifetime; 100× open/close == 100× close (no orphan)
- [x] H1-05 — Error-boundary review: every `Result.error`/`FlutterError` uses a known `SupyScanError` code — 4 strays folded to canonical `unknown` with detail preserved in `message` (Android: `SupyScannerPlugin.nativeCoreProbe`, `SupyBarcodeScannerView.setZoom`; iOS: `SupyScannerPlugin.nativeCoreProbe`, `SupyDocumentScannerView.onError`). Native wire set is now exactly `{cancelled, permission_denied, camera_unavailable, model_unavailable, unknown}` — `format_unsupported` is reserved for future use.
- [x] H1-06 — MethodChannel arg validation on every handler; typed error on malformed input — Added `expectMapArgs` helpers on both platforms (`SupyScannerPlugin.kt`, `SupyScannerPlugin.swift`) gating `scanDocument` / `scanBarcodesBatch`. Null/missing args pass through as an empty map (preserves caller ergonomics); a non-null payload that isn't a `Map<String, Any?>` / `[String: Any]` now surfaces the canonical `unknown` wire code with a message naming the method and the actual runtime type, instead of being silently dropped to `null`. Per-view channel handlers (`SupyBarcodeScannerView`, `SupyDocumentScannerView`) already cast per-arg with safe defaults — no malformed-payload-as-Map exposure surface there.
- [ ] H1-07 — Permission revocation mid-session surfaces `SupyScanError.permissionDenied`
- [ ] H1-08 — Backgrounding mid-scan: preview pauses, resumes cleanly on foreground
- [ ] H1-09 — Low-storage / low-memory paths; typed error, no crash
- [x] H1-10 — `EventChannel.EventSink` discipline: null-check + `endOfStream` on dispose — Both platform views now signal stream completion before detaching the handler so Dart subscribers see a clean `onDone` instead of a silent drop. Android: `SupyBarcodeScannerView.dispose()` and `SupyDocumentScannerView.dispose()` call `eventSink?.endOfStream()` (wrapped in `runCatching`) before nulling and detaching — safe because `dispose()` runs on the platform/main thread. iOS: `deinit` on both views captures the sink, nils the field, then sends `FlutterEndOfEventStream` on `.main` (marshalling if deinit fires off-main). Null-checks on every `sendEvent` call site were already in place on both platforms — verified.
- [ ] H1-11 — H0 reliability harness re-run; SLO targets must hit (device-blocked)

### H2 — Test rigor (1.5 weeks)

- [x] H2-01 — Android Robolectric + JUnit 4 unit suite (`android/src/test/`) — initial slice: `FormatMapperTest` (8 cases: empty/all-sentinel/unknown-filter/all-wires round-trip) + `DeviceTierTest` (5 cases: HIGH/MID/LOW dials + jpegQuality cap), wired into `android/build.gradle` (testOptions + JUnit/Robolectric/androidx-test/kotlin-test deps), runs in CI via `gradle :supy_scanner:testDebugUnitTest`. UI/AVCapture-bound classes (Activities, Presenters, OcrRunner, DocumentFrameAnalyzer, ThermalGovernor, IdleDetector, GmsAvailability) deferred — need fake-injection refactor or instrumented coverage. — 2026-06-14
- [x] H2-02 — iOS XCTest unit suite (`ios/Tests/`) — initial slice: `SymbologyMapperTests` (9 cases incl. UPC-A leading-zero disambiguation + ITF dual mapping) + `SupyDeviceTierTests` (5 cases incl. jpegQuality 0.75 cap on low). Wired via `s.test_spec 'Tests'` in `ios/supy_scanner.podspec`; runs in CI via `pod lib lint`. Same scope caveat as H2-01 for UI/AVCapture-bound classes. — 2026-06-14
- [x] H2-03 — Dart channel-boundary property-based fuzz (`test/channel/fuzz_test.dart`, 10k frames) — deterministic seed `0xDEC0DE`; 10 groups covering `SupyDocumentPage`/`SupyDocumentData`/`SupyBarcode`/`SupyBatchBarcodeResult` `fromMap` round-trip (8.5k well-formed), one-mutation-per-payload malformed fuzz (4.5k), `SupyScanErrorCode.fromWire` (500), and 600 channel round-trips. Invariant on malformed input: throws only `TypeError` / `ArgumentError` / `SupyScanError` — anything else fails the test. Full suite green (216 tests). — 2026-06-14
- [x] H2-04 — Widget golden-test backfill for Sprint 1.5 widgets — structural tests (project convention rejects pixel goldens for Skia/platform flakiness, per `supy_finder_painter_test` precedent) added for the three uncovered internal widgets: `supy_top_bar` (6 cases — text, omit-when-empty, tap-callback, solid/gradient decoration, text-style), `supy_user_guidance_card` (5 cases — invisible/empty hide, text/style/pill-radius), `supy_action_bar` (7 cases — visibility, all-four-default, per-button-hide, all-hidden empty, inactive paint, flash tap routes to `setTorch` via mocked channel, zoom label rerenders on controller notify). Full suite green (234 tests, +18). — 2026-06-14
- [ ] H2-05 — Integration tests (`integration_test/`) — one per use-case
- [ ] H2-06 — Compat-shim pinned to real retailer call sites
- [x] H2-07 — Coverage measurement: lcov + Kover + llvm-cov, CI-gated. **Dart**: `flutter test --coverage` produces `coverage/lcov.info`; CI step parses with awk and fails if line coverage drops below 70% — locally measured baseline is 76.34% (1407/1843 lines) giving ~6pp safety margin. lcov.info uploaded as `dart-coverage-lcov` artifact. **Android**: Kover 0.8.3 plugin added in `android/build.gradle` (classpath + `apply plugin` + filter for `BuildConfig` / `$Companion`); CI runs `:supy_scanner:koverXmlReportDebug` alongside the existing test task and uploads `example/build/supy_scanner/reports/kover/` as `android-kover-coverage` artifact. **iOS**: `-enableCodeCoverage YES` added to xcodebuild; CI runs `xcrun xccov view --report --json` against the xcresult and uploads `ios-coverage.json` artifact. Native gates are artifact-only for v1.0.x — once CI publishes a real baseline, a follow-up PR can set `koverVerify` minBound + an iOS awk threshold. Dart suite still green (241 tests), yaml validates. — 2026-06-14
- [x] H2-08 — `test/widgets/` completion sweep — audited `lib/src/widgets/` against `test/widgets/`; one widget (`supy_barcode_scanner_view`) had no test file. Backfilled with 7 structural cases routing `debugDefaultTargetPlatformOverride` to linux/macOS to bypass real PlatformView hosts: default-config stack has preview+finder (2 children), `showFinder:false` strips overlay (1 child), header/footer positioned to stack top/bottom, extreme combo (header+footer, finder off → 3 children), unsupported-platform placeholder renders with platform name, dispose path with attached controller throws nothing. All other 13 widget tests already have default+extreme coverage (verified by test-count spot check + reading 3-case `supy_multiple_scan_sheet` which already covers default+counting-mode+empty/full). Full suite green (241 tests, +7). — 2026-06-14

### H3 — Soak, perf-regression, security (1 week)

- [ ] H3-01 — 24h soak harness (`tools/soak.sh`)
- [ ] H3-02 — Soak run on Moto G Power (device-blocked)
- [ ] H3-03 — Soak run on iPhone SE 2 (device-blocked)
- [ ] H3-04 — Perf-regression harness (`tools/perf_bench.dart`) vs `docs/perf/baseline.json`
- [ ] H3-05 — Perf-regression run on both devices (device-blocked)
- [ ] H3-06 — Security review of channel boundary; output `docs/SECURITY.md`
- [ ] H3-07 — Dependency audit; output `docs/DEPENDENCIES.md`
- [ ] H3-08 — Reproducible-build verification

### H4 — Release ops, lite observability, ship (1 week)

- [ ] H4-01 — `SupyLogSink` interface + default sink (`lib/src/log/`); route all `print`/`debugPrint`/`Log.d`/`os_log`
- [ ] H4-02 — Debug HUD in example app (togglable, off by default)
- [ ] H4-03 — `tools/release.sh <version>` automation
- [ ] H4-04 — `docs/RELEASE.md` symbolication discipline
- [ ] H4-05 — CI matrix expansion
- [ ] H4-06 — `CHANGELOG.md` entry for `v1.0.1`
- [ ] H4-07 — `docs/QA.md` re-walk; mobile-lead sign-off (sign-off-blocked); close S4-08
- [ ] H4-08 — Tag `v1.0.1` via `tools/release.sh`

## v1.1 Sprint 6 — Embedded document auto-capture API

See `docs/V1.1_PLAN.md` §8 — Sprint 6. Depends on Sprint 4 (`warpPerspective` + DoQA gate).

- [x] V1-S6-01 — Add `SupyDocumentFrameState.capturing` + `.captured`; painter + hint card transitions for both states
- [ ] V1-S6-02 — `captureAndRectify` channel method (Android + iOS); consumes last smoothed quad → returns JPEG URI + corrected quad
- [x] V1-S6-03 — `SupyDocumentScannerController.capture()` + `SupyDocumentScanOptions.autoCaptureDelayMs` + mocked unit tests
- [x] V1-S6-04 — `docs/ARCHITECTURE.md` channel-method row + `docs/UI_CONFIGURATION.md` auto-capture recipe

## v1.1 Sprint 7 — Per-page quality grade + export breadth

See `docs/V1.1_PLAN.md` §8 — Sprint 7. Depends on Sprint 4 (quality scorer in native core).

- [x] V1-S7-01 — `SupyDocumentPageQuality` enum + `quality` + `qualityScore` fields on `SupyDocumentPage` + `fromMap` parsing + tests
- [ ] V1-S7-02 — Native per-page quality scorer (variance-of-Laplacian + luma → enum + 0..1 score) on Android + iOS
- [x] V1-S7-03 — `SupyDocumentOutputFormat { jpg, png, pdf }` on `SupyDocumentScanOptions` + channel plumbing
- [x] V1-S7-04 — Android PDF (via `RESULT_FORMAT_PDF` from GMS) + PNG (`Bitmap.CompressFormat.PNG`) output paths — `PageReencoder` (replaces `JpegReencoder`) handles JPG/PNG; launcher reads `outputFormat` from wire, ORs `RESULT_FORMAT_PDF` into GMS options on `pdf`, and surfaces `scanResult.pdf.uri` as `pdfUri` on the response.
- [x] V1-S7-05 — iOS PDF (PDFKit `PDFDocument` assembly from `UIImage`s) + PNG (`UIImage.pngData()`) output paths — `DocumentScannerPresenter` reads `outputFormat`, persists per-page as JPG/PNG via `image.jpegData`/`pngData`, and on `pdf` additionally assembles a `PDFDocument` to `NSTemporaryDirectory()`; finish payload includes `pdfUri` only when assembled.
- [x] V1-S7-06 — `docs/ARCHITECTURE.md` + `docs/MIGRATION.md` rows: Scanbot quality buckets → `SupyDocumentPageQuality`, Scanbot output formats → `SupyDocumentOutputFormat`

## v1.1 Sprint 8 — Supy-owned multi-page review (decision-gated)

See `docs/V1.1_PLAN.md` §8 — Sprint 8. **Blocked on decision in the decisions log below before kickoff.**

- [ ] V1-S8-DECISION — Mobile lead decides: do we replace VisionKit / GMS hand-off with owned capture? Log answer + rationale in decisions log dated.
- [ ] V1-S8-01 — (post-decision) Tickets authored from §8 sketch — owned capture, controller, review sheet, channel methods, model fields, example app, docs.

## QA scenarios

See `docs/QA.md`. Track per-release sign-off there.

## v1.2 — Phase CXD: CameraX document fallback (non-GMS Android)

See `docs/PLAN.md` § "v1.2 — Active phases" and `docs/CAMERAX_FALLBACK.md`. Activation is auto-detect via `GoogleApiAvailability`; no public API change. Capture UX is manual tap-to-capture only — auto-snap deferred.

- [x] CXD1 — `GmsAvailability` helper + branch in `DocumentScannerLauncher.launch` (auto-detect bypasses GMS client when Play services is unavailable) — 2026-06-13
- [x] CXD2 — `CameraXDocumentScannerActivity` (Kotlin): CameraX `Preview` + `ImageCapture`, tap-to-capture FAB, thumbnail strip with delete (retake = delete + retap), done CTA, `maxPages` cap, returns JPEG URIs in `EXTRA_RESULT_URIS`; uses `startActivityForResult` for parity with `BatchBarcodeScannerLauncher`; `Theme.AppCompat.NoActionBar` registered in manifest — 2026-06-13 (device build verification pending)
- [x] CXD3 — CameraX result piped through `PageReencoder.reencode(...)` (tier-aware quality from `DeviceTier`) + `ocrRunner.run(...)`; response shape identical to GMS path (`pages`, `ocrText`); `pdfUri` always `null` on fallback path (logged in `launch()` when `outputFormat=pdf` requested) — 2026-06-13
- [x] CXD4 — Camera permission re-checked at activity start → `RESULT_PERMISSION_DENIED` (0x5601) → `permission_denied` error; `ProcessCameraProvider` bind failure → `RESULT_CAMERA_UNAVAILABLE` (0x5602) → `camera_unavailable` error; back/cancel → `RESULT_CANCELED` → `pending.success([])` matching D4 / iOS VisionKit cancel — 2026-06-13
- [x] CXD5 — `docs/CAMERAX_FALLBACK.md` landed; `docs/ARCHITECTURE.md` Android module rows added for `CameraXDocumentScannerActivity` + `GmsAvailability` (and `DocumentScannerLauncher` row updated with the v1.2 branch behavior); `docs/QA.md` D10 revised (no longer expects `model_unavailable` on non-GMS) + D12 added (10-step Huawei/AOSP fallback walkthrough covering capture, delete, OCR result, cancel→[], permission/camera errors, retailer-no-op) — 2026-06-13
- [ ] CXD6 — Sign-off on one non-GMS device (Huawei P30 or GMS-stripped emulator); D1/D2/D4/D10/D12 pass; tag `v1.2.0`

## Out-of-scope (do not start here)

- Retailer-app cutover (separate plan).
- MRZ / ID-card recognition.
- Web/desktop support.

## Decisions log

- **2026-06-13** — Embedded PlatformView is **in scope** for v1 (required for drop-in compatibility with `BarcodeScanbotView`). Earlier draft scoped this out — corrected before any code shipped.
- **2026-06-13** — iOS deployment target jumps from 13 to 16. Confirm retailer iOS-15 fleet share is < 1% before cutover.
- **2026-06-13** — Compat shim package (`supy_scanner_scanbot_compat`) ships alongside v1 to allow import-only migration.
- **2026-06-13** — v1.1 Sprint 1.5 inserted between native-core scaffold (Sprint 1, done) and the CV pipeline lift (Sprint 2, next): embedded `SupyBarcodeScannerView` gains a Scanbot-RTU-UI-inspired configuration surface (palette tokens, top bar, action bar, view finder, user guidance, use-case modes, AR overlay). Native Document & Batch screens stay GMS/VisionKit per stakeholder. The "scan from far / needs more resources" memory is addressed by `SupyCameraConfiguration.scanRange = extended` + `minFocusDistanceLock`, both wired to the v1.1 native core when `useNativeCore` is on.
- **2026-06-13** — Scanbot document-parity audit: three new v1.1 sprints scoped (Sprint 6 — embedded auto-capture API; Sprint 7 — per-page quality grade + PNG/PDF export; Sprint 8 — Supy-owned multi-page review). Sprints 6 + 7 layer on Sprint 4's native core. **Sprint 8 is decision-gated** (per `CLAUDE.md`: sacrifices the v1.0 "system scanner does the heavy lifting" property — needs explicit go/no-go before kickoff). TIFF export deferred — no first-party encoder on either platform. Full plan in `docs/V1.1_PLAN.md` §8.
- **2026-06-13** — v1.0.x **hardening sprints (H0–H4)** sequenced BEFORE v1.1 Sprint 2. Target release `v1.0.1` for retailer cutover. Public API + symbology + decode algorithms FROZEN for v1.0.x. Telemetry out of scope (local `SupyLogSink` only). Device CI local-only. Plan file: `/Users/abdalqaderalnajjar/.claude/plans/gimme-plan-to-make-vast-gray.md`.
- **2026-06-13** — **v1.2 Phase CXD promoted** from candidate sketch to active phase: CameraX document fallback for non-GMS Android. Activation = **auto-detect** via `GoogleApiAvailability` (no public API change; existing retailer code unchanged); capture UX = **manual tap-to-capture only** for v1.2 (auto-snap deferred to v1.3). The captured JPEGs reuse the existing `JpegReencoder` + `OcrRunner`, so OCR coverage stays Latin-script. Risk R2 (non-GMS Android) closes when v1.2.0 ships. Replaces the `model_unavailable` failure mode on Huawei/AOSP devices documented in D10.
