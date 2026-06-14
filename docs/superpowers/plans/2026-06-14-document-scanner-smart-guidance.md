# Document Scanner — Smart Guidance & Interface Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the embedded `SupyDocumentScannerView` feel as smart as Scanbot — reject false positives, add an Android edge detector, auto-snap with countdown, polish overlay chrome.

**Architecture:** iOS-first to unblock the visible false-positive bug. Vision request gets tighter thresholds + an interior-variance gate; FSM gains a `holdSteady` state; widget owns the 600ms auto-snap countdown; Android grows a native C++ document-edge detector in the existing `supy_scanner_core` JNI scaffold; all overlay literals route through `SupyScannerPalette`.

**Tech Stack:** Dart (Flutter), Swift (AVFoundation + Vision + Core Image), Kotlin (CameraX), C++17 (custom CV pipeline behind JNI, no OpenCV), GoogleTest.

**Spec:** `docs/superpowers/specs/2026-06-14-document-scanner-smart-guidance-design.md`

---

## File Map

**Modify:**
- `lib/src/models/supy_document_frame_metrics.dart` — add `quadStability`, `interiorVariance` fields + `fromMap`/`==`/`hashCode`.
- `lib/src/models/supy_document_frame_state.dart` — add `holdSteady` enum case.
- `lib/src/models/ui/supy_document_guidance_configuration.dart` — new thresholds + hint copy + `autoCapture` + `holdSteadyFrames` + `allowUnrectifiedFallback`.
- `lib/src/models/ui/supy_scanner_palette.dart` — add `warning` color.
- `lib/src/document/supy_document_state_machine.dart` — `holdSteady` classification + priority slot.
- `lib/src/document/supy_document_metrics_smoother.dart` — smooth new scalars.
- `lib/src/widgets/supy_document_scanner_view.dart` — overlay rewrite (reticles, brackets, ring, flash), auto-capture countdown.
- `lib/src/widgets/supy_document_scanner_controller.dart` — `captureFullFrame` method + UNIMPLEMENTED fallback.
- `lib/src/channel/supy_document_event_channel.dart` — parse new metric fields.
- `ios/Classes/document/DocumentDetector.swift` — confidence/aspect/interior gates + stability tracker.
- `ios/Classes/document/SupyDocumentScannerView.swift` — implement `captureAndRectify` + `captureFullFrame`.
- `android/src/main/cpp/supy_scanner_core_jni.cpp` — add `Java_io_supy_scanner_nativecore_SupyNativeCore_detectQuad`.
- `android/src/main/kotlin/io/supy/scanner/nativecore/SupyNativeCore.kt` — `external fun nativeDetectQuad(...)`.
- `android/src/main/kotlin/io/supy/scanner/document/DocumentFrameAnalyzer.kt` — wire JNI + fall back to v0 path on load failure.
- `android/src/main/kotlin/io/supy/scanner/document/SupyDocumentScannerView.kt` — `captureFullFrame` MethodChannel handler.
- `native/CMakeLists.txt` — append new C++ source.
- `docs/ARCHITECTURE.md`, `docs/QA.md`, `docs/internal/BRANDING_PARITY.md`, `TODO.md`, `CHANGELOG.md`.

**Create:**
- `native/document/document_edge_detector.h` — public C++ API for the detector.
- `native/document/document_edge_detector.cpp` — pipeline implementation.
- `native/document/document_edge_detector_test.cpp` — GoogleTest cases.
- `ios/Tests/DocumentDetectorTests.swift` — XCTest cases for interior-variance & stability.
- `test/document/supy_document_state_machine_hold_steady_test.dart` — FSM tests.
- `test/widgets/supy_document_scanner_view_countdown_test.dart` — widget countdown tests.
- `test/channel/supy_document_event_channel_capture_test.dart` — capture method wrapper tests.

---

## Task 1: Extend `SupyDocumentFrameMetrics` with `quadStability` + `interiorVariance`

**Files:**
- Modify: `lib/src/models/supy_document_frame_metrics.dart`
- Modify: `test/models/supy_document_data_test.dart` (or sibling — keep with existing fixtures)
- Create: `test/models/supy_document_frame_metrics_test.dart` if no dedicated file exists

- [ ] **Step 1: Write the failing tests**

```dart
// test/models/supy_document_frame_metrics_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/supy_document_frame_metrics.dart';

void main() {
  group('SupyDocumentFrameMetrics', () {
    test('defaults: quadStability = 0.0, interiorVariance = 0.0', () {
      const m = SupyDocumentFrameMetrics();
      expect(m.quadStability, 0.0);
      expect(m.interiorVariance, 0.0);
    });

    test('fromMap reads new optional fields', () {
      final m = SupyDocumentFrameMetrics.fromMap(<Object?, Object?>{
        'quad': const <Object?>[],
        'coverageRatio': 0.5,
        'tiltDegrees': 1.0,
        'meanLuma': 120.0,
        'blurScore': 90.0,
        'clipsEdge': false,
        'quadStability': 0.8,
        'interiorVariance': 42.5,
      });
      expect(m.quadStability, 0.8);
      expect(m.interiorVariance, 42.5);
    });

    test('fromMap tolerates missing new fields (back-compat)', () {
      final m = SupyDocumentFrameMetrics.fromMap(<Object?, Object?>{
        'coverageRatio': 0.5,
      });
      expect(m.quadStability, 0.0);
      expect(m.interiorVariance, 0.0);
    });

    test('equality includes new fields', () {
      const a = SupyDocumentFrameMetrics(quadStability: 0.5);
      const b = SupyDocumentFrameMetrics(quadStability: 0.6);
      expect(a == b, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/models/supy_document_frame_metrics_test.dart`
Expected: FAIL — `quadStability`/`interiorVariance` are not members.

- [ ] **Step 3: Add the fields**

In `lib/src/models/supy_document_frame_metrics.dart`:

Add two fields in the const constructor and class body:

```dart
const SupyDocumentFrameMetrics({
  this.quad = const [],
  this.coverageRatio = 0.0,
  this.tiltDegrees = 0.0,
  this.meanLuma = 0.0,
  this.blurScore = 0.0,
  this.clipsEdge = false,
  this.quadStability = 0.0,
  this.interiorVariance = 0.0,
});
```

```dart
/// Stability of the detected quad across the last few frames (0–1).
/// 1 = no centroid/corner drift. 0.0 when [quad] is empty.
final double quadStability;

/// Variance-of-Laplacian *inside* the detected quad. Used to reject low-
/// texture surfaces (laptop screens showing a single image). 0.0 when [quad]
/// is empty.
final double interiorVariance;
```

In `fromMap`, after the existing parses, add:

```dart
quadStability: (map['quadStability'] as num?)?.toDouble() ?? 0.0,
interiorVariance: (map['interiorVariance'] as num?)?.toDouble() ?? 0.0,
```

Extend `operator ==`:

```dart
other.quadStability == quadStability &&
other.interiorVariance == interiorVariance &&
```

Extend `hashCode`:

```dart
@override
int get hashCode => Object.hash(
      Object.hashAll(quad),
      coverageRatio,
      tiltDegrees,
      meanLuma,
      blurScore,
      clipsEdge,
      quadStability,
      interiorVariance,
    );
```

Update `toString()` to append `stability: ${quadStability.toStringAsFixed(2)}, interior: ${interiorVariance.toStringAsFixed(0)})`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/models/supy_document_frame_metrics_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/models/supy_document_frame_metrics.dart test/models/supy_document_frame_metrics_test.dart
git commit -m "feat(document): add quadStability and interiorVariance metric fields"
```

---

## Task 2: Add `holdSteady` state + extend `SupyDocumentGuidanceConfiguration`

**Files:**
- Modify: `lib/src/models/supy_document_frame_state.dart`
- Modify: `lib/src/models/ui/supy_document_guidance_configuration.dart`
- Modify: `test/models/supy_document_data_test.dart` (or create dedicated config test)

- [ ] **Step 1: Write failing tests**

```dart
// test/models/supy_document_guidance_configuration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/supy_document_frame_state.dart';
import 'package:supy_scanner/src/models/ui/supy_document_guidance_configuration.dart';

void main() {
  group('SupyDocumentGuidanceConfiguration', () {
    test('exposes holdSteady defaults', () {
      const c = SupyDocumentGuidanceConfiguration();
      expect(c.readyStabilityFloor, 0.75);
      expect(c.interiorVarianceFloor, 5.0);
      expect(c.holdSteadyFrames, 6);
      expect(c.autoCapture, isTrue);
      expect(c.autoCaptureDelay, const Duration(milliseconds: 600));
      expect(c.allowUnrectifiedFallback, isTrue);
    });

    test('hintFor(holdSteady) returns the holdSteady copy', () {
      const c = SupyDocumentGuidanceConfiguration();
      expect(c.hintFor(SupyDocumentFrameState.holdSteady), 'Hold steady…');
    });

    test('new default hint copy matches spec', () {
      const c = SupyDocumentGuidanceConfiguration();
      expect(c.hintFor(SupyDocumentFrameState.noDocument), 'Searching for document…');
      expect(c.hintFor(SupyDocumentFrameState.tooDark), 'Move to a brighter spot');
      expect(c.hintFor(SupyDocumentFrameState.tooClose), 'Move farther back');
      expect(c.hintFor(SupyDocumentFrameState.tooFar), 'Move closer');
      expect(c.hintFor(SupyDocumentFrameState.tooSkewed), 'Hold the camera flat');
      expect(c.hintFor(SupyDocumentFrameState.blurry), 'Hold steady');
      expect(c.hintFor(SupyDocumentFrameState.ready), "Don't move");
      expect(c.hintFor(SupyDocumentFrameState.capturing), 'Capturing…');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/models/supy_document_guidance_configuration_test.dart`
Expected: FAIL — enum case and fields missing.

- [ ] **Step 3: Add `holdSteady` enum case**

In `lib/src/models/supy_document_frame_state.dart`, insert after `blurry`:

```dart
/// All failure checks pass but the quad isn't stable enough yet — we're
/// waiting for the user to stop moving before promoting to `ready`.
holdSteady,
```

- [ ] **Step 4: Extend `SupyDocumentGuidanceConfiguration` and `SupyDocumentGuidanceHints`**

In `lib/src/models/ui/supy_document_guidance_configuration.dart`:

Add to the const constructor parameter list:

```dart
this.readyStabilityFloor = 0.75,
this.interiorVarianceFloor = 5.0,
this.holdSteadyFrames = 6,
this.autoCapture = true,
this.autoCaptureDelay = const Duration(milliseconds: 600),
this.allowUnrectifiedFallback = true,
this.warningColor = const Color(0xFFFF4D4D),
```

Add fields:

```dart
/// Minimum `quadStability` required to leave `holdSteady` for `ready`.
final double readyStabilityFloor;

/// Minimum variance-of-Laplacian inside the quad before we trust it's a real
/// document. Screens showing a single image fail this; printed paper passes.
final double interiorVarianceFloor;

/// Consecutive frames `quadStability >= readyStabilityFloor` required to
/// promote `holdSteady` → `ready`.
final int holdSteadyFrames;

/// Whether the widget should auto-fire `captureAndRectify` after a brief
/// countdown when `ready` first lands.
final bool autoCapture;

/// Countdown duration before auto-capture fires.
final Duration autoCaptureDelay;

/// When `captureAndRectify` returns UNIMPLEMENTED (Android pre-Sprint 4),
/// silently retry via `captureFullFrame` so the user always gets a picture.
/// Set `false` for "rectified or nothing" flows.
final bool allowUnrectifiedFallback;

/// Color for failure-state corner brackets.
final Color warningColor;
```

Update `colorFor`:

```dart
case SupyDocumentFrameState.holdSteady:
  return notReadyColor;
```

Default the new copy in `SupyDocumentGuidanceHints`:

```dart
const SupyDocumentGuidanceHints({
  this.noDocument = 'Searching for document…',
  this.tooDark = 'Move to a brighter spot',
  this.tooClose = 'Move farther back',
  this.tooFar = 'Move closer',
  this.tooSkewed = 'Hold the camera flat',
  this.blurry = 'Hold steady',
  this.holdSteady = 'Hold steady…',
  this.ready = "Don't move",
  this.capturing = 'Capturing…',
  this.captured = 'Captured!',
});
```

Add `final String holdSteady;` field, the matching case in `textFor`, and include it in `==` / `hashCode`.

Update the configuration's `==` and `hashCode` to include every new field. Update `toString` accordingly.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/models/supy_document_guidance_configuration_test.dart`
Expected: PASS.

- [ ] **Step 6: Run full Dart test suite — catch any switch-exhaustiveness compile errors**

Run: `flutter test`
Expected: PASS (any `switch (state)` that didn't have a default will surface as a compile error here; fix each by adding `case SupyDocumentFrameState.holdSteady:` returning the equivalent of the failure path).

- [ ] **Step 7: Commit**

```bash
git add lib/src/models/supy_document_frame_state.dart lib/src/models/ui/supy_document_guidance_configuration.dart test/models/supy_document_guidance_configuration_test.dart
git commit -m "feat(document): add holdSteady state and guidance configuration extensions"
```

---

## Task 3: FSM — classify `holdSteady` from `quadStability`

**Files:**
- Modify: `lib/src/document/supy_document_state_machine.dart`
- Modify: `lib/src/document/supy_document_metrics_smoother.dart` (smooth the new scalars)
- Create: `test/document/supy_document_state_machine_hold_steady_test.dart`

- [ ] **Step 1: Write failing FSM tests**

```dart
// test/document/supy_document_state_machine_hold_steady_test.dart
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/document/supy_document_state_machine.dart';
import 'package:supy_scanner/src/models/supy_document_frame_metrics.dart';
import 'package:supy_scanner/src/models/supy_document_frame_state.dart';
import 'package:supy_scanner/src/models/ui/supy_document_guidance_configuration.dart';

SupyDocumentFrameMetrics _good({double stability = 1.0, double interior = 50.0}) {
  return SupyDocumentFrameMetrics(
    quad: const [Offset(0.1, 0.1), Offset(0.9, 0.1), Offset(0.9, 0.9), Offset(0.1, 0.9)],
    coverageRatio: 0.6,
    tiltDegrees: 2.0,
    meanLuma: 150.0,
    blurScore: 200.0,
    clipsEdge: false,
    quadStability: stability,
    interiorVariance: interior,
  );
}

void main() {
  group('SupyDocumentStateMachine holdSteady', () {
    test('enters holdSteady when checks pass but stability is low', () {
      // High smoothing alpha so the smoother converges in one tick for test clarity.
      final fsm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          readyStableFrames: 1,
        ),
      );
      final frame = fsm.tick(_good(stability: 0.2));
      expect(frame.state, SupyDocumentFrameState.holdSteady);
    });

    test('promotes holdSteady → ready after holdSteadyFrames stable ticks', () {
      final fsm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          readyStableFrames: 1,
          holdSteadyFrames: 3,
        ),
      );
      // Seed: one frame at low stability → holdSteady.
      fsm.tick(_good(stability: 0.2));
      // Three frames at high stability → ready.
      fsm.tick(_good(stability: 0.9));
      fsm.tick(_good(stability: 0.9));
      final frame = fsm.tick(_good(stability: 0.9));
      expect(frame.state, SupyDocumentFrameState.ready);
    });

    test('rejects on low interiorVariance (screen-like surface)', () {
      final fsm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          interiorVarianceFloor: 10.0,
        ),
      );
      final frame = fsm.tick(_good(stability: 1.0, interior: 1.0));
      // The interior-variance gate folds into the "looks like a document" branch;
      // failing it should NOT reach holdSteady — it degrades to noDocument because
      // there is no usable document.
      expect(frame.state, SupyDocumentFrameState.noDocument);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/document/supy_document_state_machine_hold_steady_test.dart`
Expected: FAIL (multiple cases — holdSteady never reached; interior gate not enforced).

- [ ] **Step 3: Smooth the new scalars**

In `lib/src/document/supy_document_metrics_smoother.dart`, locate the EMA per-scalar block and add `quadStability` and `interiorVariance` exactly like `meanLuma` (reset to 0.0 on no-document). If the smoother stores fields in a list-driven loop, append `quadStability` and `interiorVariance` to that list.

(Read the file once and add by exact pattern — there's only one EMA block.)

- [ ] **Step 4: Add interior-variance gate + holdSteady classification**

In `lib/src/document/supy_document_state_machine.dart`:

Modify `_classify` so a quad with `interiorVariance` below the floor is treated as "no usable document":

```dart
SupyDocumentFrameState _classify(SupyDocumentFrameMetrics m) {
  final c = _configuration;
  final hasUsableDoc =
      m.hasDocument && m.interiorVariance >= c.interiorVarianceFloor;
  if (!hasUsableDoc) {
    _goodStreak = 0;
    _missingStreak += 1;
    if (_missingStreak <= c.lostDocumentGraceFrames &&
        _state != SupyDocumentFrameState.noDocument) {
      return _state;
    }
    return SupyDocumentFrameState.noDocument;
  }
  _missingStreak = 0;

  final failing = _firstFailure(m);
  if (failing != null) {
    _goodStreak = 0;
    return failing;
  }

  // All hard failures pass — but require stability before promoting to ready.
  final stabilityFloor = _state == SupyDocumentFrameState.holdSteady
      ? c.readyStabilityFloor * (1.0 - c.exitMargin)
      : c.readyStabilityFloor;
  if (m.quadStability < stabilityFloor) {
    _goodStreak = 0;
    return SupyDocumentFrameState.holdSteady;
  }

  _goodStreak += 1;
  final framesNeeded =
      _state == SupyDocumentFrameState.holdSteady
          ? c.holdSteadyFrames
          : c.readyStableFrames;
  if (_goodStreak >= framesNeeded) {
    return SupyDocumentFrameState.ready;
  }
  return _holdingState();
}
```

Add `holdSteady` to `_priority` at slot 5.5 — since priority is `int`, slot it at 6 and bump `ready` to 7, `capturing`/`captured` to 8:

```dart
static int _priority(SupyDocumentFrameState s) {
  switch (s) {
    case SupyDocumentFrameState.noDocument: return 0;
    case SupyDocumentFrameState.tooDark: return 1;
    case SupyDocumentFrameState.tooClose: return 2;
    case SupyDocumentFrameState.tooFar: return 3;
    case SupyDocumentFrameState.tooSkewed: return 4;
    case SupyDocumentFrameState.blurry: return 5;
    case SupyDocumentFrameState.holdSteady: return 6;
    case SupyDocumentFrameState.ready: return 7;
    case SupyDocumentFrameState.capturing:
    case SupyDocumentFrameState.captured: return 8;
  }
}
```

Update `_holdingState` to include `holdSteady` in its passthrough branches (no behavioural change — it just needs to compile).

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/document/supy_document_state_machine_hold_steady_test.dart`
Expected: PASS.

Run: `flutter test`
Expected: PASS (full suite).

- [ ] **Step 6: Commit**

```bash
git add lib/src/document/ test/document/
git commit -m "feat(document): FSM classifies holdSteady and gates on interior variance"
```

---

## Task 4: iOS detector hardening — confidence, aspect, interior variance, stability

**Files:**
- Modify: `ios/Classes/document/DocumentDetector.swift`
- Create: `ios/Tests/DocumentDetectorTests.swift`

- [ ] **Step 1: Read the existing `DocumentDetector.swift` to find the Vision request setup and the `DocumentFrameMetrics.toMap()` definition.**

Run: `cat ios/Classes/document/DocumentDetector.swift | sed -n '1,50p'` (or use Read).

- [ ] **Step 2: Write the failing XCTest cases**

```swift
// ios/Tests/DocumentDetectorTests.swift
import XCTest
import CoreImage
@testable import supy_scanner

final class DocumentDetectorTests: XCTestCase {

  func testInteriorVarianceRejectsUniformPatch() {
    // A 64×64 uniform-gray buffer ⇒ variance ≈ 0.
    let pixelBuffer = makePixelBuffer(width: 64, height: 64, fill: 128)
    let detector = DocumentDetector()
    let variance = detector.computeInteriorVariance(
      pixelBuffer: pixelBuffer,
      normalizedQuad: [
        CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
        CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9),
      ]
    )
    XCTAssertLessThan(variance, 1.0)
  }

  func testInteriorVarianceFlagsTexturedPatch() {
    // Checkerboard ⇒ high variance.
    let pixelBuffer = makeCheckerboardBuffer(width: 64, height: 64, cell: 4)
    let detector = DocumentDetector()
    let variance = detector.computeInteriorVariance(
      pixelBuffer: pixelBuffer,
      normalizedQuad: [
        CGPoint(x: 0.05, y: 0.05), CGPoint(x: 0.95, y: 0.05),
        CGPoint(x: 0.95, y: 0.95), CGPoint(x: 0.05, y: 0.95),
      ]
    )
    XCTAssertGreaterThan(variance, 100.0)
  }

  func testStabilityTrackerReportsHighStabilityForStaticQuad() {
    let tracker = QuadStabilityTracker(windowSize: 6)
    let q: [CGPoint] = [
      CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
      CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9),
    ]
    for _ in 0..<6 { _ = tracker.push(q) }
    XCTAssertGreaterThan(tracker.stability(), 0.95)
  }

  func testStabilityTrackerReportsLowStabilityForJittery() {
    let tracker = QuadStabilityTracker(windowSize: 6)
    let base: [CGPoint] = [
      CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
      CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9),
    ]
    for i in 0..<6 {
      let jitter = CGFloat(i) * 0.05
      _ = tracker.push(base.map { CGPoint(x: $0.x + jitter, y: $0.y) })
    }
    XCTAssertLessThan(tracker.stability(), 0.5)
  }

  // Helpers (omitted for brevity in this plan — implementers write makePixelBuffer
  // and makeCheckerboardBuffer producing a kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
  // CVPixelBuffer with the specified luma content).
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run from `ios/`: `xcodebuild test -workspace ../example/ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:RunnerTests/DocumentDetectorTests`
Expected: FAIL — `QuadStabilityTracker` and `computeInteriorVariance` don't exist.

- [ ] **Step 4: Implement detector hardening**

In `ios/Classes/document/DocumentDetector.swift`:

(a) Where `VNDetectRectanglesRequest` is configured, set:

```swift
request.minimumConfidence = 0.7
request.quadratureTolerance = 30.0
request.minimumAspectRatio = 0.4
request.maximumAspectRatio = 1.0
request.minimumSize = 0.2
```

Mirror the same gates on the iOS-17 `VNDetectDocumentSegmentationRequest` post-processing branch (compute aspect/area from the observation's quad and discard out-of-range candidates).

(b) Add `computeInteriorVariance` as an internal method:

```swift
func computeInteriorVariance(
  pixelBuffer: CVPixelBuffer,
  normalizedQuad: [CGPoint]
) -> Double {
  guard normalizedQuad.count == 4 else { return 0 }
  CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
  defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
  let w = CVPixelBufferGetWidth(pixelBuffer)
  let h = CVPixelBufferGetHeight(pixelBuffer)
  let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
  guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }
  let y = base.assumingMemoryBound(to: UInt8.self)

  // Axis-aligned bounding box of the quad, clamped to the image.
  let xs = normalizedQuad.map { Int($0.x * CGFloat(w)) }
  let ys = normalizedQuad.map { Int($0.y * CGFloat(h)) }
  let xMin = max(0, xs.min()!)
  let yMin = max(0, ys.min()!)
  let xMax = min(w - 1, xs.max()!)
  let yMax = min(h - 1, ys.max()!)
  if xMax - xMin < 8 || yMax - yMin < 8 { return 0 }

  // Subsample to ~96px long-edge. Variance-of-Laplacian on the sampled grid.
  let target = 96
  let longEdge = max(xMax - xMin, yMax - yMin)
  let step = max(1, longEdge / target)

  var sumLap: Double = 0
  var sumLap2: Double = 0
  var n: Int = 0
  var yy = yMin + step
  while yy < yMax - step {
    var xx = xMin + step
    while xx < xMax - step {
      let c  = Int(y[yy * stride + xx])
      let l  = Int(y[yy * stride + xx - step])
      let r  = Int(y[yy * stride + xx + step])
      let u  = Int(y[(yy - step) * stride + xx])
      let d  = Int(y[(yy + step) * stride + xx])
      let lap = Double(4 * c - l - r - u - d)
      sumLap  += lap
      sumLap2 += lap * lap
      n += 1
      xx += step
    }
    yy += step
  }
  guard n > 0 else { return 0 }
  let mean = sumLap / Double(n)
  return sumLap2 / Double(n) - mean * mean
}
```

(c) Add the stability tracker:

```swift
final class QuadStabilityTracker {
  private let windowSize: Int
  private var history: [[CGPoint]] = []

  init(windowSize: Int = 6) { self.windowSize = windowSize }

  func push(_ quad: [CGPoint]) -> Double {
    guard quad.count == 4 else { history.removeAll(); return 0.0 }
    history.append(quad)
    if history.count > windowSize { history.removeFirst() }
    return stability()
  }

  func stability() -> Double {
    guard history.count >= 2 else { return 0.0 }
    // Per-corner max-drift across the window, expressed in normalized units.
    var maxDrift: Double = 0
    for corner in 0..<4 {
      var minX = Double.infinity, maxX = -Double.infinity
      var minY = Double.infinity, maxY = -Double.infinity
      for frame in history {
        let p = frame[corner]
        minX = min(minX, Double(p.x))
        maxX = max(maxX, Double(p.x))
        minY = min(minY, Double(p.y))
        maxY = max(maxY, Double(p.y))
      }
      let drift = max(maxX - minX, maxY - minY)
      if drift > maxDrift { maxDrift = drift }
    }
    // Map drift to stability: 0 drift → 1.0, ≥0.1 drift → 0.0.
    return max(0.0, min(1.0, 1.0 - maxDrift / 0.1))
  }

  func reset() { history.removeAll() }
}
```

(d) Wire both into the existing frame pipeline. After a candidate quad is accepted, compute `interiorVariance` and reject (no-quad) if below `5.0`. Push the accepted quad into the tracker and include `interiorVariance` + `quadStability` in `DocumentFrameMetrics.toMap()`:

```swift
// In DocumentFrameMetrics — add the two stored properties + map keys.
let interiorVariance: Double
let quadStability: Double

// In toMap():
"interiorVariance": interiorVariance,
"quadStability": quadStability,
```

(`DocumentDetector` owns one `QuadStabilityTracker` instance; reset it whenever the detector observes a no-quad frame so the buffer doesn't bleed across acquisitions.)

- [ ] **Step 5: Run tests to verify they pass**

Run the test invocation from Step 3.
Expected: PASS.

- [ ] **Step 6: Manual sanity check on iPhone**

Run the example app on an iPhone 13 or newer. Point at:
1. A laptop screen showing any rectangular content → must NOT trigger a quad / `ready`.
2. A printed invoice on a dark desk → must detect quad within ~1 second.

Capture two screenshots and attach to the PR description.

- [ ] **Step 7: Commit**

```bash
git add ios/Classes/document/DocumentDetector.swift ios/Tests/DocumentDetectorTests.swift
git commit -m "feat(ios): tighten document detector thresholds and add interior-variance + stability gates"
```

---

## Task 5: iOS `captureAndRectify` + `captureFullFrame` MethodChannel handlers

**Files:**
- Modify: `ios/Classes/document/SupyDocumentScannerView.swift`
- Modify: `lib/src/widgets/supy_document_scanner_controller.dart`
- Modify: `lib/src/channel/supy_document_event_channel.dart` (if it owns method-channel names — otherwise the wrapper file under `lib/src/channel/`)
- Create: `test/channel/supy_document_event_channel_capture_test.dart`

- [ ] **Step 1: Write failing Dart wrapper tests**

```dart
// test/channel/supy_document_event_channel_capture_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/widgets/supy_document_scanner_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captureAndRectify returns parsed result', () async {
    final ctrl = SupyDocumentScannerController();
    final channel = MethodChannel('io.supy.scanner/v1/document/0');
    ctrl.attach(channel);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'captureAndRectify') {
        return <String, Object?>{
          'path': '/tmp/page.jpg',
          'widthPx': 2480,
          'heightPx': 3508,
          'quad': <Map<String, Object?>>[
            {'x': 0.1, 'y': 0.1}, {'x': 0.9, 'y': 0.1},
            {'x': 0.9, 'y': 0.9}, {'x': 0.1, 'y': 0.9},
          ],
        };
      }
      return null;
    });

    final result = await ctrl.captureAndRectify();
    expect(result.path, '/tmp/page.jpg');
    expect(result.widthPx, 2480);
    expect(result.quad.length, 4);
  });

  test('captureAndRectify UNIMPLEMENTED throws captureUnsupported error', () async {
    final ctrl = SupyDocumentScannerController();
    final channel = MethodChannel('io.supy.scanner/v1/document/1');
    ctrl.attach(channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'UNIMPLEMENTED');
    });
    await expectLater(
      ctrl.captureAndRectify(),
      throwsA(predicate((e) => e is StateError && e.message.contains('captureUnsupported'))),
    );
  });

  test('captureFullFrame returns parsed result', () async {
    final ctrl = SupyDocumentScannerController();
    final channel = MethodChannel('io.supy.scanner/v1/document/2');
    ctrl.attach(channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'captureFullFrame') {
        return <String, Object?>{
          'path': '/tmp/raw.jpg', 'widthPx': 3024, 'heightPx': 4032,
        };
      }
      return null;
    });
    final r = await ctrl.captureFullFrame();
    expect(r.path, '/tmp/raw.jpg');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/channel/supy_document_event_channel_capture_test.dart`
Expected: FAIL — methods missing on controller.

- [ ] **Step 3: Add controller methods + result type**

In `lib/src/widgets/supy_document_scanner_controller.dart` (or its sibling result-models file):

```dart
@immutable
class SupyDocumentCapture {
  const SupyDocumentCapture({required this.path, required this.widthPx, required this.heightPx, this.quad = const []});
  final String path;
  final int widthPx;
  final int heightPx;
  final List<Offset> quad;
}
```

Add `Future<SupyDocumentCapture> captureAndRectify()` and `Future<SupyDocumentCapture> captureFullFrame()` on `SupyDocumentScannerController`. The body invokes the bound `MethodChannel` and parses the returned `Map`. On `PlatformException(code: 'UNIMPLEMENTED')` from `captureAndRectify`, rethrow as a typed `StateError('captureUnsupported: …')` — or, preferred, add `SupyScanError.captureUnsupported` to the existing error enum and surface that. (Read `lib/src/models/supy_scan_error.dart` to choose.)

- [ ] **Step 4: Implement `captureFullFrame` on iOS**

In `ios/Classes/document/SupyDocumentScannerView.swift`:

(a) Add an `AVCapturePhotoOutput` to the session in `configureSession()`, before `commitConfiguration()`:

```swift
private let photoOutput = AVCapturePhotoOutput()
// ...inside configureSession():
if session.canAddOutput(photoOutput) {
  session.addOutput(photoOutput)
}
```

(b) Add a method-channel branch and a delegate-handling helper. Pattern: queue a `FlutterResult` against a UUID, invoke `photoOutput.capturePhoto`, write JPEG to `NSTemporaryDirectory().appendingPathComponent("supy-doc-\(uuid).jpg")`, return `{path, widthPx, heightPx}`.

(c) Implement `captureAndRectify`: take the most recent smoothed quad from `DocumentDetector`, capture a still via the same `AVCapturePhotoOutput`, then apply `CIPerspectiveCorrection`:

```swift
let ciImage = CIImage(data: photoData)!
let filter = CIFilter(name: "CIPerspectiveCorrection")!
filter.setValue(ciImage, forKey: kCIInputImageKey)
// Vision normalized quad → image-pixel CGPoints (note: Vision origin is bottom-left).
let imgW = CGFloat(ciImage.extent.width), imgH = CGFloat(ciImage.extent.height)
let tl = CGPoint(x: quad[0].x * imgW, y: (1 - quad[0].y) * imgH)
let tr = CGPoint(x: quad[1].x * imgW, y: (1 - quad[1].y) * imgH)
let br = CGPoint(x: quad[2].x * imgW, y: (1 - quad[2].y) * imgH)
let bl = CGPoint(x: quad[3].x * imgW, y: (1 - quad[3].y) * imgH)
filter.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
filter.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
filter.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")
filter.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")
let context = CIContext()
let outCI = filter.outputImage!
let cg = context.createCGImage(outCI, from: outCI.extent)!
let uiImage = UIImage(cgImage: cg)
let jpeg = uiImage.jpegData(compressionQuality: 0.92)!
let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("supy-doc-\(UUID().uuidString).jpg")
try jpeg.write(to: url, options: .atomic)
result([
  "path": url.path, "widthPx": cg.width, "heightPx": cg.height,
  "quad": quad.map { ["x": $0.x, "y": $0.y] },
])
```

(d) Replace the stub case `case "captureAndRectify":` with the real implementation (background-queue capture + CI processing). Failure path writes `result(FlutterError(code: "captureFailed", message: "…", details: nil))`.

(e) Add `case "captureFullFrame":` that captures + writes JPEG, no rectification.

- [ ] **Step 5: Run Dart tests to verify they pass**

Run: `flutter test test/channel/supy_document_event_channel_capture_test.dart`
Expected: PASS.

- [ ] **Step 6: Manual sanity check on iPhone**

Run the example app, line up a printed invoice, wait for `ready`, tap manual capture. Expected: JPEG written and surfaced to the example app. Inspect it (`open <path>`) — the page should be crop-rectified.

- [ ] **Step 7: Commit**

```bash
git add ios/Classes/document/ lib/src/widgets/supy_document_scanner_controller.dart lib/src/models/supy_scan_error.dart test/channel/supy_document_event_channel_capture_test.dart
git commit -m "feat(ios): implement captureAndRectify and captureFullFrame"
```

---

## Task 6: Widget overlay — corner reticles, brackets, ring countdown, flash

**Files:**
- Modify: `lib/src/widgets/supy_document_scanner_view.dart`
- Modify: `lib/src/models/ui/supy_scanner_palette.dart` (add `warning` color)
- Create: `test/widgets/supy_document_scanner_view_countdown_test.dart`

- [ ] **Step 1: Write failing widget tests**

```dart
// test/widgets/supy_document_scanner_view_countdown_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/supy_document_frame_state.dart';
import 'package:supy_scanner/src/models/ui/supy_document_guidance_configuration.dart';
import 'package:supy_scanner/src/widgets/supy_document_scanner_view.dart';

void main() {
  // The countdown widget should be addressable in isolation. Plan: extract the
  // countdown ring into a `SupyDocumentCountdownRing` widget exported from
  // supy_document_scanner_view.dart so it's testable without a platform view.
  testWidgets('countdown ring sweeps over autoCaptureDelay', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: SupyDocumentCountdownRing(
        duration: const Duration(milliseconds: 300),
        color: const Color(0xFF1AC0E5),
        onComplete: () => completer.complete(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 150));
    // Mid-sweep — visible.
    expect(find.byType(SupyDocumentCountdownRing), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 160));
    expect(completer.isCompleted, isTrue);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/supy_document_scanner_view_countdown_test.dart`
Expected: FAIL — widget not defined.

- [ ] **Step 3: Add `warning` to palette**

In `lib/src/models/ui/supy_scanner_palette.dart`:

Add field `final Color warning;` defaulting to `const Color(0xFFFF4D4D)`. Extend `==`, `hashCode`, and the `scanbotDark` named constructor.

- [ ] **Step 4: Rewrite the overlay painter and widget**

In `lib/src/widgets/supy_document_scanner_view.dart`:

(a) Add a `SupyDocumentCountdownRing` `StatefulWidget` with `duration`, `color`, `onComplete`. Uses `AnimationController(duration: duration)` and a `CustomPaint` drawing an arc from `-π/2` sweeping clockwise by `2π * value`.

(b) Rewrite `_DocumentGuidancePainter` so:

- When `frame.metrics.quad.isEmpty`: paint four growing corner reticles (L-shaped strokes) at the four image corners. Pulse alpha via the existing `TweenAnimationBuilder` driving a 0..1 pulse value through a 1.2s `AnimationController`.
- When `frame.metrics.quad.length == 4`: paint **only the four corner brackets** (not the full outline). Each bracket = two strokes along the two edges adjacent to the corner, ~22px each. Colour ramps red → amber → green by lerping over a `state` index (`noDocument`/failures → palette.warning, `holdSteady` → amber, `ready` → palette.primary).
- Scrim path-difference cutout remains as-is.

(c) When the state machine reports `ready` and `widget.guidance.autoCapture == true`, the widget starts a `SupyDocumentCountdownRing(duration: widget.guidance.autoCaptureDelay, ...)` overlaid in the scrim center; on completion, calls `widget.controller!.captureAndRectify()`, catches `StateError('captureUnsupported: …')`, and if `widget.guidance.allowUnrectifiedFallback` is true, retries with `captureFullFrame()`. While the countdown is in flight, transition to `SupyDocumentFrameState.capturing` via the controller's existing capture-phase mechanism (`capturePhaseAsFrameState`).

(d) On capture completion: trigger a 80ms full-screen white flash overlay (`AnimatedOpacity` from 0 → 1 → 0 with 80ms duration each leg). Fire `HapticFeedback.lightImpact()`.

(e) Replace `_HintCard`'s `border` shape with a single text-only line (no border ring) per spec §3.5.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widgets/supy_document_scanner_view_countdown_test.dart`
Expected: PASS.

Run: `flutter test`
Expected: PASS (full suite).

- [ ] **Step 6: Manual UI sanity check**

Run the example app on iPhone. Verify the overlay shows:
- Reticles when no quad.
- Brackets (not full outline) when quad detected.
- Ring sweep when `ready`.
- 80ms flash + JPEG produced on countdown completion.

- [ ] **Step 7: Commit**

```bash
git add lib/src/widgets/ lib/src/models/ui/supy_scanner_palette.dart test/widgets/
git commit -m "feat(document): overlay reticles, brackets, ring countdown, capture flash"
```

---

## Task 7: Android native C++ document-edge detector — scaffold + API

**Files:**
- Create: `native/document/document_edge_detector.h`
- Create: `native/document/document_edge_detector.cpp`
- Create: `native/document/document_edge_detector_test.cpp`
- Modify: `native/CMakeLists.txt`

- [ ] **Step 1: Define the C++ API**

```cpp
// native/document/document_edge_detector.h
#pragma once
#include <array>
#include <cstdint>
#include <optional>

namespace supy::scanner::document {

struct Point { float x; float y; }; // normalized [0,1], top-left origin

struct DetectedQuad {
  std::array<Point, 4> corners; // TL, TR, BR, BL
  float coverageRatio;          // quad area / image area
  float tiltDegrees;            // 0 = head-on
};

struct DetectionInput {
  const uint8_t* luma;   // Y plane
  int width;
  int height;
  int rowStride;
};

// Returns std::nullopt if no acceptable quad found.
std::optional<DetectedQuad> detectDocument(const DetectionInput& in);

}  // namespace
```

- [ ] **Step 2: Write the failing GoogleTest cases**

```cpp
// native/document/document_edge_detector_test.cpp
#include "document/document_edge_detector.h"
#include <gtest/gtest.h>
#include <vector>

using namespace supy::scanner::document;

// Synthesizes a 256×256 Y-plane with a bright rectangle on dark background.
static std::vector<uint8_t> makeRectImage(int w, int h, int x0, int y0, int x1, int y1) {
  std::vector<uint8_t> img(static_cast<size_t>(w * h), 30);
  for (int y = y0; y < y1; ++y)
    for (int x = x0; x < x1; ++x) img[y * w + x] = 200;
  return img;
}

TEST(DocumentEdgeDetector, DetectsCenteredRectangle) {
  auto img = makeRectImage(256, 256, 40, 60, 220, 200);
  DetectionInput in{img.data(), 256, 256, 256};
  auto q = detectDocument(in);
  ASSERT_TRUE(q.has_value());
  // TL near (40/256, 60/256), BR near (220/256, 200/256).
  EXPECT_NEAR(q->corners[0].x, 40.f / 256.f, 0.05f);
  EXPECT_NEAR(q->corners[2].y, 200.f / 256.f, 0.05f);
}

TEST(DocumentEdgeDetector, ReturnsNulloptOnUniformInput) {
  std::vector<uint8_t> img(256 * 256, 128);
  DetectionInput in{img.data(), 256, 256, 256};
  EXPECT_FALSE(detectDocument(in).has_value());
}
```

- [ ] **Step 3: Wire CMake**

Append to `native/CMakeLists.txt` (next to existing core sources):

```cmake
target_sources(supy_scanner_core PRIVATE
  document/document_edge_detector.cpp
)
target_include_directories(supy_scanner_core PUBLIC .)

if(SUPY_BUILD_TESTS)
  add_executable(supy_scanner_core_tests
    document/document_edge_detector_test.cpp
  )
  target_link_libraries(supy_scanner_core_tests PRIVATE supy_scanner_core gtest gtest_main)
endif()
```

(Match the project's existing `SUPY_BUILD_TESTS` flag; create the flag if missing — default OFF in Android builds, ON in host CI runs.)

- [ ] **Step 4: Run the tests on host to verify they fail**

Run from repo root:

```bash
cmake -S native -B build/native -DSUPY_BUILD_TESTS=ON
cmake --build build/native --target supy_scanner_core_tests
./build/native/supy_scanner_core_tests
```

Expected: FAIL (undefined symbol — `detectDocument` not implemented).

- [ ] **Step 5: Implement the pipeline**

In `native/document/document_edge_detector.cpp`, implement the 7-stage pipeline from spec §3.1. Each helper is its own small function — keep the file focused and each function ≤40 lines:

- `downsampleAndCrop(in, out256)` — bilinear to 256-px long-edge, center-crop the working frame.
- `gaussianBlur3x3(buf)` — separable 3×3 box (acceptable approximation).
- `sobelMagnitude(blur, mag)` — `Gx = [-1,0,1; -2,0,2; -1,0,1]`, `Gy = transpose`, `mag = |Gx|+|Gy|`.
- `adaptiveCannyThresholds(mag, lo, hi)` — `hi = median(mag) * 2.5`, `lo = hi * 0.4`.
- `cannyNonMaxSuppression(mag, lo, hi, edges)` — standard hysteresis-thresholded edge map.
- `houghLines(edges, lines, maxLines=120)` — accumulator over `(rho, theta)`, vote, peak-pick.
- `clusterDominantAngles(lines, four_angles)` — group lines into 4 bins by angle clustering (k-means k=2 for horizontal/vertical, ±90°).
- `intersectToQuads(lines, candidate_quads)` — for each pair of horizontal lines and each pair of vertical lines, compute four intersection points.
- `scoreQuad(quad, edges, w, h)` — combined score: `area_in_band * edge_energy_along_sides * orthogonality_bonus`.
- `pickBest(candidates)` — return the highest-scoring quad, or `nullopt` if no candidate clears `minScore`.

Map the winning quad back to normalized coordinates of the full image (undo the crop+downsample). Compute `coverageRatio` and `tiltDegrees` (tilt = angle of the top edge from horizontal).

The implementations are small. The plan does not inline 400 lines of CV here — engineers should iterate one helper at a time, each driven by adding a focused unit test (e.g. `TEST(Sobel, KnownEdge)` for the Sobel kernel) before implementing.

- [ ] **Step 6: Run the tests until they pass**

Re-run the build from Step 4 until both top-level tests pass. Add per-helper tests as needed; commit small, frequent.

- [ ] **Step 7: Commit (the whole CV slice)**

```bash
git add native/document/ native/CMakeLists.txt
git commit -m "feat(native): C++ document-edge detector with adaptive Canny + Hough pipeline"
```

---

## Task 8: JNI binding for `detectQuad`

**Files:**
- Modify: `android/src/main/cpp/supy_scanner_core_jni.cpp`
- Modify: `android/src/main/kotlin/io/supy/scanner/nativecore/SupyNativeCore.kt`

- [ ] **Step 1: Add the Kotlin external + facade**

In `SupyNativeCore.kt`, add:

```kotlin
data class NativeQuad(
  val corners: FloatArray,        // [x0,y0,x1,y1,x2,y2,x3,y3]
  val coverageRatio: Float,
  val tiltDegrees: Float,
)

@JvmStatic external fun nativeDetectQuad(
  yPlane: java.nio.ByteBuffer,
  width: Int, height: Int, rowStride: Int,
): FloatArray? // null when no quad; else [x0,y0,..,x3,y3, coverage, tilt]

fun detectQuad(y: java.nio.ByteBuffer, w: Int, h: Int, stride: Int): NativeQuad? {
  if (!ensureLoaded()) return null
  val raw = nativeDetectQuad(y, w, h, stride) ?: return null
  val corners = FloatArray(8) { raw[it] }
  return NativeQuad(corners, raw[8], raw[9])
}
```

- [ ] **Step 2: Implement the JNI bridge**

In `android/src/main/cpp/supy_scanner_core_jni.cpp`, append:

```cpp
#include "document/document_edge_detector.h"
#include <jni.h>

extern "C" JNIEXPORT jfloatArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeDetectQuad(
    JNIEnv* env, jclass, jobject yBuffer, jint w, jint h, jint stride) {
  using namespace supy::scanner::document;
  auto* ptr = static_cast<uint8_t*>(env->GetDirectBufferAddress(yBuffer));
  if (!ptr || w <= 0 || h <= 0 || stride < w) return nullptr;
  DetectionInput in{ptr, w, h, stride};
  auto result = detectDocument(in);
  if (!result) return nullptr;
  jfloatArray arr = env->NewFloatArray(10);
  if (!arr) return nullptr;
  jfloat buf[10] = {
    result->corners[0].x, result->corners[0].y,
    result->corners[1].x, result->corners[1].y,
    result->corners[2].x, result->corners[2].y,
    result->corners[3].x, result->corners[3].y,
    result->coverageRatio, result->tiltDegrees,
  };
  env->SetFloatArrayRegion(arr, 0, 10, buf);
  return arr;
}
```

- [ ] **Step 3: Build to verify it links**

Run from `android/`: `./gradlew :supy_scanner:externalNativeBuildDebug`
Expected: PASS (no link errors).

- [ ] **Step 4: Commit**

```bash
git add android/src/main/cpp/supy_scanner_core_jni.cpp android/src/main/kotlin/io/supy/scanner/nativecore/SupyNativeCore.kt
git commit -m "feat(android): JNI bridge for native document-edge detector"
```

---

## Task 9: `DocumentFrameAnalyzer` wires the JNI detector

**Files:**
- Modify: `android/src/main/kotlin/io/supy/scanner/document/DocumentFrameAnalyzer.kt`

- [ ] **Step 1: Read the current analyzer**

Run: `cat android/src/main/kotlin/io/supy/scanner/document/DocumentFrameAnalyzer.kt`

Locate the `analyze(image: ImageProxy)` body where `quad = emptyList()` is emitted.

- [ ] **Step 2: Wire `SupyNativeCore.detectQuad`**

Replace the empty `quad` emission with:

```kotlin
private val nativeAvailable: Boolean = SupyNativeCore.ensureLoaded()
private val stabilityTracker = QuadStabilityTracker(windowSize = 6)

override fun analyze(image: ImageProxy) {
  try {
    val plane = image.planes[0]
    val w = image.width
    val h = image.height
    val stride = plane.rowStride

    val nativeResult = if (nativeAvailable) {
      SupyNativeCore.detectQuad(plane.buffer, w, h, stride)
    } else null

    val quad: List<Map<String, Float>> = if (nativeResult != null) {
      val c = nativeResult.corners
      listOf(
        mapOf("x" to c[0], "y" to c[1]),
        mapOf("x" to c[2], "y" to c[3]),
        mapOf("x" to c[4], "y" to c[5]),
        mapOf("x" to c[6], "y" to c[7]),
      )
    } else emptyList()

    val coverage = nativeResult?.coverageRatio ?: 0f
    val tilt = nativeResult?.tiltDegrees ?: 0f

    // Existing luma + blur computation stays.
    val meanLuma = computeMeanLuma(plane, w, h, stride)
    val blur = computeBlurScore(plane, w, h, stride)
    val interior = if (nativeResult != null)
      computeInteriorVariance(plane, w, h, stride, nativeResult.corners) else 0f
    val stability = if (nativeResult != null)
      stabilityTracker.push(nativeResult.corners) else { stabilityTracker.reset(); 0f }

    onMetrics(mapOf(
      "quad" to quad,
      "coverageRatio" to coverage,
      "tiltDegrees" to tilt,
      "meanLuma" to meanLuma,
      "blurScore" to blur,
      "clipsEdge" to detectsEdgeClip(nativeResult?.corners),
      "interiorVariance" to interior,
      "quadStability" to stability,
    ))
  } catch (t: Throwable) {
    onError(t.message ?: "analyzer failure")
  } finally {
    image.close()
  }
}
```

(`computeInteriorVariance` mirrors the iOS helper in Kotlin — variance-of-Laplacian inside the corner-bounded box on the downsampled Y plane. `QuadStabilityTracker` ports the iOS class.)

- [ ] **Step 3: Add a JVM-side analyzer test if the existing test layout permits, otherwise rely on the manual QA in Task 11.**

- [ ] **Step 4: Commit**

```bash
git add android/src/main/kotlin/io/supy/scanner/document/
git commit -m "feat(android): wire JNI document detector into frame analyzer with graceful fallback"
```

---

## Task 10: Android `captureFullFrame` MethodChannel handler

**Files:**
- Modify: `android/src/main/kotlin/io/supy/scanner/document/SupyDocumentScannerView.kt`

- [ ] **Step 1: Read the existing MethodChannel switch**

Find the `setMethodCallHandler` block. Locate the existing `captureAndRectify` UNIMPLEMENTED stub.

- [ ] **Step 2: Add CameraX `ImageCapture` to the camera bind**

Where `LifecycleCameraController` is built (or `cameraProvider.bindToLifecycle`), include an `ImageCapture` instance:

```kotlin
private val imageCapture: ImageCapture = ImageCapture.Builder()
  .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
  .build()
// bindToLifecycle(... preview, analyzer, imageCapture)
```

- [ ] **Step 3: Implement the `captureFullFrame` handler**

```kotlin
"captureFullFrame" -> {
  val file = File.createTempFile("supy-doc-", ".jpg", context.cacheDir)
  val output = ImageCapture.OutputFileOptions.Builder(file).build()
  imageCapture.takePicture(
    output, ContextCompat.getMainExecutor(context),
    object : ImageCapture.OnImageSavedCallback {
      override fun onImageSaved(out: ImageCapture.OutputFileResults) {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, opts)
        result.success(mapOf(
          "path" to file.absolutePath,
          "widthPx" to opts.outWidth,
          "heightPx" to opts.outHeight,
        ))
      }
      override fun onError(exc: ImageCaptureException) {
        result.error("captureFailed", exc.message, null)
      }
    }
  )
}
```

`captureAndRectify` stays UNIMPLEMENTED until Sprint 4 — leave the existing branch in place.

- [ ] **Step 4: Manual sanity check**

Run example on a Pixel 6a. Confirm:
- Native edge detector triggers — bracket overlay appears on a real document.
- Tap manual capture in ready state. Confirm fallback flow: `captureAndRectify` UNIMPLEMENTED → widget retries `captureFullFrame` → JPEG written.

- [ ] **Step 5: Commit**

```bash
git add android/src/main/kotlin/io/supy/scanner/document/SupyDocumentScannerView.kt
git commit -m "feat(android): implement captureFullFrame as fallback for unrectified capture"
```

---

## Task 11: Manual QA pass against `docs/QA.md`

**Files:**
- Modify: `docs/QA.md` (add scenarios)

- [ ] **Step 1: Append QA scenarios**

In `docs/QA.md`, add a "Phase: Document Scanner Smart Guidance" section with the scenarios from spec §6, manual QA bullet:

```markdown
### Document Scanner Smart Guidance (2026-06-14)

Run on Pixel 6a + iPhone 13:

- [ ] Invoice on dark desk → quad detected within 1s, ring countdown fires.
- [ ] Invoice held in hand (motion) → `holdSteady` shows, never auto-snaps until stable.
- [ ] Invoice on a laptop screen showing the same scan → must NOT trigger ready (interior-variance gate).
- [ ] Invoice partially off-frame → `tooClose` with `clipsEdge`.
- [ ] Low-light desk → `tooDark`.
- [ ] Tilted 30° → `tooSkewed`.
- [ ] Auto-snap: ring countdown visible, cancellable by tilting, fires capture; manual button still works while countdown not active.
- [ ] Capture JPEG: open the file from the example app's surfaced path; verify rectification on iOS, full-frame on Android.
```

- [ ] **Step 2: Walk every checkbox on real hardware**

Attach screenshots / capture sample JPEGs to the PR. Note any threshold tuning needed (especially `interiorVarianceFloor` per spec §9.3).

- [ ] **Step 3: Commit**

```bash
git add docs/QA.md
git commit -m "docs(qa): add document scanner smart guidance manual QA scenarios"
```

---

## Task 12: Doc updates — ARCHITECTURE, BRANDING_PARITY, TODO, CHANGELOG

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/internal/BRANDING_PARITY.md`
- Modify: `TODO.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: ARCHITECTURE.md channel table**

Add rows for `frame_metrics.quadStability`, `frame_metrics.interiorVariance`, `captureAndRectify`, `captureFullFrame`. Note that the channel name stays `io.supy.scanner/v1` (additive).

- [ ] **Step 2: BRANDING_PARITY.md — new Document Scanner section**

Add a section mirroring the Batch table:

| Element | Literal | Source |
|---|---|---|
| Corner reticles | `palette.warning` `#FF4D4D` | `SupyScannerPalette` |
| Corner brackets (failure) | `palette.warning` | " |
| Corner brackets (ready) | `palette.primary` `#1AC0E5` | " |
| Ring countdown stroke | `palette.primary` | " |
| Capture flash | `Colors.white`, 80ms | hardcoded |
| Hint pill scrim | `black @ 0.55` | mirrors batch |

Add the note: "Document overlay literals route through `SupyScannerPalette` rather than native-side duplication, because the overlay is Dart (not native chrome). No hardcoded `#6448C3` or other purple in the library; example-app theme override stays in `example/`."

- [ ] **Step 3: TODO.md — sprint progress**

Check off V1-S6-02 iOS half (`captureAndRectify`). Note the Android half remains blocked on Sprint 4 `warpPerspective`. Add a decisions-section entry: "2026-06-14: Embedded document scanner gains smart guidance + auto-snap + interior-variance gate. Channel additive (no v2). Android `captureAndRectify` stays UNIMPLEMENTED until Sprint 4; widget falls back to `captureFullFrame` so users never hit a dead button."

- [ ] **Step 4: CHANGELOG.md**

Add an `## [Unreleased]` entry:

```markdown
### Added
- `SupyDocumentFrameState.holdSteady` between failing and `ready`.
- `quadStability` and `interiorVariance` metric fields on the document EventChannel.
- `captureAndRectify` (iOS only — Android UNIMPLEMENTED until Sprint 4) and `captureFullFrame` MethodChannel methods.
- Auto-capture countdown widget with 600ms default delay; configurable via `SupyDocumentGuidanceConfiguration.autoCapture` / `autoCaptureDelay`.
- Android native C++ document-edge detector (`supy_scanner_core` JNI).

### Changed
- iOS document detector now gates on confidence ≥ 0.7, aspect 0.4–1.0, and interior variance ≥ 5.0 — rejects laptop-screen false positives.
- Document overlay redesigned: corner reticles / brackets / ring countdown / capture flash, palette-driven.
- Default hint copy updated for clarity ("Hold the camera flat", "Move closer", "Don't move").
```

- [ ] **Step 5: Commit**

```bash
git add docs/ARCHITECTURE.md docs/internal/BRANDING_PARITY.md TODO.md CHANGELOG.md
git commit -m "docs: document smart-guidance additions across architecture, branding, todo, changelog"
```

---

## Self-Review Notes

**Spec coverage check:**

- §3.1 Android C++ detector → Tasks 7, 8, 9 ✓
- §3.2 iOS hardening → Task 4 ✓
- §3.3 Channel additions (`quadStability`, `interiorVariance`, `captureAndRectify`, `captureFullFrame`) → Tasks 1, 5, 10, 12 ✓
- §3.4 FSM `holdSteady` + countdown → Tasks 2, 3, 6 ✓
- §3.5 Overlay polish → Task 6 ✓
- §3.6 Hint copy → Task 2 ✓
- §5 Error handling (UNIMPLEMENTED fallback, JNI load failure) → Tasks 5, 9, 10 ✓
- §6 Testing → Tasks 1, 3, 4, 5, 6, 7, 11 ✓
- §7 Build sequence → Tasks 1–12 (interleaves correctly, iOS-first) ✓
- §8 Brand parity → Task 6 (palette + warning) + Task 12 (BRANDING_PARITY.md section) ✓

**Open question to resolve during execution (spec §9):**
- §9.3 `interiorVarianceFloor` value — start at `5.0`, tune in Task 11 QA. Plan reflects this in the test threshold and the QA bullet.

**Acknowledged trade-off:** Task 7's C++ pipeline doesn't inline the per-helper bodies (Sobel/Hough/etc.) — instead the engineer iterates one helper at a time, test-first, against the GoogleTest harness. This is deliberate: 400 lines of CV inline would degrade the plan's signal, and the spec §3.1 pipeline already enumerates the algorithm steps in implementation order.

---

Plan complete and saved to `docs/superpowers/plans/2026-06-14-document-scanner-smart-guidance.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
