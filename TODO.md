# supy_scanner: master specification and refactor guide

**Audience:** an AI coding agent executing this work, plus the engineers reviewing it.
**Purpose:** define the target architecture completely, and give an executable path from the current `supy_scanner` implementation to it.
**Status:** authoritative. Where this document and older specs, tickets, or code comments disagree, this document wins.

---

# PART 0: HOW TO USE THIS DOCUMENT

Read this part fully before touching any code.

## 0.1 Your operating rules

1. **Discovery before change.** Part 2 is a discovery protocol. Run it and produce the inventory artifact before editing anything. Do not assume the repository matches any tree shown in this document.
2. **Strangler pattern, always.** Never delete a working path before its replacement proves parity on the corpus. Old and new coexist behind an Unleash flag until the new path wins on measured metrics. This matches the pattern already used for the order module refactor in `supy-mobile`.
3. **One phase per branch, one phase per PR.** Phases are defined in Part 3. Do not batch them. A phase that touches 40 files is unreviewable and will be rubber-stamped, which defeats the point.
4. **Every phase has an acceptance gate.** They are written as runnable commands. A phase is not done until its gate passes. Do not proceed to the next phase with a red gate.
5. **Stop and ask on the open questions.** Part 8 lists decisions you must not make unilaterally. If a phase depends on one, stop, state which question blocks you, and wait. Guessing here produces weeks of rework.
6. **Never invent metrics.** If this document says "mean IoU at least 0.95", that number comes from a real harness run on the real corpus. Do not report a number you did not measure. If the harness is not built yet, say the gate cannot be evaluated.
7. **Follow Supy Flutter standards** for all Dart: Clean Architecture with dependencies pointing inward, `Bloc` never `Cubit`, `Either<Failure, T>` from repositories and usecases, the domain never throws, `context.push` with path constants, `get_it` (singletons for services/repos/usecases/datasources, factory for BLoCs), design tokens only with no raw hex or inline `TextStyle`.
8. **Supy writing rule:** no em dashes or en dashes in any output, including code comments, commit messages, PR descriptions, and UI copy. Use a hyphen, a comma, a colon, or split the sentence.

## 0.2 What "done" means for the whole programme

The refactor is complete when all of these hold:

- One C++ core produces every processed pixel on every platform.
- A native Android app with zero Flutter on its classpath can consume the SDK, and CI proves it.
- A native iOS app with zero Flutter can consume the SDK, and CI proves it.
- The Flutter app consumes the same core and produces byte-identical output to both.
- The scanner UI carries Supy brand identically on all three, enforced by a pixel-level brand assertion in CI.
- Every legacy scanner code path is deleted, not merely disabled.

## 0.3 Document map

| Part | Contents |
|---|---|
| 1 | Target architecture, in brief |
| 2 | Discovery protocol: inventory the current implementation |
| 3 | Migration phases with acceptance gates |
| 4 | Target spec: the image processing pipeline |
| 5 | Target spec: multi-platform distribution |
| 6 | Target spec: UI and Supy branding |
| 7 | Anti-patterns: known ways this goes wrong |
| 8 | Open questions you must not answer alone |

---

# PART 1: TARGET ARCHITECTURE

## 1.1 The core decision

Detection and enhancement both live in one platform-free C++ core. Platform code is a thin binding.

```
   L3  UI          ┌──────────────┬─────────────┬──────────────┐
   optional        │ Compose      │ SwiftUI     │ Flutter      │
                   │ screens      │ screens     │ widgets      │
                   └──────┬───────┴──────┬──────┴──────┬───────┘
   L2  Public SDK  ┌──────▼───────┬──────▼──────┬──────▼───────┐
   idiomatic       │ io.supy:     │ SupyScanner │ supy_scanner │
   per language    │  scanner     │ SPM+Pods    │ pub.dev      │
                   │ Kotlin       │ Swift       │ Dart         │
                   │ coroutines   │ async/await │ Either       │
                   └──────┬───────┴──────┬──────┴──────┬───────┘
   L1  Platform    ┌──────▼──────────────▼─────────────▼───────┐
   detection       │ VisionDetector (iOS only, optional)       │
   adapters        │ MlKitTurnkey   (Android only, optional)   │
                   └──────────────────┬────────────────────────┘
   L0  Core        ┌──────────────────▼────────────────────────┐
   C++17 + OpenCV  │ C ABI: supy_scanner.h                     │
                   │ detect, rectify, enhance, encode          │
                   │ ZERO platform dependencies                │
                   │ Compiles and tests on Linux CI            │
                   └───────────────────────────────────────────┘
```

**Two rules govern everything:**

- **L0 has no platform dependencies at all.** No JNI, no Objective-C, no Dart. This is what lets the pipeline be unit tested on Linux in seconds, and it is what makes the SDK consumable without Flutter.
- **The three L2 surfaces are siblings, not a chain.** Flutter binds to the C ABI directly. It does not call the Kotlin SDK. A chain would add a JNI hop per call and inherit every Kotlin-side bug.

## 1.2 Correction to earlier assumptions

If any existing ticket, spec, or code comment says ML Kit Document Scanner provides per-frame quad detection on Android, that is wrong and must be corrected wherever found.

ML Kit Document Scanner is a **full-UI activity flow**. It ships its own viewfinder and preview screens and returns finished JPEG or PDF pages. There is no API to hand it a CameraX frame and receive four corners. It also requires at least 1.7 GB device RAM (throws `MlKitException(UNSUPPORTED)` below that), requires Google Play Services, and downloads its models and UI on first use.

**Consequences:**

| | Wrong assumption | Reality |
|---|---|---|
| Android live detection | ML Kit | Shared C++ classical detector, the only option |
| iOS live detection | Vision | Correct, `VNDetectDocumentSegmentationRequest` is a real per-frame API |
| ML Kit role | Primary detector | Optional turnkey fallback only |

This makes the C++ detector production-critical rather than a fallback. It also makes the core genuinely standalone-useful, which is what the multi-platform requirement needs.

## 1.3 Effort

| Track | Weeks |
|---|---|
| Pipeline core (detect, rectify, enhance, encode) | 8 |
| Multi-platform packaging and conformance | 3 |
| UI on three platforms, branded, with parity gate | 5 net |
| **Total** | **~16 weeks** |

---

# PART 2: DISCOVERY PROTOCOL

Run this first. Produce `docs/refactor/00-inventory.md` and stop for review before any code changes.

## 2.1 Inventory the current implementation

```bash
# Locate every scanner-related source file
rg -l --type dart -i 'scanner|scanbot|docutain|perspective|crop|ocr' lib/ packages/
rg -l --type kotlin -i 'scanner|camera|mlkit|document' android/
rg -l --type swift  -i 'scanner|camera|vision|document' ios/

# Existing dependencies that matter
rg -n 'scanbot|docutain|opencv|image|camera|mlkit|google_ml' pubspec.yaml
rg -n 'scanbot|docutain|opencv|mlkit|camerax' android/**/build.gradle*
rg -n 'Scanbot|Docutain|OpenCV' ios/Podfile ios/**/*.podspec

# Any existing native code
fd -e cpp -e cc -e h -e hpp . --exclude build
fd 'CMakeLists.txt|\.podspec|ffigen' .

# Existing ports and adapters
rg -n 'abstract (class|interface class).*Scanner|ScannerPort|implements Scanner' lib/

# Feature flags already in play
rg -n 'unleash|isEnabled\(' lib/ | rg -i 'scan|camera|ocr'
```

## 2.2 Fill in the inventory artifact

Answer each question with file paths and line references, not prose. Write "not present" where nothing exists. Do not speculate.

```markdown
# Scanner refactor: current state inventory

## A. Entry points
- Where does a scan start today? (route, widget, method)
- How many distinct entry points exist? (invoice capture, gallery import, share sheet, other)

## B. Abstraction layer
- Does a `ScannerPort` or equivalent exist? Path:
- What is its exact method signature list?
- How many concrete adapters implement it? Paths:
- Do repositories/usecases return `Either<Failure, T>`, or do they throw?

## C. Processing
- What performs perspective correction today? (vendor SDK, Dart package, native, nothing)
- What performs enhancement today?
- What performs binarisation today?
- Is any processing done in pure Dart? Paths and image sizes:
- How many times is an image encoded/decoded per capture? Trace it:

## D. Detection
- What detects the document today?
- Is detection live (per frame) or only post-capture?
- Is there a manual crop editor? Path:

## E. Vendor SDKs
- Scanbot present? Version, where initialised, license key handling:
- Docutain present? Same:
- ML Kit present? Which modules:
- What is each vendor SDK's current contribution to APK/IPA size?

## F. State management
- Which Bloc(s) own scanner state? Paths:
- Any Cubit in the scanner path? (must be migrated to Bloc)
- Where is captured-page state held? Are full-resolution bytes in Bloc state?

## G. UI
- How many scanner screens exist? Paths:
- Is any hex literal, `Colors.*`, or inline `TextStyle` present in them? Count and paths:
- Is there Arabic localisation for scanner strings? Coverage:
- Is RTL handled in the crop overlay?

## H. Native
- Any existing Kotlin/Swift scanner code? Paths:
- Is there an existing AAR/xcframework/podspec published from this repo?

## I. Tests
- Existing scanner test files and what they cover:
- Is there any labelled image corpus? Path and size:
- Current Dart coverage on scanner paths:

## J. Memory and performance
- Are full-resolution images held in memory? Where:
- Any known OOM reports or crash clusters on the scan path? (check Sentry)
- Current measured shutter-to-preview latency, if known:
```

## 2.3 Produce the mapping table

For every file found in 2.1, assign exactly one disposition:

| Disposition | Meaning |
|---|---|
| `KEEP` | Already matches target. No change. |
| `MOVE` | Correct code, wrong layer or package. Relocate only. |
| `REWRITE` | Concept survives, implementation is replaced. |
| `WRAP` | Becomes an adapter behind the new port. |
| `DELETE` | Removed after the replacement proves parity. |

Output `docs/refactor/01-mapping.md` as a table: current path, disposition, target path, phase number, one-line rationale.

**Stop here and wait for review.** The mapping table is the contract for everything that follows. Getting it wrong is expensive; getting it reviewed costs an hour.

---

# PART 3: MIGRATION PHASES

Ten phases. One branch and one PR each. Commit with Conventional Commits per `commitlint` (never the `hotfix` type).

## Phase 0: Corpus and harness

**Why first:** without measurement, every parameter change afterwards is a coin flip, and there is no way to prove the new path beats the old one. This feels like a two-week detour and it is the difference between tuning on evidence and tuning on opinion.

**Do:**
1. Create `supy-scanner-corpus` (separate repo, git-lfs). Collect and label 250+ images per the matrix in section 4.15.
2. Build the metrics harness: quad IoU in the rectified frame (ICDAR SmartDoc 2015 protocol), SSIM, OCR character error rate.
3. Run the harness against the **current** implementation. This baseline is what the refactor must beat.

**Gate:**
```bash
./tools/harness run --impl=legacy --corpus=../supy-scanner-corpus
# must emit docs/refactor/02-baseline.md with IoU, SSIM, CER per category
test -f docs/refactor/02-baseline.md
```

**Blocked by:** open question Q5 (corpus consent).

## Phase 1: Monorepo skeleton and native build

**Do:**
1. Create the target tree (section 5.5). Do not move existing code yet.
2. Write `core/include/supy_scanner.h` exactly as section 4.2 defines. This header is a contract; changing it later is expensive.
3. Stub every function to return `SC_OK` with a passthrough.
4. Build OpenCV trimmed per section 4.1. Produce `.so` x 3 ABIs, `.xcframework`, host `.dylib`/`.so`.
5. Create three sample apps: Android (Kotlin, zero Flutter), iOS (Swift, zero Flutter), Flutter example. Each calls `sc_version()` and prints it.
6. Wire CI: all three sample apps build on every PR.

**Gate:**
```bash
./tools/build-core.sh --all
llvm-readelf -l android/scanner-core/src/main/jniLibs/arm64-v8a/libsupy_scanner_core.so | grep -q 'LOAD.*0x4000'   # 16 KB alignment
./tools/check-sizes.sh   # .so <= 3.5 MB/ABI, .xcframework <= 4 MB
./gradlew :sample-app:assembleDebug
xcodebuild -project ios/SampleApp/SampleApp.xcodeproj build
cd flutter/example && flutter build apk --debug
./tools/assert-no-flutter.sh android/sample-app ios/SampleApp   # must exit 0
```

The last check is load-bearing. It locks the "no Flutter on the classpath" constraint into CI **before** any code exists to violate it. Retrofitting standalone-consumability onto a Flutter-first plugin is a rewrite, not a refactor.

## Phase 2: Core detection and rectification

**Do:** implement pipeline stages 0 through 4 (section 4.3 to 4.7): decode-once, classical detector with LSD fallback, corner ordering, homography with aspect-ratio recovery, anti-aliased warp, resolution policy, JPEG encode.

**Gate:**
```bash
cmake --build build --target core_tests && ctest --test-dir build --output-on-failure
./tools/harness run --impl=core --corpus=../supy-scanner-corpus
# mean IoU >= 0.93, P95 >= 0.88, catastrophic (IoU < 0.80) <= 3%
./tools/harness compare --baseline=docs/refactor/02-baseline.md --new=core
```

## Phase 3: Flutter binds to the core

**Do:**
1. `ffigen` bindings from the header. Commit as generated, never hand-edit.
2. Worker isolate with the request/response protocol and `NativeFinalizer` handle lifecycle.
3. `DocumentProcessorPort` in `domain/ports/`, `NativeProcessorAdapter` in `data/adapters/`.
4. `WRAP` the existing implementation as `LegacyScannerAdapter` behind the same port.
5. Unleash flag `mobile.scanner.native_core` selects between them. Default off.

**Gate:**
```bash
flutter test --coverage   # >= 80% on new code
flutter test integration_test/ffi_lifecycle_test.dart   # 1000 cycles, RSS flat
dart format --set-exit-if-changed lib test && flutter analyze
```
Both adapters must satisfy the identical port test suite.

## Phase 4: Core enhancement

**Do:** stages 5 through 11 (section 4.8 to 4.14): deskew, orientation, illumination (morphological and guided filter), background whitening with colour preservation, tone-curve contrast, denoise, unsharp with halo control, Sauvola via integral images.

**Gate:**
```bash
ctest --test-dir build --output-on-failure
./tools/harness run --impl=core --metric=cer
# CER must improve >= 25% vs the Phase 0 legacy baseline
./tools/bench --op=refilter   # <= 50 ms
./tools/bench --op=process --size=2200   # <= 900 ms
```

## Phase 5: Flip the flag, delete the legacy path

**Do:**
1. Ramp `mobile.scanner.native_core` to 100% via Unleash, staged.
2. Watch Sentry and the retake-rate metric for one full release cycle.
3. **Only then** delete `LegacyScannerAdapter` and every file marked `DELETE` in the mapping table.
4. Remove the now-unused vendor SDK dependencies and their license key handling.

**Gate:**
```bash
rg -n 'LegacyScannerAdapter|scanbot|docutain' lib/ android/ ios/   # must return nothing
./tools/check-sizes.sh --report-delta   # net APK/IPA change documented
```

Do not run this phase until Phase 4's gate is green in production telemetry, not just in CI.

## Phase 6: Android native SDK

**Blocked by:** open question Q9. If no native Android consumer exists, skip Phase 6 and Phase 7 entirely and record the decision.

**Do:** JNI bridge, `SupyScannerProcessor` Kotlin API with coroutines, module split (`scanner-core`, `scanner-camera`, `scanner-ui`, `scanner-mlkit`, `scanner-ocr`, `scanner-bom`), CameraX capture. Flutter plugin declares `api "io.supy:scanner-core"` and ships **no** `.so` of its own (section 5.3.1).

**Gate:**
```bash
./gradlew :scanner-core:test :scanner-camera:test connectedAndroidTest
./tools/harness run --impl=android-sdk
./tools/conformance --targets=core,android   # byte-identical encoded output
./tools/assert-single-so.sh   # hybrid app loads exactly one libsupy_scanner_core.so
```

## Phase 7: iOS native SDK

**Do:** Swift wrapper with async/await, module split, AVFoundation capture, `VisionDetector`, SPM `binaryTarget` plus CocoaPods podspec. The Flutter podspec declares `s.dependency 'SupyScannerCore'` and never vendors the framework (section 5.3.2). Dart FFI uses `DynamicLibrary.process()` on iOS because the framework is static.

**Gate:**
```bash
swift test && xcodebuild test -scheme SupyScannerCore
./tools/conformance --targets=core,android,ios   # all three byte-identical
```

## Phase 8: Design tokens and UI config

**Do:**
1. `design/tokens.json` per section 6.2. Generate `SupyScannerTokens.{kt,swift,dart}`.
2. `design/ui-config.schema.json` per section 6.4. Generate config types for all three.
3. `design/strings/{en,ar}.arb`. Generate `strings.xml`, `.strings`, `.arb`.
4. Add the lint rule that fails the build on any hex literal, `Colors.*`, `Color(0xFF...)`, `UIColor(red:)`, or raw numeric padding inside a scanner view file.

**Gate:**
```bash
./tools/build-tokens.sh && git diff --exit-code   # generated output matches committed
./tools/lint-no-literals.sh                        # zero violations
```

## Phase 9: Branded UI

**Do:** the five screens and six states (section 6.5), on whichever platforms Q9 resolved to. Build Flutter first (fastest iteration, where design review happens), then transcribe to Compose and SwiftUI.

**Critical sequencing:** stand up the cross-platform diff harness **before** the second platform's UI, not after. Otherwise the second implementation drifts during development and you pay to converge it at the end.

**Gate:**
```bash
./gradlew verifyPaparazziDebug
swift test --filter SnapshotTests
flutter test --tags golden
./tools/ui-parity --screens=all --locales=en,ar --scales=1.0,1.3
# layout diff <= 2 dp, SSIM >= 0.94, brand hex assertions EXACT
```

---

# PART 4: TARGET SPEC, THE PIPELINE

## 4.1 OpenCV build

Full OpenCV is +20 MB per ABI and unacceptable. Use `opencv-mobile` or a custom trimmed CMake build:

```
BUILD_LIST=core,imgproc,imgcodecs
WITH_PROTOBUF=OFF  WITH_QUIRC=OFF  WITH_ITT=OFF  WITH_IPP=OFF
BUILD_opencv_apps=OFF  BUILD_TESTS=OFF  BUILD_PERF_TESTS=OFF
WITH_JPEG=ON (libjpeg-turbo)  WITH_PNG=ON  WITH_WEBP=ON
BUILD_SHARED_LIBS=OFF
```

Budget: 3.5 MB per ABI on Android, 4 MB on iOS. Build in a separate `supy-scanner-native` pipeline, publish as a GitHub Release artifact with SHA-256, download and verify at plugin build time. Do not vendor OpenCV sources.

## 4.2 The C ABI

This header is the contract between the core and all three bindings. Keep it narrow and stable.

```c
#ifdef __cplusplus
extern "C" {
#endif

typedef int64_t sc_handle;
typedef int64_t sc_client;
typedef int32_t sc_status;

#define SC_OK                     0
#define SC_ERR_DECODE            -1
#define SC_ERR_NO_DOCUMENT       -2
#define SC_ERR_DEGENERATE_QUAD   -3
#define SC_ERR_OOM               -4
#define SC_ERR_INVALID_HANDLE    -5
#define SC_ERR_CANCELLED         -6

typedef struct { float x, y; } sc_point;
typedef struct { sc_point tl, tr, br, bl; } sc_quad;

typedef struct {
  int32_t enhancement;            /* 0 original 1 auto 2 color 3 gray 4 bw 5 ocr */
  int32_t deskew;
  int32_t shadow_removal;         /* 0 off 1 fast 2 guided */
  int32_t background_whitening;
  int32_t denoise;                /* 0 off 1 light 2 nlm */
  float   sharpen_amount;
  float   margin_percent;
  int32_t max_dimension;
  int32_t target_dpi;
  int32_t output_format;          /* 0 jpeg 1 png 2 webp 3 g4tiff */
  int32_t quality;
  int32_t chroma_subsampling;     /* 0 = 4:4:4, 1 = 4:2:0 */
  int32_t preserve_color_regions;
} sc_options;

/* lifecycle, refcounted so one loaded core can serve two callers */
sc_status sc_init(void);
sc_status sc_shutdown(void);
sc_status sc_acquire_client(const char* tag, sc_client* out);
sc_status sc_release_client(sc_client c);
int32_t   sc_abi_version(void);
const char* sc_version(void);
const char* sc_last_error_message(void);

/* images */
sc_status sc_decode_jpeg(const uint8_t* bytes, int64_t len, int32_t reduce,
                         int32_t exif_orientation, sc_handle* out);
sc_status sc_wrap_luma(const uint8_t* y, int32_t w, int32_t h,
                       int32_t stride, sc_handle* out);
sc_status sc_release(sc_handle h);
sc_status sc_dimensions(sc_handle h, int32_t* w, int32_t* h_out);

/* pipeline */
sc_status sc_detect_quad(sc_handle src, sc_quad* out, float* confidence);
sc_status sc_rectify(sc_handle src, const sc_quad* q, const sc_options* o, sc_handle* out);
sc_status sc_enhance(sc_handle rect, const sc_options* o, sc_handle* out);
sc_status sc_encode(sc_handle h, const sc_options* o, uint8_t** bytes, int64_t* len);
void      sc_free_bytes(uint8_t* p);

/* one hop for the common case */
sc_status sc_process(sc_handle src, const sc_quad* q, const sc_options* o,
                     uint8_t** bytes, int64_t* len, int32_t* w, int32_t* h);

/* cached refilter, so the filter strip feels instant */
sc_status sc_cache_rectified(sc_client c, sc_handle rect, int32_t slot);
sc_status sc_refilter(sc_client c, int32_t slot, const sc_options* o,
                      uint8_t** bytes, int64_t* len);
sc_status sc_clear_cache(sc_client c, int32_t slot);

#ifdef __cplusplus
}
#endif
```

**ABI evolution rule:** any change to this header bumps `sc_abi_version()`. New `sc_options` fields go at the **end** of the struct and must treat zero as "previous behaviour", so an old wrapper against a new core degrades gracefully instead of reading garbage.

## 4.3 Stage 0: ingest, decode exactly once

1. Decode once. All stages operate on in-memory `cv::Mat`. Never decode, process, encode, decode between stages.
2. Use DCT-scaled decode for the detection pass. libjpeg-turbo decodes at 1/2, 1/4, or 1/8 nearly free. Detection uses `reduce=8`.
3. Normalise EXIF orientation at ingest, then strip it. Half of all "the scan is sideways" bugs are an orientation tag applied twice or zero times.
4. For live frames use the **Y plane directly** as an 8-bit grayscale `Mat` with the supplied row stride. Zero conversion, zero copy. This is the difference between 4 ms and 18 ms per frame.

```cpp
cv::Mat luma(height, width, CV_8UC1, const_cast<uint8_t*>(yPlane), rowStride);
```

HEIC on iOS: decode via `CGImageSource` on the platform side and pass BGRA in. Adding libheif to the core costs ~1.5 MB and is not worth it.

## 4.4 Stage 1: detection

Work in Lab, not naive grayscale. This is what keeps colour stamps, red "PAID" marks, and blue signatures alive through later stages.

Run detection at 512 px longest side.

```cpp
sc_status detect_quad_classical(const cv::Mat& src, sc_quad* out, float* conf) {
  cv::Mat small; double scale = 512.0 / std::max(src.cols, src.rows);
  cv::resize(src, small, {}, scale, scale, cv::INTER_AREA);

  cv::Mat lab; cv::cvtColor(small, lab, cv::COLOR_BGR2Lab);
  std::vector<cv::Mat> ch; cv::split(lab, ch);

  /* per-pixel max gradient across L, a, b. White paper on a white table has
     no luminance edge but almost always has a chroma edge. */
  cv::Mat edges = cv::Mat::zeros(small.size(), CV_8UC1);
  for (auto& c : ch) {
    cv::Mat blurred, e;
    cv::medianBlur(c, blurred, 5);
    double med = median_of(blurred);
    cv::Canny(blurred, e, std::max(0.0, 0.66*med), std::min(255.0, 1.33*med));
    cv::max(edges, e, edges);
  }
  cv::morphologyEx(edges, edges, cv::MORPH_CLOSE,
                   cv::getStructuringElement(cv::MORPH_RECT, {3,3}), {-1,-1}, 2);

  std::vector<std::vector<cv::Point>> contours;
  cv::findContours(edges, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
  std::sort(contours.begin(), contours.end(),
            [](auto& a, auto& b){ return cv::contourArea(a) > cv::contourArea(b); });

  const double frameArea = small.total();
  for (int i = 0; i < std::min<int>(8, contours.size()); ++i) {
    std::vector<cv::Point> approx;
    cv::approxPolyDP(contours[i], approx, 0.02*cv::arcLength(contours[i], true), true);
    if (approx.size() != 4) continue;
    if (!cv::isContourConvex(approx)) continue;
    if (cv::contourArea(approx) < 0.15*frameArea) continue;
    if (!angles_within(approx, 60.0, 120.0)) continue;
    emit_ordered(approx, scale, out);
    *conf = confidence_from(approx, contours[i]);
    return SC_OK;
  }
  return detect_quad_lsd(src, out, conf);
}
```

**LSD fallback, required not optional.** When a finger covers a corner (extremely common with receipts) `approxPolyDP` never yields four points. Run `cv::createLineSegmentDetector`, keep segments longer than 15% of the frame, cluster into near-horizontal and near-vertical groups by angle (plus or minus 25 degrees), take the two extreme lines of each group, and intersect them to synthesise the corner. The corner is reconstructed even though it is physically hidden. This single fallback measurably reduces retake rate.

**Confidence score,** used for auto-capture, margin expansion, and UI hints:

```
conf = 0.35 * edge_support      /* fraction of quad perimeter with a real edge beneath */
     + 0.25 * convexity         /* contourArea / convexHullArea */
     + 0.20 * angle_regularity  /* 1 - mean(|angle - 90|)/45 */
     + 0.20 * area_ratio_sanity /* penalise below 20% or above 95% of frame */
```

If `conf < 0.6`, expand the crop margin to 3% and do not auto-capture.

**Temporal stabilisation for live preview:**

```dart
if (iou(newQuad, smoothed) < 0.70) {
  smoothed = newQuad;        // genuine re-frame, snap rather than lerp
  stableFrames = 0;
} else {
  smoothed = lerpQuad(smoothed, newQuad, 0.35);
  stableFrames++;
}
```

Auto-capture fires when all hold: `stableFrames >= 8`, `confidence >= 0.75`, focus locked, device motion below threshold, quad area between 25% and 92% of frame. Show a visible 3-tick countdown. Auto-capture with no warning is indistinguishable from a bug.

**Never leave the user with nothing.** Failed detection means "show the full frame with draggable corners", never an error dialog.

## 4.5 Stage 2: corner ordering

Order by angle around the centroid, then rotate the array so index 0 is the vertex nearest the image top-left. The simpler sum/diff trick (TL = min(x+y) and so on) degrades past 45 degrees of rotation; the robust version costs nothing and removes a whole class of mirrored-scan bugs.

Reject as `SC_ERR_DEGENERATE_QUAD`: any edge shorter than 5% of the image's shorter side, self-intersecting quads (inconsistent cross-product signs), aspect ratio beyond 1:12.

## 4.6 Stage 3: perspective correction

**The output-size problem.** The naive `w = max(|TR-TL|, |BR-BL|)` is wrong under strong perspective. Shooting a portrait A4 from 40 degrees makes the near edge much longer than the far edge, and `max()` of two projected lengths does not recover the true aspect ratio. Result: subtly stretched documents. Users do not articulate this; they say the scan "looks off".

**Correct approach.** Given four image points, an assumed principal point at the image centre, and a focal length, the physical rectangle's aspect ratio is solvable in closed form (Zhang and He, *Whiteboard Scanning and Image Enhancement*, MSR-TR-2003-39).

Focal length in pixels is available on both platforms:
- Android: `LENS_INFO_AVAILABLE_FOCAL_LENGTHS` and `SENSOR_INFO_PHYSICAL_SIZE`, then `f_px = f_mm * imageWidth / sensorWidth_mm`
- iOS: EXIF, or `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix` with `isCameraIntrinsicMatrixDeliveryEnabled = true`

Fallback prior when unavailable: `f_px ~= 1.2 * max(W, H)`.

Optional aspect snapping (default OFF): if within 2.5% of A4 (1:1.414), Letter (1:1.294), or ID-1 (1.586:1), snap. Never snap receipts.

**Fold the resize into the warp.** Do not warp at full resolution then downscale.

```cpp
cv::Mat H = cv::getPerspectiveTransform(srcQuad, dstQuad);
cv::Mat S = (cv::Mat_<double>(3,3) << s,0,0, 0,s,0, 0,0,1);
cv::Mat Hs = S * H;
```

**Anti-aliasing rule.** If the effective scale is a downscale greater than 2x, sampling in `warpPerspective` aliases text into moire. Pre-filter:

```cpp
cv::Mat working = src;
while (effective_downscale(Hs, working) > 2.0) {
  cv::pyrDown(working, working);
  Hs = adjust_for_pyrdown(Hs);
}
cv::warpPerspective(working, dst, Hs, targetSize,
                    final ? cv::INTER_LANCZOS4 : cv::INTER_LINEAR,
                    cv::BORDER_REPLICATE);
```

`BORDER_REPLICATE`, never `BORDER_CONSTANT`. A constant border puts black wedges in the corners whenever margin expansion runs past the frame edge.

## 4.7 Stage 4: deskew

Residual skew after rectification is typically under 3 degrees.

**Primary: projection-profile variance.** Sweep coarse (-5 to +5 degrees, step 0.5) then fine (plus or minus 0.5 around the winner, step 0.05). Shear rather than rotate, since shear approximates rotation at small angles and is far cheaper. Score = sum of squared differences between adjacent row sums. Sharp text lines score high. Compute on a 1/8-scale binarised copy; skew angle is scale-invariant and this makes the sweep about 3 ms.

**Fallback for sparse-text documents:** Hough transform on Canny edges, modal angle within plus or minus 10 degrees of horizontal.

**Guards:**
- Skip if `|theta| < 0.3` degrees. A tenth of a degree costs a full resample and gains nothing.
- Skip if the best score is within 5% of the score at zero (flat profile, no reliable text structure).
- After `warpAffine` with `INTER_CUBIC` and `BORDER_REPLICATE`, crop to the largest inscribed axis-aligned rectangle.

## 4.8 Stage 5: orientation

Rectification gives a correct rectangle but not which way is up.

- **Tier 1, free:** the projection-profile machinery already answers this. Horizontal text gives much higher row-profile variance than column-profile variance. If `columnScore > 1.6 * rowScore`, the document is rotated 90 or 270. Resolve which by margin asymmetry (documents have a larger bottom margin than top). About 85% accurate, fine as a default.
- **Tier 2:** when OCR is enabled, both ML Kit and Vision report block orientation. Trust it over the heuristic.
- **Tier 3:** show the rotate button prominently in review. A wrong 90 is the most annoying possible failure, and a one-tap fix beats a cleverer classifier.

## 4.9 Stage 6: illumination and shadow removal

**Highest-leverage stage in the pipeline.** Get this right and the rest is polish.

**The physical model:** observed = reflectance x illumination. Illumination is low-frequency, text is high-frequency. Two consequences:

1. It is a **division**, not a subtraction. Subtracting a background is the wrong model and crushes contrast in dark regions.
2. Illumination being low-frequency means you can estimate it at 1/8 resolution and upsample bilinearly. Visually identical, 64x cheaper. This is the key performance trick of the whole pipeline.

**Mode 1, morphological (default, fast):**

```cpp
cv::Mat estimate_background_fast(const cv::Mat& L) {
  cv::Mat small;
  cv::resize(L, small, {}, 0.125, 0.125, cv::INTER_AREA);
  int k = std::max(3, (int)(std::max(small.cols, small.rows) / 12) | 1);
  cv::morphologyEx(small, small, cv::MORPH_CLOSE,
                   cv::getStructuringElement(cv::MORPH_ELLIPSE, {k, k}));
  cv::medianBlur(small, small, 5);
  cv::Mat bg;
  cv::resize(small, bg, L.size(), 0, 0, cv::INTER_LINEAR);
  return bg;
}

void normalise_illumination(cv::Mat& L, const cv::Mat& bg, float targetMean = 210.f) {
  L.forEach<uchar>([&](uchar& p, const int* pos) {
    float g = targetMean / std::max<float>(bg.at<uchar>(pos[0], pos[1]), 1.f);
    g = std::clamp(g, 0.5f, 3.0f);
    p = cv::saturate_cast<uchar>(p * g);
  });
}
```

Apply the gain to **L only**. Leave `a` and `b` untouched. This is exactly why the pipeline works in Lab.

**Mode 2, guided filter (high quality).** The morphological estimate smears across hard shadow boundaries, such as the phone's own shadow cutting a straight line across the page, leaving a visible grey band. A guided filter (He, Sun, Tang) with the original L as guide is edge-aware, so the estimate follows the shadow boundary. About 20 lines using `cv::boxFilter` over integral images, O(1) per pixel regardless of radius. Radius `maxDim/16`, `eps = 0.02^2 * 255^2`. Run at 1/4 scale, upsample the coefficient maps, apply at full resolution (fast guided filter). Cost about 90 ms at 2200 px, so use for final only.

**Failure mode you must handle.** A large dark photo or filled black region gets classified as shadow and washed to grey mush. Both mitigations are required:
1. Clamp the gain to [0.5, 3.0].
2. Mask large dark regions out of the estimate: connected components in `L < 60` with area above 2% of the page, inpainted in the 1/8-scale background map before upsampling.

## 4.10 Stage 7: background whitening

```cpp
float paperL = percentile(L, 92.0f);   /* not max, that is a specular highlight */
float inkL   = percentile(L,  8.0f);
```

Build a 256-entry LUT and apply with `cv::LUT`. Essentially free, and better than a per-pixel branch.

```cpp
cv::Mat build_tone_lut(float inkL, float paperL, float strength) {
  cv::Mat lut(1, 256, CV_8U);
  float lo = inkL + 6.f;
  float hi = paperL - 4.f * (1.f - strength);
  for (int i = 0; i < 256; ++i) {
    float v;
    if      (i >= hi) v = 255.f;
    else if (i <= lo) v = i * (1.f - 0.15f * strength);
    else { float t = (i - lo) / (hi - lo); v = lo + (255.f - lo) * smoothstep(t); }
    lut.at<uchar>(i) = cv::saturate_cast<uchar>(v);
  }
  return lut;
}
```

**Desaturate proportionally to whiteness,** or you get coloured fringing on the paper:

```cpp
float whiteness = std::clamp((L_out - hi) / (255.f - hi), 0.f, 1.f);
float s = 1.f - whiteness;
a_out = 128 + (a_in - 128) * s;
b_out = 128 + (b_in - 128) * s;
```

**Coloured-document guard.** Pink carbon copies, yellow thermal receipts, and green delivery notes are destroyed by full whitening:

```cpp
float chroma = mean(abs(a - 128)) + mean(abs(b - 128));
if (chroma > 14.f) strength *= 0.4f;
```

**Colour-region preservation** (default on for invoices): build a mask of pixels with local chroma above 20, dilate 5 px, feather, blend the whitened result against the original inside the mask. Costs about 15 ms and saves every "PAID" stamp on every supplier invoice.

## 4.11 Stage 8: contrast

**Do not reach for CLAHE by default.** It is the reflex answer and it is wrong for documents: it amplifies sensor noise in blank regions and produces visible tile seams across the large empty areas invoices are full of.

- Document and Auto modes: global tone curve from the now-bimodal histogram. Black point at the 2nd percentile of ink, white point at paper white, gamma 1.0 to 1.15. One LUT, one pass, no artefacts.
- CLAHE (`clipLimit=2.0`, `tileGridSize=8x8`) on L only: reserve for photo-ish captures such as whiteboards and handwritten notes on textured paper.

## 4.12 Stage 9: denoise

After illumination correction (which amplifies noise in the regions it brightens), before binarisation and sharpening.

| Level | Method | Cost at 2200 px | Use |
|---|---|---|---|
| light (default) | `bilateralFilter(d=5, sigmaColor=45, sigmaSpace=5)` on L | ~60 ms | Everything |
| nlm | `fastNlMeansDenoising(h=7, templ=7, search=21)` | ~600 ms | Final only, high ISO |
| off | | 0 | Gallery imports of real scans |

Trigger `nlm` automatically above ISO 800 (from EXIF or `SENSOR_SENSITIVITY`).

Never denoise the detection copy.

## 4.13 Stage 10: sharpening

```cpp
void unsharp(cv::Mat& L, float amount, float sigma = 1.0f, int threshold = 3) {
  cv::Mat blur; cv::GaussianBlur(L, blur, {0,0}, sigma);
  cv::Mat diff = L - blur;
  cv::Mat mask = cv::abs(diff) > threshold;
  cv::Mat sharpened = L + amount * diff;
  sharpened.copyTo(L, mask);
}
```

Three non-negotiables: after the final resize never before; threshold the difference so noise is not amplified; amount 0.4 to 0.8 with sigma about 1.0, beyond which you get white halos around every glyph, the signature of an over-processed scan. L channel only.

## 4.14 Stage 11: binarisation

**Sauvola is the correct default.** `T(x,y) = m(x,y) * [1 + k * (s(x,y)/R - 1)]`, with `k = 0.20` (`0.34` for faint thermal receipts), `R = 128`, window `(imageWidth / 40) | 1`.

**Implement with integral images or it is unusable.** Naive windowed statistics at 2200 px with a 55 px window is billions of operations. With `cv::integral` for mean and `sqsum` for variance it is O(1) per pixel and window size becomes free. Target 150 ms at 2200 px. If your implementation is slower, you did not use integral images.

Variants: Wolf-Jolion for very low global contrast, Otsu for clean evenly lit scans, adaptive Gaussian as a cheap preview approximation.

Post-processing: `connectedComponentsWithStats`, drop components under 4 px, single 2x2 morphological open. **Verify periods and Arabic diacritics survive the area threshold before shipping it.**

Encode 1-bit output as CCITT Group 4, not JPEG. A4 at 200 dpi is about 35 KB G4 versus about 380 KB JPEG. At Supy's invoice volume that is a real storage and bandwidth line item.

## 4.15 Resolution policy

**Target DPI, not pixels.**

| DPI | A4 pixels | Use |
|---|---|---|
| 300 | 2480 x 3508 | Compliance archive, sub-6pt print |
| **200** | **1654 x 2339** | **Default, OCR grade** |
| 150 | 1240 x 1754 | Human-readable archive |
| 96 | 794 x 1123 | Thumbnails only |

The floor is set by OCR: roughly 20 to 30 px of character x-height, which for 8 pt body text is 150 to 200 dpi. Below 150 dpi accuracy falls off a cliff, not gradually.

**Class-aware capping.** A single longest-side cap is wrong for receipts. A 4:1 thermal receipt capped at 2200 px on the long side ends up 550 px wide and unreadable.

```dart
ResolutionPolicy resolveFor(DocumentClass cls) => switch (cls) {
  DocumentClass.invoice    => const ResolutionPolicy.dpi(200, maxLongSide: 2400),
  DocumentClass.receipt    => const ResolutionPolicy.minWidth(1100, maxLongSide: 4000),
  DocumentClass.idCard     => const ResolutionPolicy.dpi(300, maxLongSide: 1600),
  DocumentClass.whiteboard => const ResolutionPolicy.dpi(150, maxLongSide: 2000),
};
```

Classify by rectified aspect ratio (receipt if above 2.2), with manual override in review.

## 4.16 Encoding and export

| Content | Format | Settings |
|---|---|---|
| Colour document | JPEG | q=82, **4:4:4 chroma**, progressive |
| Grayscale | JPEG | q=85 |
| B&W | PNG or G4 TIFF | 1-bit |
| Bandwidth constrained | WebP | q=80, about 28% smaller |

**Use 4:4:4, not 4:2:0.** Halving chroma resolution visibly smears thin coloured text and red stamps, the exact things stage 7 preserved. On a mostly-white document the size penalty is about 8% because the chroma planes are nearly flat.

**Multi-page PDF:** build client-side with the `pdf` Dart package, embedding already-compressed streams as image XObjects. Do not re-encode. Add an invisible text layer (`Tr 3`) from OCR word boxes for a searchable PDF. Set page size from actual DPI so A4 prints at A4.

**Strip EXIF and GPS on every export.** A supplier invoice carrying the GPS coordinates of a restaurant back office is a privacy incident waiting to happen.

## 4.17 OCR: two branches, not one

The most expensive common mistake in this space is feeding OCR the same aggressively binarised, whitened, sharpened image shown to the user. Modern neural OCR performs **worse** on hard-binarised, halo-sharpened input than on clean grayscale, because it was trained on photographs, not 1-bit fax output.

```
                          ┌──> whiten, contrast, sharpen, JPEG   -> human / archive
rectified -> illumination ┤
                          └──> mild denoise, grayscale, PNG      -> OCR engine
```

The OCR branch is illumination-corrected, mildly denoised, **not** whitened, **not** binarised, **not** sharpened, at 200 dpi or above. In memory only, never persisted.

**Engine availability, read before promising Arabic:**

| Engine | Latin | Arabic |
|---|---|---|
| ML Kit Text Recognition v2 (Android) | yes | **no** |
| Apple Vision `VNRecognizeTextRequest` | yes | limited, verify `supportedRecognitionLanguages` at runtime on the minimum target |
| Google Cloud Vision | yes | yes (server) |
| Azure AI Document Intelligence | yes | yes (server) |
| AWS Textract | yes | no |

**This is a hard architectural constraint.** Supy's market is UAE, KSA, and MENA, and a meaningful share of supplier invoices are Arabic or mixed. On-device OCR is effectively Latin-only.

Therefore: treat on-device OCR as an optimisation (instant feedback, offline capture, cheap pre-filtering) and server-side OCR as the source of truth for invoice extraction. A page must be capturable offline and extractable server-side on reconnect. Never let on-device OCR silently become the extracted data for an Arabic document.

Also plan for: RTL text, Eastern Arabic numerals, and Hijri dates. Separate spec, but must not be discovered late.

## 4.18 Preview versus final

| Tier | Resolution | Algorithms | Budget |
|---|---|---|---|
| Live detection | 384 to 512 px from Y plane | detector only | **12 ms/frame** |
| Post-capture preview | ~1000 px | fast morphological BG, LUT, INTER_LINEAR | **250 ms** |
| Filter toggle | ~1000 px, cached | LUT plus Sauvola only | **50 ms** |
| Final | per resolution policy | guided filter, Lanczos, optional NLM | **900 ms** |

The final pass runs in the background while the user reviews. If they change a filter, cancel in flight (`SC_ERR_CANCELLED`) and restart. By the time they tap Done the final is usually already encoded.

## 4.19 Memory rules

A 12 MP RGBA frame is 48 MB. Ten pages holding original, rectified, processed, and thumbnail is about 1.4 GB. That app is dead on any mid-tier device.

1. At most two full-resolution buffers alive at once. Assert it in debug builds.
2. On capture, write the original JPEG to cache and drop the in-memory copy. `ScannedPage` holds `originalPath`, `processedPath`, and a thumbnail at 256 px or less. Never full-resolution bytes in Bloc state.
3. Explicit `dispose()` plus `NativeFinalizer` backstop.
4. Bound the session at 50 pages.
5. Never `android:largeHeap="true"`. It is a symptom, not a fix.
6. Clear the cache directory on session completion and on app start. Crash orphans accumulate silently and users see "Supy is using 4 GB".
7. iOS: on `didReceiveMemoryWarningNotification`, flush all native caches immediately.

## 4.20 Performance budgets

Reference: mid-tier Android (Snapdragon 6-series, 6 GB) and iPhone SE 3, 12 MP source. CI-enforced.

| Operation | Budget | Fail above |
|---|---|---|
| Live detection per frame | 12 ms | 20 ms |
| Shutter to preview | 400 ms | 600 ms |
| Filter toggle (cached) | 50 ms | 100 ms |
| Full process, colour, 2200 px | 900 ms | 1400 ms |
| Sauvola additional | 150 ms | 250 ms |
| On-device OCR per page | 700 ms | 1200 ms |
| PDF export, 10 pages | 1500 ms | 2500 ms |
| Peak RSS, 10-page session | 350 MB | 500 MB |
| Binary size per ABI | 3.5 MB | 4.5 MB |

## 4.21 Corpus and metrics

**250+ labelled images.** The single highest-value artefact in the project.

| Category | n | Why |
|---|---|---|
| White paper on white surface | 25 | Kills luminance-only edge detection |
| Dark wood or stainless counter | 25 | Real Supy environment |
| Hard shadow across the page | 25 | Guided filter validation |
| Uneven or gradient lighting | 25 | Illumination model |
| Finger occluding a corner | 20 | LSD fallback |
| Glossy or laminated | 15 | White point estimation |
| Crumpled or curled receipts | 20 | Known limitation |
| Faded thermal receipts | 20 | Sauvola k tuning |
| Arabic and mixed AR/EN | 30 | RTL, diacritic survival |
| Coloured carbon forms | 15 | Whitening guard |
| Stamps and signatures | 15 | Colour region preservation |
| Low light plus motion blur | 15 | Denoise selection |
| Flash hotspot | 10 | Gain clamp |

Stage them in an actual restaurant back office, not on an office desk.

**Metrics:**

| Metric | Target |
|---|---|
| Mean quad IoU (rectified frame, ICDAR SmartDoc 2015 protocol) | >= 0.95 |
| P95 IoU | >= 0.90 |
| Catastrophic rate (IoU < 0.80) | <= 2% |
| CER, printed Latin invoice | <= 1.5% |
| CER, thermal receipt | <= 4% |
| CER, Arabic (server engine) | <= 3% |
| Cross-platform SSIM | >= 0.98 |

Compare quads in the **rectified** frame. Comparing in the original frame over-weights the near edge and under-reports real failures.

Judge every pipeline change by delta-CER, not by whether the thumbnail looks nicer.

Do not use byte-hash goldens for native output. Floating-point differences across architectures make them permanently flaky, and a flaky gate gets disabled within a month.

---

# PART 5: TARGET SPEC, MULTI-PLATFORM DISTRIBUTION

## 5.1 Module matrix

### Android (`minSdk 24`, `compileSdk 36`, NDK r27+)

| Artifact | Contents | Size |
|---|---|---|
| `io.supy:scanner-core` | `.so` x 3 ABIs, JNI bridge, `SupyScannerProcessor` | ~3.5 MB/ABI |
| `io.supy:scanner-camera` | CameraX capture, `ScannerAnalyzer`, auto-capture | ~180 KB |
| `io.supy:scanner-ui` | Compose viewfinder, crop editor, filter strip, review | ~340 KB |
| `io.supy:scanner-mlkit` | Optional ML Kit turnkey adapter | ~40 KB |
| `io.supy:scanner-ocr` | ML Kit Text Recognition binding | ~60 KB |
| `io.supy:scanner-bom` | Version alignment | |

### iOS (15.0+, with graceful 13.0 fallback)

| Product | Contents | Size |
|---|---|---|
| `SupyScannerCore` | static `.xcframework`, Swift wrapper, `SupyScannerProcessor` | ~4 MB |
| `SupyScannerCapture` | AVFoundation session, `VisionDetector`, auto-capture | ~140 KB |
| `SupyScannerUI` | SwiftUI and UIKit screens | ~300 KB |
| `SupyScannerOCR` | `VNRecognizeTextRequest` binding | ~30 KB |

On iOS 13 and 14 the SDK silently uses the C++ detector instead of Vision. No API difference, no compile-time branch for the consumer.

Ship via **both** SPM (`binaryTarget` plus checksum) and CocoaPods. Forcing a package-manager migration to adopt a library is a good way to not get adopted.

### Flutter (3.41+, Dart 3.11+)

| Package | Contents |
|---|---|
| `supy_scanner` | FFI bindings, isolate, ports, headless API |
| `supy_scanner_camera` | Capture plus detection stream |
| `supy_scanner_ui` | Flutter widgets |

The core compiles for macOS and Linux, so headless processing works on Flutter desktop for gallery imports. Web is unsupported: `DocumentProcessorPort` throws `UnsupportedPlatformFailure` so a web build compiles and degrades gracefully rather than breaking CI.

## 5.2 Linking: the two failure modes that break multi-target libraries

### 5.2.1 Android duplicate `.so`

If both the AAR and the Flutter plugin ship `libsupy_scanner_core.so`, Gradle's native merge either fails or silently picks one. Two different versions means an ABI mismatch crash at first call, on a device, in production.

**The Flutter plugin ships no native library of its own:**

```gradle
dependencies {
    api "io.supy:scanner-core:$supyScannerVersion"
}
android {
    packagingOptions {
        jniLibs { pickFirsts += [] }   /* no pickFirst: a duplicate must FAIL loudly */
    }
}
```

```dart
final DynamicLibrary _lib = Platform.isAndroid
    ? DynamicLibrary.open('libsupy_scanner_core.so')
    : DynamicLibrary.process();
```

If the Kotlin SDK already called `System.loadLibrary`, `dlopen` on the same soname within the app's linker namespace resolves to the already-loaded instance. Verify this explicitly in the hybrid integration test; do not assume it.

### 5.2.2 iOS duplicate symbols

`SupyScannerCore` is a **static** xcframework, chosen for startup time and dead-code stripping. If the Swift SDK and the Flutter plugin each link it independently, the linker sees duplicate symbols.

```ruby
s.dependency 'SupyScannerCore', "~> #{s.version}"
# NOT: s.vendored_frameworks = 'SupyScannerCore.xcframework'
```

Because it is static, symbols land in the app binary, so Dart FFI must use `DynamicLibrary.process()`. `DynamicLibrary.open()` fails with a confusing "image not found".

### 5.2.3 Shared global state

One loaded core may serve two callers simultaneously in a hybrid app. Therefore:

- **Reference counted.** `sc_init` / `sc_shutdown` with an atomic refcount. Last caller out tears down.
- **Thread safe.** All handle and slot maps behind a mutex. Handles are opaque `int64_t` from a global monotonic counter, never pointers cast to integers.
- **Namespaced per client.** `sc_acquire_client(tag)` returns a token; cache slots are scoped to it, so Flutter's cache cannot evict the Kotlin SDK's.

### 5.2.4 ABI version guard

Three independently versioned wrappers over one binary core is an ABI-drift machine. Guard at init, loudly, in all three wrappers:

```kotlin
init {
    val abi = NativeBridge.abiVersion()
    require(abi == SUPPORTED_ABI) {
        "supy-scanner ABI mismatch: core=$abi, sdk=$SUPPORTED_ABI. " +
        "Align io.supy:scanner-* artifacts using io.supy:scanner-bom."
    }
}
```

Fail at init with an actionable message, never at the first `process()` call with a segfault.

## 5.3 API parity: one model, three idioms

Same concepts, same option names, same defaults, same failure taxonomy.

```kotlin
val processor = SupyScannerProcessor.create(context)
val detection = processor.detect(bitmap)
val page = processor.process(
    source = bitmap, quad = detection.quad,
    options = ProcessingOptions(
        enhancement = Enhancement.AUTO,
        shadowRemoval = ShadowRemoval.GUIDED,
        backgroundWhitening = true,
        preserveColorRegions = true,
        documentClass = DocumentClass.INVOICE,
    ),
)
```
```swift
let processor = try SupyScannerProcessor()
let detection = try await processor.detect(image)
let page = try await processor.process(
    source: image, quad: detection.quad,
    options: ProcessingOptions(
        enhancement: .auto, shadowRemoval: .guided,
        backgroundWhitening: true, preserveColorRegions: true,
        documentClass: .invoice
    )
)
```
```dart
final processor = await SupyScannerProcessor.create();
final detection = await processor.detect(ImageRef.file(path));
final result = await processor.process(
  ImageRef.file(path), quad: detection.quad,
  options: const ProcessingOptions(
    enhancement: Enhancement.auto,
    shadowRemoval: ShadowRemoval.guided,
    backgroundWhitening: true,
    preserveColorRegions: true,
    documentClass: DocumentClass.invoice,
  ),
);
```

**Live detection:** `Flow<DetectionResult>` (Kotlin), `AsyncStream<DetectionResult>` (Swift), `Stream<DetectionResult>` (Dart).

**Error model:** Kotlin throws, Swift throws, Dart returns `Either`. Same information, three conventions. Do not force `Either` on Kotlin or `Result` on Swift for superficial symmetry; that produces an API nobody on those platforms wants to use. Never let a raw `sc_status` int leak into a public API.

**Image types at the boundary:**

| Platform | Accepts | Path to core |
|---|---|---|
| Kotlin | `Bitmap`, `ImageProxy`, `ByteArray`, `Uri` | `AndroidBitmap_lockPixels` zero-copy; `ImageProxy` Y-plane direct |
| Swift | `UIImage`, `CGImage`, `CVPixelBuffer`, `Data`, `URL` | `CVPixelBuffer` base address zero-copy |
| Dart | `ImageRef.file/bytes/handle` | file path as `const char*`, decoded natively. **Never** a `Uint8List` round-trip for full-resolution images |

## 5.4 Native glue

### Android

```kotlin
class ScannerAnalyzer(private val onQuad: (FloatArray?, Float) -> Unit)
    : ImageAnalysis.Analyzer {
    override fun analyze(proxy: ImageProxy) {
        val y = proxy.planes[0]
        val quad = nativeDetect(y.buffer, proxy.width, proxy.height,
                                y.rowStride, proxy.imageInfo.rotationDegrees)
        onQuad(quad?.points, quad?.confidence ?: 0f)
        proxy.close()   /* leak this and the pipeline stalls */
    }
}
```

```kotlin
ImageAnalysis.Builder()
    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
    .build()
```

Capture with `CAPTURE_MODE_MAXIMIZE_QUALITY` and `setJpegQuality(95)`. The capture JPEG is an intermediate; the lossy step is our own final encode.

**Android specifics:**
- **16 KB page size.** Android 15+ devices require 16 KB alignment and Play enforces it for apps targeting Android 15+. Build with `-Wl,-z,max-page-size=16384`, verify with `llvm-readelf -l`, gate in CI.
- ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64`. Drop `x86`.
- Never request `WRITE_EXTERNAL_STORAGE`. Cache dir plus MediaStore.

### iOS

```swift
func captureOutput(_ output: AVCaptureOutput,
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
    guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let request = VNDetectDocumentSegmentationRequest { req, _ in
        guard let obs = req.results?.first as? VNRectangleObservation else {
            self.onQuad(nil, 0); return
        }
        self.onQuad(obs.quad, obs.confidence)
    }
    try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: self.exifOrientation)
        .perform([request])
}
```

Session: `.photo` preset, `maxPhotoQualityPrioritization = .quality`, `isCameraIntrinsicMatrixDeliveryEnabled = true` on the video connection (this gives the focal length for aspect-ratio recovery, free and worth taking).

**iOS specifics:**
- `PrivacyInfo.xcprivacy` mandatory.
- `NSCameraUsageDescription` and `NSPhotoLibraryAddUsageDescription` in the host app's Info.plist. Document in the README: a missing key is an instant crash with an unhelpful message.
- Run Vision on a dedicated serial queue. On the capture queue it drops frames; on main it drops the UI.

## 5.5 Repository layout

One monorepo. Three independently versioned products would drift within a quarter.

```
supy-scanner/
├── core/                          L0, C++17, no platform deps
│   ├── include/supy_scanner.h
│   ├── src/
│   ├── test/                      GoogleTest, runs on Linux CI
│   └── CMakeLists.txt
├── conformance/
│   ├── corpus/                    git-lfs, 250+ labelled images
│   ├── expected/
│   ├── runner/
│   └── ui/                        cross-platform screenshot diff
├── design/
│   ├── tokens.json
│   ├── ui-config.schema.json
│   └── strings/{en,ar}.arb
├── android/
│   ├── scanner-core/ scanner-camera/ scanner-ui/ scanner-mlkit/ scanner-ocr/
│   └── sample-app/                proves Android-only works
├── ios/
│   ├── Sources/SupyScanner{Core,Capture,UI,OCR}/
│   ├── Package.swift  *.podspec
│   └── SampleApp/                 proves iOS-only works
├── flutter/
│   ├── supy_scanner/ supy_scanner_camera/ supy_scanner_ui/
│   └── example/
└── tools/
    ├── build-core.sh  build-tokens.sh  ffigen.yaml
    ├── harness  conformance  ui-parity
    └── release.sh
```

**The three sample apps are load-bearing, not demos.** Built in CI on every PR. If the Android sample fails to compile without Flutter on its classpath, the Android-only requirement has silently regressed, and that regression is invisible until a native team tries to adopt the library.

## 5.6 Release

One version, three channels, lockstep.

```
tools/release.sh 2026.3.1
  ├─ build core: .so x3 (16 KB aligned), .xcframework, host lib
  ├─ bump gradle.properties, *.podspec, Package.swift, pubspec.yaml
  ├─ verify sc_abi_version() matches all three wrappers
  ├─ run conformance on all three targets, output must be identical
  ├─ verify size budgets
  ├─ publish Maven Central, CocoaPods, SPM tag, pub.dev
  └─ GitHub Release with checksums
```

## 5.7 Cross-target testing

| Layer | Tool | Runs |
|---|---|---|
| Core unit and corpus | GoogleTest, ASAN, UBSAN | Linux CI, seconds |
| Kotlin binding | JUnit plus instrumented | CI plus device |
| Swift binding | XCTest | CI |
| Dart binding | `mocktail`, `bloc_test`, `integration_test` | CI plus device |
| **Conformance** | `conformance/runner` | Every PR |
| Hybrid integration | device | Nightly |

Binding suites test only the binding: type marshalling, handle lifecycle, error mapping, cancellation, no leaks over 1000 cycles. They do not re-test the pipeline. The pipeline is tested once, in C++.

**Conformance asserts byte-identical encoded output** across Android and iOS for the same input and options. Not SSIM: identical. If the core is genuinely shared and deterministic this holds, and when it breaks it means someone introduced a platform-conditional path, which is exactly what you want to catch. Set `cv::setNumThreads(1)` in the conformance build; thread-count differences change floating-point reduction order.

**Hybrid integration** runs an Android app with both the native SDK and an add-to-app Flutter module in one process. Asserts one `.so` loaded (check `/proc/self/maps`), refcount correct across both, cache slots isolated per client token, no crash on `sc_shutdown` from one while the other is live. This looks paranoid and it catches the class of bug that costs a week to diagnose in production.

---

# PART 6: TARGET SPEC, UI AND SUPY BRANDING

## 6.1 The approach

| Option | Verdict |
|---|---|
| Flutter add-to-app everywhere | Rejected. Forces the Flutter engine (about 5 MB, plus 200 to 400 ms first frame) into every native host. Breaks the Android-only requirement outright. |
| Three free-form implementations | Rejected. Drifts within a quarter. |
| **Shared tokens plus shared config schema plus three thin native views plus a visual parity gate** | **Chosen.** |

This is the shape Scanbot uses for its RTU-UI: screens written natively per platform, every colour, string, and visibility flag from one configuration object with identical field names on all three. That configuration object, not the view code, is the product surface.

About 4,200 lines of view code total. That is the honest cost. It buys native scroll physics, native gestures, native accessibility, and no engine embedded in a host app. The parity gate is what stops those 4,200 lines from diverging.

## 6.2 Token pipeline

**No hex value is ever typed by hand in view code.** One JSON file, three generated outputs, one CI check.

```json
{
  "color": {
    "brand": {
      "navy": "#321e57", "logoPurple": "#503390",
      "brightPurple": "#7b51bf", "purpleAction": "#6C3FC5", "purpleDark": "#4A2A8A"
    },
    "scanner": {
      "scrim":           { "value": "#321e57", "alpha": 0.72 },
      "quadStroke":      "#7b51bf",
      "quadStrokeInner": "#ffffff",
      "quadFill":        { "value": "#7b51bf", "alpha": 0.14 },
      "quadLocked":      "#40c798",
      "quadWarning":     "#fcd34d",
      "quadReposition":  "#fb763c",
      "quadError":       "#c2260c",
      "handle":          "#ffffff",
      "handleCore":      "#6C3FC5",
      "shutterRing":     "#ffffff",
      "shutterFill":     "#6C3FC5"
    },
    "surface": {
      "page": "#f4f1fa", "card": "#ffffff", "border": "#efedfa",
      "textPrimary": "#1A1A2E", "textSecondary": "#888888"
    }
  },
  "radius":  { "sm": 4, "md": 8, "lg": 12, "sheet": 16 },
  "spacing": { "xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24 },
  "motion": {
    "enter":     { "duration": 280, "curve": "easeOut" },
    "exit":      { "duration": 200, "curve": "easeIn" },
    "spring":    { "duration": 400, "curve": "cubic-bezier(0.34,1.56,0.64,1)" },
    "dissolve":  { "duration": 200, "curve": "easeInOut" },
    "quadTrack": { "duration": 120, "curve": "easeOut" }
  },
  "type": {
    "family": "Noto Sans", "familyArabic": "Noto Kufi Arabic",
    "h1": { "size": 28, "weight": 600 }, "h2": { "size": 20, "weight": 600 },
    "sectionHeader": { "size": 16, "weight": 700 },
    "body": { "size": 14, "weight": 400 }, "label": { "size": 12, "weight": 500 },
    "caption": { "size": 11, "weight": 400 }
  }
}
```

Generated by Style Dictionary into `SupyScannerTokens.{kt,swift,dart}`, checked in as generated code, regenerated in CI. If regenerated output differs from committed output, the build fails.

**Lint rule on every PR:** any hex literal, `Color(0xFF...)`, `Colors.*`, `UIColor(red:)`, or raw numeric padding inside a scanner view file fails the build. This is the mechanism that makes "the brand is applied" a fact rather than a claim.

## 6.3 Brand on a dark surface

Supy's palette is built for light enterprise surfaces: white cards on `#f4f1fa`. A viewfinder is the opposite context, so the mapping must be explicit or each platform improvises differently.

| Element | Token | Rationale |
|---|---|---|
| Chrome, scrims, sheets over camera | Navy `#321e57` at 72% | Reads as Supy, not generic black |
| Wordmark | `Supy_Logo_White.svg` | Required on dark backgrounds |
| Quad outline | Bright Purple `#7b51bf`, 3 dp, plus 1 dp white inner hairline | The white hairline guarantees visibility on purple, navy, or dark documents. Purple alone disappears. |
| Quad fill | Bright Purple at 14% | Reads the shape without obscuring the document |
| Corner handles | White fill, Purple Action core, 44 dp touch target | Contrast plus brand |
| Shutter | White ring, Purple Action fill | Standard Supy primary |
| Active mode chip | White background, Purple Action text | Supy segmented control pattern |

**Colour carries state, never decoration** (brand hard rule 6):

| State | Quad colour | Hint |
|---|---|---|
| Searching | White 40%, dashed | "Point at a document" |
| Detected, unstable | Bright Purple `#7b51bf` | "Hold steady" |
| Stable, capturing | Yellow `#fcd34d` plus countdown ring | "Capturing" |
| Captured | Green `#40c798`, 200 ms flash | none, haptic only |
| Too close or far | Orange `#fb763c` | "Move back" / "Move closer" |
| Low light | Orange `#fb763c` | "More light needed" |
| Detection failed | Red `#c2260c` | "Tap to capture manually" |

Every state is announced through the platform accessibility API as well as shown. A user holding a phone over an invoice is not necessarily looking at the hint text.

## 6.4 Shared UI configuration

The most important artefact in the UI work. It makes the same UI configurable identically from three languages, and it is what the parity tests drive.

```json
{
  "topBar":        { "visible": true, "showLogo": true, "title": null },
  "flashButton":   { "visible": true },
  "galleryImport": { "visible": true },
  "autoCapture":   { "enabled": true, "stableFrames": 8, "countdownVisible": true },
  "hints":         { "visible": true, "position": "bottom" },
  "shutter":       { "style": "ring", "hapticOnCapture": true },
  "modes":         { "visible": true, "options": ["single","multi","receipt"] },
  "cropEditor":    { "magnifier": true, "resetButton": true, "gridOverlay": true },
  "filters":       { "visible": true, "options": ["auto","color","grayscale","bw"], "default": "auto" },
  "review":        { "reorderable": true, "maxPages": 20, "addMoreButton": true },
  "theme":         { "override": null },
  "strings":       { "override": {} }
}
```

Identical field names in Kotlin, Swift, and Dart. Because it is JSON-serializable, the parity test loads one fixture and drives all three platforms from it. That is what makes cross-platform screenshot comparison meaningful rather than approximate.

`theme.override` lets a white-label deployment swap the palette without forking views. Supy's own apps never set it, so they always get Supy brand by default.

## 6.5 Screens

### Viewfinder

```
┌───────────────────────────────────┐
│ X        [supy wordmark]      ⚡  │  Navy 72%, 56 dp, white logo
├───────────────────────────────────┤
│      ╔═══════════════════╗        │  3 dp Bright Purple
│      ║     INVOICE       ║        │  + 1 dp white inner hairline
│      ╚═══════════════════╝        │  + 14% purple fill
│         Hold steady               │  Navy 60% pill, 8 dp radius
├───────────────────────────────────┤
│  Single  <Multi>  Receipt         │  white active chip
│   [img]      ( o )        [3]     │  gallery / shutter / page count
└───────────────────────────────────┘  Navy 72%, 132 dp
```

- Quad animates to new corners over 120 ms `easeOut`. Never teleports, never springs. Spring on a tracking overlay reads as instability.
- Corner brackets are L-shaped at 24 dp until the quad is stable. Full perimeter appears only on lock, giving a legible progress signal for free.
- Auto-capture shows a 3-tick countdown ring around the shutter.
- Page count badge uses the Neutral badge palette (`#EDE9FB` background, `#6C3FC5` text) and taps through to review.

### Crop editor

- Handles: 20 dp visual, 44 dp touch target, white with an 8 dp Purple Action core.
- **Magnifier** on handle drag only, 96 dp circle, 2 dp Bright Purple border, positioned to avoid the finger. This single detail most separates a polished scanner from a rough one.
- Edges draggable, not just corners. Users reach for the edge more often.
- Handles snap to detected edges within 12 dp with a light haptic.
- `Reset` is a ghost button, not primary, because it is a recovery action.

### Filter strip

- 72 dp thumbnails, 8 dp radius. Active: 2 dp Purple Action border plus purple label.
- Rendered from the cached rectified buffer via `sc_refilter`, under 50 ms. If a filter tap shows a spinner, the caching is broken.
- **Filter chrome is uniform across all four thumbnails** per brand hard rule 5. Only the image content differs. Do not colour-code the filter chips.

### Page review

The one screen on a light surface, so standard Supy chrome applies directly: page background `#f4f1fa`, white cards at 12 dp radius with `0 1px 3px rgba(0,0,0,0.06)` shadow, `#efedfa` borders, `#1A1A2E` text. Reorder by long-press plus drag with a 400 ms spring on pickup.

### Processing and export

Determinate Purple Action progress bar, not an indeterminate spinner, because the pipeline reports real progress through the FFI callback. Copy follows Supy voice: "Enhancing page 2 of 3", not "Please wait".

### The five states nobody specs and everybody ships broken

| State | Treatment |
|---|---|
| Camera permission denied | Navy full screen, white icon, one-line explanation, `Open settings` primary button. Never a bare system dialog with no recovery path. |
| No document for 10 s | Hint becomes "Tap the shutter to capture manually". Never block on detection. |
| Low light | Orange hint plus automatic torch suggestion chip. |
| Max pages reached | Inline banner using the Warning badge palette (`#FEF9EC` / `#B8860B`), not a modal. |
| Processing failure | Error badge palette, failed page marked in the grid with a `Retry` ghost button. The session is never discarded because one page failed. |

## 6.6 Component parity

| Component | Compose | SwiftUI | Flutter |
|---|---|---|---|
| Quad overlay | `Canvas` plus `Animatable` | `Canvas` plus `withAnimation` | `CustomPainter` plus `AnimationController` |
| Camera preview | `PreviewView` in `AndroidView` | `AVCaptureVideoPreviewLayer` in `UIViewRepresentable` | `Texture` over platform view |
| Magnifier | `graphicsLayer` scale on cropped bitmap | `UIView` snapshot scaled | `BackdropFilter` plus `Transform.scale` |
| Filter strip | `LazyRow` | `ScrollView(.horizontal)` | horizontal `ListView.builder` |
| Page reorder | `LazyVerticalGrid` plus drag gestures | `.onDrag` / `.onDrop` | `ReorderableGridView` |
| Haptics | `HapticFeedbackConstants` | `UIImpactFeedbackGenerator` | `HapticFeedback` |

Each platform uses its native primitive. The parity gate compares the rendered result, not the implementation.

## 6.7 Localisation and RTL

Copy lives in `design/strings/{en,ar}.arb`, generated into `strings.xml`, `.strings`, and `.arb`. One source, three outputs, same keys.

Typeface: `Noto Sans` for Latin, `Noto Kufi Arabic` for Arabic. Both bundled in the SDK rather than assumed present on device. A missing Arabic font renders as boxes, and that is a support ticket you will get.

**The RTL trap.** In a scanner, some things mirror and some absolutely must not.

| Element | Mirrors under RTL? |
|---|---|
| Top bar, back button, bottom bar layout | Yes |
| Filter strip scroll direction | Yes |
| Page thumbnail order in review | Yes |
| Hint text alignment | Yes |
| **Camera preview** | **No.** Mirroring makes the physical document unreadable. |
| **Quad overlay coordinates** | **No.** They are image space, not layout space. |
| **The captured image** | **No.** Obviously, and yet this has shipped broken in real products. |

Add an explicit RTL golden per screen on all three platforms. This class of bug is invisible to a team that does not read Arabic and glaring to every user who does.

## 6.8 Accessibility

- Corner handles: 44 dp minimum touch target, individually focusable, adjustable by keyboard or switch control in 1% increments, labelled "Top left corner, 12 percent from left, 8 percent from top".
- Detection state announced live, throttled to once per 1.5 s so it does not spam.
- Capture confirmed by haptic and sound, never the visual flash alone.
- All text pairings pass WCAG AA. Note: Yellow `#fcd34d` on Navy passes at large size only, so countdown text is 16 px bold minimum, never caption size.
- Reduced motion: quad tracking becomes instant, countdown ring becomes a numeric counter, cross-dissolves become cuts.
- Filter options labelled, never distinguished by colour alone.

## 6.9 Visual parity: making the brand claim testable

| Layer | Tool |
|---|---|
| Android goldens | Paparazzi (JVM, no emulator) |
| iOS goldens | swift-snapshot-testing |
| Flutter goldens | Alchemist |
| Cross-platform diff | `conformance/ui/` |

Matrix: 5 screens x 6 states x 2 locales x 2 text scales = 120 goldens per platform, 360 total.

**Do not require pixel-identical output across platforms.** Font rasterisation, antialiasing, and shadow rendering genuinely differ, and a gate that fails on those gets disabled within a month. Instead:

1. **Layout diff:** bounding boxes of every labelled element, tolerance 2 dp. Catches a 16 dp padding that became 12 dp on iOS only.
2. **Brand colour assertion:** sample specific pixels, assert the **exact** hex. The quad stroke pixel must be exactly `#7b51bf` on all three. No tolerance, because there is no legitimate reason for a brand colour to differ by one bit.
3. **Perceptual diff:** SSIM at least 0.94 between platforms for the same screen and state.

Point 2 is what actually enforces the brand. A human reviewer will not notice that iOS drifted to `#7c52c0` after someone hand-typed a hex. The test will.

---

# PART 7: ANTI-PATTERNS

Known ways this work goes wrong. Check against this list before opening any PR.

## Pipeline

1. **Decode, process, encode, decode between stages.** Destroys quality and performance. Decode once, all processing in memory, encode once.
2. **`max(edge length)` for output size.** Wrong under perspective. Use aspect-ratio recovery from the homography.
3. **Warping at full resolution then downscaling.** Twice the work, no quality gain. Fold the scale into the homography.
4. **No pre-filter before a greater-than-2x downscale warp.** Aliases text into moire.
5. **`BORDER_CONSTANT` in `warpPerspective`.** Black wedges in the corners.
6. **Subtracting the illumination background instead of dividing.** Wrong physical model, crushes dark regions.
7. **Estimating illumination at full resolution.** 64x more expensive for no visible gain.
8. **Naive Sauvola without integral images.** Billions of operations, unusable.
9. **CLAHE as the document default.** Tile seams and amplified noise on the large blank areas invoices are full of.
10. **Sharpening before the final resize.** Wastes the sharpening and creates aliasing.
11. **Unsharp without a difference threshold.** Amplifies sensor noise into visible grain.
12. **Applying gain to a, b as well as L.** Destroys the colour stamps you worked to preserve.
13. **Feeding OCR the binarised, whitened, sharpened image.** OCR does worse on it. Two branches.
14. **Single longest-side resolution cap.** Turns receipts into unreadable mush. Class-aware capping.
15. **4:2:0 chroma on documents.** Smears thin coloured text and red stamps.
16. **Byte-hash goldens for native output.** Permanently flaky across architectures.
17. **Comparing quads in the original frame.** Over-weights the near edge, under-reports failures. Compare in the rectified frame.

## Memory

18. **Full-resolution `Uint8List` in Bloc state.** 48 MB per page. Paths and thumbnails only.
19. **Relying on GC for native buffers.** Explicit `dispose()` plus `NativeFinalizer`.
20. **`android:largeHeap="true"`.** A symptom, not a fix, and it makes OOMs harder to reproduce.
21. **Never clearing the cache directory.** Crash orphans accumulate and users see "Supy is using 4 GB".

## Multi-platform

22. **Flutter plugin shipping its own copy of the `.so`.** Duplicate native library, version mismatch crash in production.
23. **`pickFirst` on `libsupy_scanner_core.so`.** Hides the duplicate instead of failing loudly.
24. **Vendoring the xcframework in the Flutter podspec.** Duplicate symbols.
25. **`DynamicLibrary.open()` on iOS with a static framework.** Fails with "image not found". Use `.process()`.
26. **Flutter calling the Kotlin SDK which calls the core.** A chain, not siblings. Adds a JNI hop and inherits Kotlin-side bugs.
27. **No ABI version guard.** Segfault at first call instead of an actionable message at init.
28. **Global cache slots not namespaced per client.** Flutter's cache evicts the Kotlin SDK's.
29. **Deferring the "no Flutter on the classpath" CI check.** By the time you notice, it is a rewrite.
30. **Raw `sc_status` leaking into a public API.** Map to the native error type.

## UI

31. **Any hex literal in a view file.** Lint rule exists precisely because this is the default failure mode.
32. **Mirroring the camera preview or quad coordinates under RTL.** Makes the document unreadable.
33. **Colour-coding the filter chips.** Violates chrome consistency. Chrome uniform, content varies.
34. **Auto-capture with no countdown.** Indistinguishable from a bug.
35. **Springing the quad overlay.** Reads as instability. Use 120 ms `easeOut`.
36. **Spinner on filter toggle.** Means the rectified-buffer cache is broken.
37. **A modal for "max pages reached".** Inline banner using the Warning badge palette.
38. **Discarding the session because one page failed.** Mark the page, offer Retry.
39. **Blocking on detection with no manual capture path.** Always leave the shutter available.
40. **Standing up the second platform's UI before the parity harness.** Guarantees drift you pay to converge later.

## Process

41. **Tuning pipeline parameters without the corpus.** Every change becomes a coin flip.
42. **Deleting the legacy path before parity is proven in production telemetry.** Strangler pattern exists for a reason.
43. **Reporting a metric you did not measure.** Say the gate cannot be evaluated instead.
44. **Batching phases into one PR.** Unreviewable, therefore rubber-stamped.
45. **Em dashes or en dashes anywhere in Supy output.** Brand hard rule 1.

---

# PART 8: OPEN QUESTIONS, DO NOT ANSWER ALONE

Stop and escalate if a phase depends on one of these.

| # | Question | Blocks | Why it matters |
|---|---|---|---|
| Q1 | What retake rate or CER from the core would justify keeping or buying a vendor SDK? | Phase 5 | Agree the threshold before Phase 2 ships or the decision gets made on sentiment. |
| Q2 | Is server-side Arabic extraction (Azure Document Intelligence versus Google Cloud Vision) committed? Cost per page at projected volume? | OCR work | On-device OCR is Latin-only. This gates the whole Arabic path. |
| Q3 | Storage format for the invoice archive: per-page JPEG or multi-page searchable PDF? | Export design | Affects the export path and backend ingestion contract. |
| Q4 | Offline queue depth: how many pages before the cache policy pushes back? | Phase 3 | Restaurant back offices have genuinely poor Wi-Fi. |
| Q5 | Can real customer captures be retained for a test corpus under current terms? | **Phase 0** | Legal input needed before collection starts, not after. |
| Q6 | Does the ingestion and OCR path accept WebP? | Encoding | About 28% bandwidth saving is worth confirming. |
| Q7 | Curled thermal receipts are not planar and homography cannot fix them. Accept the limitation or scope cylindrical dewarping? | Backlog | Sets expectations with product. |
| Q8 | Public distribution (Maven Central, CocoaPods trunk, pub.dev) or internal Artifactory? | Phase 6 | Public implies API stability commitments, support burden, and a licence decision. |
| Q9 | **Which native teams consume the Android and iOS SDKs?** | **Phases 6, 7, 9** | If the answer is "none today", skip those phases. This is the single largest swing in the estimate: UI work goes from 8 weeks to 3. |
| Q10 | Is `theme.override` a real white-label requirement or speculative? | Phase 8 | Shapes the token architecture. Retrofitting is expensive. |
| Q11 | Is there a Figma file for these screens? | Phase 8 | If yes, the token pipeline should read Figma Variables directly rather than a hand-maintained `tokens.json`. |
| Q12 | iOS floor: 15 for Vision, or 13 using the C++ detector everywhere? | Phase 7 | Dropping Vision gives perfect cross-platform parity at some accuracy cost. Measure on the corpus before deciding. |
| Q13 | Do the light screens (review, export) follow a dark theme if the system is dark? | Phase 9 | Viewfinder and crop are dark by nature; the other two are a product decision. |

---

# PART 9: NON-GOALS

Explicitly out of scope. Do not build these.

- Curled, folded, or otherwise non-planar page dewarping
- Handwriting recognition
- Table structure extraction (that is the server-side document-AI layer)
- Barcode and QR scanning (separate module, already exists)
- Real-time video OCR
- Kotlin Multiplatform for the binding layers (adds a toolchain, buys little, the bindings are a few hundred lines each)