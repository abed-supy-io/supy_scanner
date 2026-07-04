# Phase CSU · Sprint 1 — iOS Capture Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make iOS `captureAndRectify` produce a correctly-cropped, on-still-refined document image — the WS1 exit gate of `docs/superpowers/specs/2026-07-03-supy-document-scanner-replaces-scanbot-design.md`.

**Architecture:** Three new pure Swift units (`QuadGeometry` IoU math, `PreviewPhotoQuadMapper` aspect-space mapping, `DocumentStillRefiner` on-still Vision re-detection) compose into a new testable `DocumentRectifyPipeline` that `SupyDocumentScannerView.processRectifyCapture` delegates to. The pipeline fixes a latent bug (the analyzer-stream quad is currently applied to the still with **no aspect mapping** — a 16:9 analyzer quad mis-crops a 4:3 photo) and adds the spec's on-still refinement: re-detect on the captured photo, accept when IoU ≥ 0.8 vs the mapped preview quad, otherwise fall back to the mapped quad — capture never fails because refinement fails. The result payload gains an additive `quadSource` key surfaced on Dart's `SupyDocumentCapture` for Sprint-4 bench measurement.

**Tech Stack:** Swift (iOS 16 floor), Vision (`VNDetectDocumentSegmentationRequest` iOS 17+ / `VNDetectRectanglesRequest` iOS 16), Core Image (`CIPerspectiveCorrection`), XCTest via the `supy_scanner-Unit-Tests` pod test spec, Dart/Flutter for the model passthrough.

## Sprint roadmap (context, not scope)

Phase CSU spans four sprints. **This plan covers Sprint 1 only.** Plans for later sprints are written at each sprint boundary because they depend on earlier outcomes:

- Sprint 2 — Dart scanner screen (`SupyDocumentScannerScreen`, `startMultiPage` routing via caller's `BuildContext`, minimal review UI, additive `supy` backend value).
- Sprint 3 — Android parity (C++ guidance on embedded view, seeded still refinement, `filter` native mapping).
- Sprint 4 — Proof & Scanbot removal (bench harness, QA walkthrough, retailer pilot).

**Already implemented in the working tree — do NOT redo:** Dart native-state deferral (`lib/src/widgets/supy_document_scanner_view.dart:263-274` trusts the wire `state` ordinal and skips the Dart FSM), the `filter`/`preferredBackend`/`SupyDocumentFilter` Dart options, and the iOS `DocumentEnhancer` filter chains.

## Global Constraints

- **Drop-in Scanbot compat:** public Dart API changes must be additive only (new optional fields/params). Never rename/remove existing members.
- **Channel:** `io.supy.scanner/v1` — never bump. New payload keys are additive and must be documented in `docs/ARCHITECTURE.md` in the same commit series.
- **iOS deployment target is iOS 16.** Any iOS 17+ API needs `if #available(iOS 17, *)` with a working iOS 16 fallback.
- `AVCaptureSession` start/stop and photo-capture initiation stay on `sessionQueue`; Vision requests and Core Image rendering stay off the main thread (existing code already routes heavy work to `DispatchQueue.global(qos: .userInitiated)` — keep it there).
- **No paid SDKs, no network calls in the scanning path, no secrets in commits.**
- **Dirty working tree:** in-flight v1.1 work is uncommitted. `git add` ONLY the files named in each commit step. Never `git add -A` / `git add .`.
- Conventional commits; every commit message ends with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- New Swift source goes in `ios/Classes/document/`, tests in `ios/Tests/document/` (picked up by the podspec globs `Classes/**/*.{swift,h,m,mm}` and `Tests/**/*.swift`). **After creating any new Swift file, re-run `pod install` in `example/ios` so the Pods project picks it up.**
- Swift test files import the plugin module the same way the existing tests do — check the import line at the top of `ios/Tests/document/DocumentDetectorTests.swift` and copy it (expected: `@testable import supy_scanner`).
- Quad convention everywhere in this plan: **normalized [0,1], top-left origin, TL/TR/BR/BL order** — same as `DocumentDetector.snapshotLatestQuad()` output. The only bottom-left-origin moment is the existing single Y-flip when denormalizing into `CIPerspectiveCorrection` inputs.
- Line numbers cited below are from the 2026-07-03 tree. Read the file before editing; adjust anchors if the in-flight work has shifted them.

## Environment prep (once, before Task 1)

```bash
cd example && flutter build ios --config-only --no-codesign
cd ios && pod install
```

Expected: `pod install` ends with `Pod installation complete!`. All iOS test commands below run from `example/ios`.

---

### Task 1: `QuadGeometry` — convex-quad IoU

**Files:**
- Create: `ios/Classes/document/QuadGeometry.swift`
- Test: `ios/Tests/document/QuadGeometryTests.swift`

**Interfaces:**
- Consumes: nothing (pure CoreGraphics math).
- Produces: `QuadGeometry.area(_ points: [CGPoint]) -> CGFloat`, `QuadGeometry.iou(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat`. Task 3's refiner and its tests call `iou`.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/document/QuadGeometryTests.swift`:

```swift
import XCTest
@testable import supy_scanner

final class QuadGeometryTests: XCTestCase {
  private let unitSquare = [
    CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
    CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
  ]

  func testAreaOfUnitSquare() {
    XCTAssertEqual(QuadGeometry.area(unitSquare), 1.0, accuracy: 1e-9)
  }

  func testIoUOfIdenticalQuadsIsOne() {
    XCTAssertEqual(QuadGeometry.iou(unitSquare, unitSquare), 1.0, accuracy: 1e-6)
  }

  func testIoUOfDisjointQuadsIsZero() {
    let far = unitSquare.map { CGPoint(x: $0.x + 5, y: $0.y + 5) }
    XCTAssertEqual(QuadGeometry.iou(unitSquare, far), 0.0, accuracy: 1e-9)
  }

  func testIoUOfHalfOverlapIsOneThird() {
    // B is A shifted right by 0.5: intersection 0.5, union 1.5 → IoU 1/3.
    let shifted = unitSquare.map { CGPoint(x: $0.x + 0.5, y: $0.y) }
    XCTAssertEqual(QuadGeometry.iou(unitSquare, shifted), 1.0 / 3.0, accuracy: 1e-6)
  }

  func testIoUIsWindingOrderInsensitive() {
    let clockwise = [unitSquare[0], unitSquare[3], unitSquare[2], unitSquare[1]]
    let shifted = unitSquare.map { CGPoint(x: $0.x + 0.5, y: $0.y) }
    XCTAssertEqual(
      QuadGeometry.iou(clockwise, shifted), 1.0 / 3.0, accuracy: 1e-6)
  }

  func testIoUWithDegenerateQuadIsZero() {
    let line = [
      CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
      CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0),
    ]
    XCTAssertEqual(QuadGeometry.iou(unitSquare, line), 0.0, accuracy: 1e-9)
  }

  func testIoUOfTiltedOverlappingQuads() {
    // A diamond inscribed in the unit square: area 0.5, fully inside A.
    // IoU = 0.5 / (1 + 0.5 - 0.5) = 0.5.
    let diamond = [
      CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.5),
      CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.5),
    ]
    XCTAssertEqual(QuadGeometry.iou(unitSquare, diamond), 0.5, accuracy: 1e-6)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -only-testing:supy_scanner-Unit-Tests/QuadGeometryTests 2>&1 | tail -20
```

Expected: **build failure** — `cannot find 'QuadGeometry' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ios/Classes/document/QuadGeometry.swift`:

```swift
import CoreGraphics

/// Pure geometry helpers for comparing detection quads.
/// Points are normalized [0,1], top-left origin, TL/TR/BR/BL order,
/// but the math is origin/scale agnostic — only consistency between the two
/// polygons matters.
enum QuadGeometry {
  /// Absolute polygon area via the shoelace formula.
  static func area(_ points: [CGPoint]) -> CGFloat {
    guard points.count >= 3 else { return 0 }
    var sum: CGFloat = 0
    for i in 0..<points.count {
      let a = points[i]
      let b = points[(i + 1) % points.count]
      sum += a.x * b.y - b.x * a.y
    }
    return abs(sum) / 2
  }

  /// Intersection-over-union of two convex quads. 0 when either is degenerate.
  static func iou(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
    let areaA = area(a)
    let areaB = area(b)
    guard areaA > 1e-9, areaB > 1e-9 else { return 0 }
    let inter = area(clip(subject: a, by: b))
    let union = areaA + areaB - inter
    guard union > 0 else { return 0 }
    return inter / union
  }

  /// Sutherland–Hodgman clip of one convex polygon by another.
  static func clip(subject: [CGPoint], by clipPolygon: [CGPoint]) -> [CGPoint] {
    guard subject.count >= 3, clipPolygon.count >= 3 else { return [] }
    var output = normalizedWinding(subject)
    let clipper = normalizedWinding(clipPolygon)
    for i in 0..<clipper.count {
      guard !output.isEmpty else { return [] }
      let edgeA = clipper[i]
      let edgeB = clipper[(i + 1) % clipper.count]
      let input = output
      output = []
      for j in 0..<input.count {
        let current = input[j]
        let previous = input[(j + input.count - 1) % input.count]
        let currentInside = isInside(current, edgeA: edgeA, edgeB: edgeB)
        let previousInside = isInside(previous, edgeA: edgeA, edgeB: edgeB)
        if currentInside {
          if !previousInside {
            output.append(intersection(previous, current, edgeA, edgeB))
          }
          output.append(current)
        } else if previousInside {
          output.append(intersection(previous, current, edgeA, edgeB))
        }
      }
    }
    return output
  }

  /// Forces the winding that makes `isInside`'s cross-product sign valid.
  private static func normalizedWinding(_ points: [CGPoint]) -> [CGPoint] {
    var sum: CGFloat = 0
    for i in 0..<points.count {
      let a = points[i]
      let b = points[(i + 1) % points.count]
      sum += (b.x - a.x) * (b.y + a.y)
    }
    return sum > 0 ? points.reversed() : points
  }

  private static func isInside(_ p: CGPoint, edgeA: CGPoint, edgeB: CGPoint) -> Bool {
    (edgeB.x - edgeA.x) * (p.y - edgeA.y) - (edgeB.y - edgeA.y) * (p.x - edgeA.x) >= 0
  }

  private static func intersection(
    _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint
  ) -> CGPoint {
    let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
    guard abs(d) > 1e-12 else { return p2 }
    let a = p1.x * p2.y - p1.y * p2.x
    let b = p3.x * p4.y - p3.y * p4.x
    return CGPoint(
      x: (a * (p3.x - p4.x) - (p1.x - p2.x) * b) / d,
      y: (a * (p3.y - p4.y) - (p1.y - p2.y) * b) / d
    )
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -only-testing:supy_scanner-Unit-Tests/QuadGeometryTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with 7 tests passing.

- [ ] **Step 5: Commit**

```bash
git add ios/Classes/document/QuadGeometry.swift ios/Tests/document/QuadGeometryTests.swift
git commit -m "feat(ios): add convex-quad IoU geometry for still-capture refinement

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `PreviewPhotoQuadMapper` — analyzer→still aspect mapping

**Files:**
- Create: `ios/Classes/document/PreviewPhotoQuadMapper.swift`
- Test: `ios/Tests/document/PreviewPhotoQuadMapperTests.swift`

**Interfaces:**
- Consumes: nothing (pure math).
- Produces: `PreviewPhotoQuadMapper.mapNormalizedQuad(_ quad: [CGPoint], from source: CGSize, to dest: CGSize) -> [CGPoint]`. Task 4's pipeline calls this with `source` = analyzer oriented size, `dest` = still oriented size.

Physical model: the analyzer stream and the photo output share one sensor; when their aspect ratios differ, the narrower-aspect output is (to first order) a centered crop of the wider one. Residual FOV error beyond this model is absorbed by Task 3's on-still re-detection.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/document/PreviewPhotoQuadMapperTests.swift`:

```swift
import XCTest
@testable import supy_scanner

final class PreviewPhotoQuadMapperTests: XCTestCase {
  private let quad = [
    CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.9, y: 0.3),
    CGPoint(x: 0.9, y: 0.7), CGPoint(x: 0.1, y: 0.7),
  ]

  func testSameAspectIsIdentity() {
    let mapped = PreviewPhotoQuadMapper.mapNormalizedQuad(
      quad, from: CGSize(width: 1080, height: 1920),
      to: CGSize(width: 2160, height: 3840))
    for (m, q) in zip(mapped, quad) {
      XCTAssertEqual(m.x, q.x, accuracy: 1e-9)
      XCTAssertEqual(m.y, q.y, accuracy: 1e-9)
    }
  }

  func testPortrait16x9AnalyzerToPortrait4x3Still() {
    // Analyzer 1080×1920 (aspect 0.5625) → still 3024×4032 (aspect 0.75).
    // The analyzer sees the still's full height; horizontally it covers the
    // centered fraction 0.5625/0.75 = 0.75 → offsetX = 0.125.
    let mapped = PreviewPhotoQuadMapper.mapNormalizedQuad(
      quad, from: CGSize(width: 1080, height: 1920),
      to: CGSize(width: 3024, height: 4032))
    XCTAssertEqual(mapped[0].x, 0.125 + 0.1 * 0.75, accuracy: 1e-9)  // 0.2
    XCTAssertEqual(mapped[0].y, 0.3, accuracy: 1e-9)
    XCTAssertEqual(mapped[1].x, 0.125 + 0.9 * 0.75, accuracy: 1e-9)  // 0.8
    XCTAssertEqual(mapped[2].y, 0.7, accuracy: 1e-9)
  }

  func testWiderSourceExpandsHorizontally() {
    // Source aspect 0.75 → dest aspect 0.5625: dest is the centered
    // horizontal band of source (they share full height), so x expands by
    // 1/0.75 around the center and may leave [0,1] — callers clamp.
    let mapped = PreviewPhotoQuadMapper.mapNormalizedQuad(
      quad, from: CGSize(width: 3024, height: 4032),
      to: CGSize(width: 1080, height: 1920))
    XCTAssertEqual(mapped[0].x, (0.1 - 0.125) / 0.75, accuracy: 1e-9)  // -0.0333…
    XCTAssertEqual(mapped[1].x, (0.9 - 0.125) / 0.75, accuracy: 1e-9)  //  1.0333…
    XCTAssertEqual(mapped[0].y, 0.3, accuracy: 1e-9)
    XCTAssertEqual(mapped[2].y, 0.7, accuracy: 1e-9)
  }

  func testRoundTripIsIdentity() {
    let a = CGSize(width: 1080, height: 1920)
    let b = CGSize(width: 3024, height: 4032)
    let there = PreviewPhotoQuadMapper.mapNormalizedQuad(quad, from: a, to: b)
    let back = PreviewPhotoQuadMapper.mapNormalizedQuad(there, from: b, to: a)
    for (r, q) in zip(back, quad) {
      XCTAssertEqual(r.x, q.x, accuracy: 1e-9)
      XCTAssertEqual(r.y, q.y, accuracy: 1e-9)
    }
  }

  func testZeroSizeReturnsQuadUnchanged() {
    let mapped = PreviewPhotoQuadMapper.mapNormalizedQuad(
      quad, from: .zero, to: CGSize(width: 3024, height: 4032))
    XCTAssertEqual(mapped, quad)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -only-testing:supy_scanner-Unit-Tests/PreviewPhotoQuadMapperTests 2>&1 | tail -20
```

Expected: **build failure** — `cannot find 'PreviewPhotoQuadMapper' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ios/Classes/document/PreviewPhotoQuadMapper.swift`:

```swift
import CoreGraphics

/// Maps a normalized quad between two capture spaces that share a sensor
/// field of view but differ in aspect ratio (e.g. a 16:9 analyzer stream vs
/// a 4:3 still). Models the narrower-aspect space as a horizontally centered
/// crop of the wider one — both spaces share the full long axis because the
/// scanner session is portrait-locked. Residual FOV error is corrected
/// downstream by on-still re-detection (`DocumentStillRefiner`).
enum PreviewPhotoQuadMapper {
  /// `quad`: normalized [0,1], top-left origin, relative to `source`.
  /// `source` / `dest`: oriented pixel sizes (post-rotation, i.e. portrait
  /// sizes for portrait sessions) of each space.
  /// Returns the quad normalized [0,1] relative to `dest`.
  static func mapNormalizedQuad(
    _ quad: [CGPoint],
    from source: CGSize,
    to dest: CGSize
  ) -> [CGPoint] {
    guard source.width > 0, source.height > 0, dest.width > 0, dest.height > 0
    else { return quad }
    let sourceAspect = source.width / source.height
    let destAspect = dest.width / dest.height
    if abs(sourceAspect - destAspect) < 0.001 { return quad }
    if sourceAspect < destAspect {
      // Source is the narrower space: it shares the full long axis (height —
      // the session is portrait-locked) and occupies a centered horizontal
      // band of dest.
      let f = sourceAspect / destAspect
      let c = (1 - f) / 2
      return quad.map { CGPoint(x: c + $0.x * f, y: $0.y) }
    } else {
      // Source is the wider space: dest is the centered horizontal band of
      // source — the exact inverse of the branch above, so round-trips are
      // identity. Mapped x may leave [0,1]; callers clamp.
      let f = destAspect / sourceAspect
      let c = (1 - f) / 2
      return quad.map { CGPoint(x: ($0.x - c) / f, y: $0.y) }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -only-testing:supy_scanner-Unit-Tests/PreviewPhotoQuadMapperTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with 5 tests passing.

- [ ] **Step 5: Commit**

```bash
git add ios/Classes/document/PreviewPhotoQuadMapper.swift ios/Tests/document/PreviewPhotoQuadMapperTests.swift
git commit -m "feat(ios): map analyzer-space quads into still-photo space (centered-crop FOV model)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `DocumentStillRefiner` — on-still re-detection with IoU gate

**Files:**
- Create: `ios/Classes/document/DocumentStillRefiner.swift`
- Test: `ios/Tests/document/DocumentStillRefinerTests.swift`

**Interfaces:**
- Consumes: `QuadGeometry.iou(_:_:)` from Task 1.
- Produces:
  - `struct DocumentStillRefinement { let quad: [CGPoint]; let refined: Bool }`
  - `DocumentStillRefiner.refine(still: CIImage, seedQuad: [CGPoint], minIoU: CGFloat = 0.8) -> DocumentStillRefinement` — synchronous, background-queue only.
  - `DocumentStillRefiner.evaluate(candidates: [[CGPoint]], seedQuad: [CGPoint], minIoU: CGFloat) -> DocumentStillRefinement` — pure accept/reject logic, exposed for tests.
  - Task 4's pipeline injects `refine` as its default refiner closure.

Spec rule implemented here: accept the on-still detection only when its IoU vs the (mapped) preview quad is ≥ 0.8; otherwise keep the seed. Refinement failure must never fail the capture.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/document/DocumentStillRefinerTests.swift`:

```swift
import CoreImage
import UIKit
import XCTest
@testable import supy_scanner

final class DocumentStillRefinerTests: XCTestCase {
  private let seed = [
    CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.3),
    CGPoint(x: 0.8, y: 0.7), CGPoint(x: 0.2, y: 0.7),
  ]

  // MARK: evaluate() — pure gate logic

  func testEvaluateAcceptsCandidateAboveThreshold() {
    // Candidate = seed nudged by 0.01 → IoU well above 0.8.
    let candidate = seed.map { CGPoint(x: $0.x + 0.01, y: $0.y + 0.01) }
    let result = DocumentStillRefiner.evaluate(
      candidates: [candidate], seedQuad: seed, minIoU: 0.8)
    XCTAssertTrue(result.refined)
    XCTAssertEqual(result.quad, candidate)
  }

  func testEvaluateRejectsCandidateBelowThreshold() {
    let candidate = seed.map { CGPoint(x: $0.x + 0.4, y: $0.y) }
    let result = DocumentStillRefiner.evaluate(
      candidates: [candidate], seedQuad: seed, minIoU: 0.8)
    XCTAssertFalse(result.refined)
    XCTAssertEqual(result.quad, seed)
  }

  func testEvaluatePicksHighestIoUCandidate() {
    let close = seed.map { CGPoint(x: $0.x + 0.005, y: $0.y) }
    let closer = seed.map { CGPoint(x: $0.x + 0.001, y: $0.y) }
    let result = DocumentStillRefiner.evaluate(
      candidates: [close, closer], seedQuad: seed, minIoU: 0.8)
    XCTAssertTrue(result.refined)
    XCTAssertEqual(result.quad, closer)
  }

  func testEvaluateWithNoCandidatesFallsBackToSeed() {
    let result = DocumentStillRefiner.evaluate(
      candidates: [], seedQuad: seed, minIoU: 0.8)
    XCTAssertFalse(result.refined)
    XCTAssertEqual(result.quad, seed)
  }

  func testEvaluateWithMalformedSeedFallsBack() {
    let result = DocumentStillRefiner.evaluate(
      candidates: [seed], seedQuad: [CGPoint(x: 0.5, y: 0.5)], minIoU: 0.8)
    XCTAssertFalse(result.refined)
    XCTAssertEqual(result.quad, [CGPoint(x: 0.5, y: 0.5)])
  }

  // MARK: refine() — real Vision on a synthetic still

  func testRefineFindsSyntheticDocument() {
    // White page on a dark background at exactly `seed`'s rect.
    let still = Self.makeStill(
      size: CGSize(width: 900, height: 1200),
      pageRect: CGRect(x: 180, y: 360, width: 540, height: 480))
    // Seed slightly off the truth — refinement should snap to the page.
    let offSeed = seed.map { CGPoint(x: $0.x + 0.02, y: $0.y + 0.02) }
    let result = DocumentStillRefiner.refine(still: still, seedQuad: offSeed)
    XCTAssertTrue(result.refined)
    XCTAssertGreaterThan(QuadGeometry.iou(result.quad, seed), 0.85)
  }

  func testRefineOnBlankImageKeepsSeed() {
    let still = Self.makeStill(
      size: CGSize(width: 900, height: 1200), pageRect: nil)
    let result = DocumentStillRefiner.refine(still: still, seedQuad: seed)
    XCTAssertFalse(result.refined)
    XCTAssertEqual(result.quad, seed)
  }

  /// Draws a dark canvas with an optional white "page" rect (top-left-origin
  /// UIKit coordinates, matching the normalized quad convention).
  private static func makeStill(size: CGSize, pageRect: CGRect?) -> CIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { ctx in
      UIColor(white: 0.15, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      if let pageRect {
        UIColor.white.setFill()
        ctx.fill(pageRect)
      }
    }
    return CIImage(image: image)!
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -only-testing:supy_scanner-Unit-Tests/DocumentStillRefinerTests 2>&1 | tail -20
```

Expected: **build failure** — `cannot find 'DocumentStillRefiner' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ios/Classes/document/DocumentStillRefiner.swift`:

```swift
import CoreImage
import Vision

/// Result of on-still quad refinement.
struct DocumentStillRefinement: Equatable {
  /// Normalized [0,1], top-left origin, TL/TR/BR/BL — in the still's space.
  let quad: [CGPoint]
  /// `true` when the on-still re-detection was accepted; `false` when the
  /// seed (mapped preview quad) was kept.
  let refined: Bool
}

/// Re-runs document detection on the captured full-resolution still and keeps
/// the result only when it plausibly matches the preview-tracked quad
/// (IoU ≥ `minIoU`, spec: docs/superpowers/specs/
/// 2026-07-03-supy-document-scanner-replaces-scanbot-design.md).
/// Never fails the capture: every path returns a usable quad.
enum DocumentStillRefiner {
  static let defaultMinIoU: CGFloat = 0.8

  /// Synchronous Vision pass — call on a background queue only.
  /// `seedQuad`: the preview quad already mapped into the still's space.
  static func refine(
    still: CIImage,
    seedQuad: [CGPoint],
    minIoU: CGFloat = defaultMinIoU
  ) -> DocumentStillRefinement {
    evaluate(
      candidates: detectCandidates(still: still),
      seedQuad: seedQuad,
      minIoU: minIoU
    )
  }

  /// Pure accept/reject gate, separated from Vision for testability.
  static func evaluate(
    candidates: [[CGPoint]],
    seedQuad: [CGPoint],
    minIoU: CGFloat
  ) -> DocumentStillRefinement {
    guard seedQuad.count == 4 else {
      return DocumentStillRefinement(quad: seedQuad, refined: false)
    }
    var best: (quad: [CGPoint], iou: CGFloat)?
    for candidate in candidates where candidate.count == 4 {
      let overlap = QuadGeometry.iou(candidate, seedQuad)
      if overlap >= minIoU, overlap > (best?.iou ?? 0) {
        best = (candidate, overlap)
      }
    }
    if let best {
      return DocumentStillRefinement(quad: best.quad, refined: true)
    }
    return DocumentStillRefinement(quad: seedQuad, refined: false)
  }

  /// Top-left-origin normalized quads for every Vision observation.
  /// Same request split as `DocumentDetector`: segmentation on iOS 17+,
  /// rectangles on iOS 16.
  private static func detectCandidates(still: CIImage) -> [[CGPoint]] {
    let request: VNImageBasedRequest
    if #available(iOS 17.0, *) {
      request = VNDetectDocumentSegmentationRequest()
    } else {
      let rectangles = VNDetectRectanglesRequest()
      rectangles.maximumObservations = 3
      rectangles.minimumConfidence = 0.5
      rectangles.minimumAspectRatio = 0.35
      request = rectangles
    }
    let handler = VNImageRequestHandler(ciImage: still, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    let observations = (request.results as? [VNRectangleObservation]) ?? []
    return observations.map { obs in
      // Vision is bottom-left origin; flip to top-left once.
      [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
        .map { CGPoint(x: $0.x, y: 1 - $0.y) }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -only-testing:supy_scanner-Unit-Tests/DocumentStillRefinerTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with 7 tests passing. If `testRefineFindsSyntheticDocument` fails because simulator Vision doesn't detect the synthetic page, mirror how `ios/Tests/document/DocumentDetectorTests.swift` builds its fixture images (same renderer pattern, contrast, margins) and adjust the drawing — do not weaken the assertion.

- [ ] **Step 5: Commit**

```bash
git add ios/Classes/document/DocumentStillRefiner.swift ios/Tests/document/DocumentStillRefinerTests.swift
git commit -m "feat(ios): on-still quad re-detection gated at IoU >= 0.8 with preview fallback

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Rectify pipeline + wiring into `captureAndRectify`

**Files:**
- Create: `ios/Classes/document/DocumentRectifyPipeline.swift`
- Modify: `ios/Classes/document/DocumentDetector.swift:108-126` (quad snapshot gains analyzer size)
- Modify: `ios/Classes/document/SupyDocumentScannerView.swift:431-464` (`captureAndRectify`), the `PendingCapture` struct, and `:551-639` (`processRectifyCapture`)
- Test: `ios/Tests/document/DocumentRectifyPipelineTests.swift`

**Interfaces:**
- Consumes: `PreviewPhotoQuadMapper.mapNormalizedQuad(_:from:to:)` (Task 2), `DocumentStillRefiner.refine(still:seedQuad:minIoU:)` / `DocumentStillRefinement` (Task 3), existing `DocumentEnhancer.sharedContext: CIContext`.
- Produces:
  - `struct DocumentDetector.Detection { let quad: [CGPoint]; let analyzerSize: CGSize }` and `DocumentDetector.snapshotLatestDetection() -> Detection?` (existing `snapshotLatestQuad()` kept, now delegating).
  - `struct DocumentRectifyOutput { let image: CGImage; let quad: [CGPoint]; let quadSource: String }` (`quad` = final still-space quad actually warped; `quadSource` = `"refined"` or `"preview"`).
  - `DocumentRectifyPipeline.rectify(still:analyzerQuad:analyzerSize:context:refiner:) -> DocumentRectifyOutput?`.
  - Channel payload of `captureAndRectify` gains additive key `"quadSource": String`; `"quad"` now carries the final still-space quad. Task 5 parses `quadSource`; Task 6 documents it.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/document/DocumentRectifyPipelineTests.swift`:

```swift
import CoreImage
import UIKit
import XCTest
@testable import supy_scanner

final class DocumentRectifyPipelineTests: XCTestCase {
  // Still: 900×1200 (aspect 0.75). Analyzer: 675×1200 (aspect 0.5625).
  // mapNormalizedQuad scales x by 0.75 with offset 0.125, y unchanged —
  // so this analyzer quad lands exactly on the page drawn at
  // x [180,720], y [360,840] in the still.
  private let analyzerSize = CGSize(width: 675, height: 1200)
  private let stillSize = CGSize(width: 900, height: 1200)
  private let analyzerQuad = [
    CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.9, y: 0.3),
    CGPoint(x: 0.9, y: 0.7), CGPoint(x: 0.1, y: 0.7),
  ]
  private let expectedStillQuad = [
    CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.3),
    CGPoint(x: 0.8, y: 0.7), CGPoint(x: 0.2, y: 0.7),
  ]

  func testPreviewFallbackWarpsMappedQuad() throws {
    let still = Self.makeStill(size: stillSize)
    // Refiner stub: rejects, echoing the seed back.
    let output = DocumentRectifyPipeline.rectify(
      still: still,
      analyzerQuad: analyzerQuad,
      analyzerSize: analyzerSize,
      context: CIContext(),
      refiner: { _, seed in DocumentStillRefinement(quad: seed, refined: false) }
    )
    let result = try XCTUnwrap(output)
    XCTAssertEqual(result.quadSource, "preview")
    // Warped image ≈ the page's pixel size: (0.8−0.2)*900 × (0.7−0.3)*1200.
    XCTAssertEqual(CGFloat(result.image.width), 540, accuracy: 2)
    XCTAssertEqual(CGFloat(result.image.height), 480, accuracy: 2)
    for (got, want) in zip(result.quad, expectedStillQuad) {
      XCTAssertEqual(got.x, want.x, accuracy: 1e-6)
      XCTAssertEqual(got.y, want.y, accuracy: 1e-6)
    }
  }

  func testRefinedQuadWinsAndIsReported() throws {
    let still = Self.makeStill(size: stillSize)
    let refinedQuad = expectedStillQuad.map {
      CGPoint(x: $0.x + 0.01, y: $0.y - 0.01)
    }
    var seedSeenByRefiner: [CGPoint] = []
    let output = DocumentRectifyPipeline.rectify(
      still: still,
      analyzerQuad: analyzerQuad,
      analyzerSize: analyzerSize,
      context: CIContext(),
      refiner: { _, seed in
        seedSeenByRefiner = seed
        return DocumentStillRefinement(quad: refinedQuad, refined: true)
      }
    )
    let result = try XCTUnwrap(output)
    XCTAssertEqual(result.quadSource, "refined")
    XCTAssertEqual(result.quad, refinedQuad)
    // The refiner must be seeded with the MAPPED quad, not the analyzer quad.
    for (got, want) in zip(seedSeenByRefiner, expectedStillQuad) {
      XCTAssertEqual(got.x, want.x, accuracy: 1e-6)
      XCTAssertEqual(got.y, want.y, accuracy: 1e-6)
    }
  }

  func testOutOfBoundsMappedQuadIsClampedNotFailed() throws {
    let still = Self.makeStill(size: stillSize)
    // Analyzer quad hugging the left edge maps to x < 0 in a NARROWER dest
    // space; the pipeline must clamp into [0,1] and still produce an image.
    let edgeQuad = [
      CGPoint(x: 0.0, y: 0.1), CGPoint(x: 0.5, y: 0.1),
      CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.0, y: 0.9),
    ]
    let output = DocumentRectifyPipeline.rectify(
      still: still,
      analyzerQuad: edgeQuad,
      analyzerSize: CGSize(width: 1200, height: 1200),  // wider than still
      context: CIContext(),
      refiner: { _, seed in DocumentStillRefinement(quad: seed, refined: false) }
    )
    let result = try XCTUnwrap(output)
    for p in result.quad {
      XCTAssertGreaterThanOrEqual(p.x, 0)
      XCTAssertLessThanOrEqual(p.x, 1)
      XCTAssertGreaterThanOrEqual(p.y, 0)
      XCTAssertLessThanOrEqual(p.y, 1)
    }
    XCTAssertGreaterThan(result.image.width, 0)
  }

  func testExifRotatedStillMatchesUprightResult() throws {
    let upright = Self.makeStill(size: stillSize)
    // Physically rotate the pixels 90° CCW (the EXIF-8 display transform),
    // then tag them EXIF 6 ("rotate 90° CW to display"). The pipeline's
    // orientation guard must recover the upright image before mapping, so
    // both inputs must produce the same result.
    let tagged = upright.oriented(forExifOrientation: 8).settingProperties([
      kCGImagePropertyOrientation as String: 6
    ])
    let echoRefiner: (CIImage, [CGPoint]) -> DocumentStillRefinement = {
      _, seed in DocumentStillRefinement(quad: seed, refined: false)
    }
    let baseline = try XCTUnwrap(
      DocumentRectifyPipeline.rectify(
        still: upright, analyzerQuad: analyzerQuad, analyzerSize: analyzerSize,
        context: CIContext(), refiner: echoRefiner))
    let result = try XCTUnwrap(
      DocumentRectifyPipeline.rectify(
        still: tagged, analyzerQuad: analyzerQuad, analyzerSize: analyzerSize,
        context: CIContext(), refiner: echoRefiner))
    XCTAssertEqual(result.image.width, baseline.image.width)
    XCTAssertEqual(result.image.height, baseline.image.height)
    for (got, want) in zip(result.quad, baseline.quad) {
      XCTAssertEqual(got.x, want.x, accuracy: 1e-6)
      XCTAssertEqual(got.y, want.y, accuracy: 1e-6)
    }
  }

  private static func makeStill(size: CGSize) -> CIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { ctx in
      UIColor(white: 0.15, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      UIColor.white.setFill()
      ctx.fill(CGRect(x: 180, y: 360, width: 540, height: 480))
    }
    return CIImage(image: image)!
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -only-testing:supy_scanner-Unit-Tests/DocumentRectifyPipelineTests 2>&1 | tail -20
```

Expected: **build failure** — `cannot find 'DocumentRectifyPipeline' in scope`.

- [ ] **Step 3: Implement the pipeline**

Create `ios/Classes/document/DocumentRectifyPipeline.swift`:

```swift
import CoreImage
import ImageIO

/// Output of a rectify pass over a captured still.
struct DocumentRectifyOutput {
  /// Rectified (perspective-corrected) document image.
  let image: CGImage
  /// Final quad actually warped — normalized [0,1], top-left origin,
  /// TL/TR/BR/BL, in the still's oriented space.
  let quad: [CGPoint]
  /// "refined" when the on-still re-detection was accepted, "preview" when
  /// the mapped preview quad was used. Wire value for the `quadSource` key.
  let quadSource: String
}

/// Still-capture rectification: orients the still, maps the analyzer-space
/// quad into still space, refines it against an on-still re-detection, and
/// warps via CIPerspectiveCorrection. Pure w.r.t. Flutter — callers own
/// threading, encoding, and channel errors.
enum DocumentRectifyPipeline {
  static func rectify(
    still: CIImage,
    analyzerQuad: [CGPoint],
    analyzerSize: CGSize,
    context: CIContext,
    refiner: (CIImage, [CGPoint]) -> DocumentStillRefinement = { still, seed in
      DocumentStillRefiner.refine(still: still, seedQuad: seed)
    }
  ) -> DocumentRectifyOutput? {
    guard analyzerQuad.count == 4 else { return nil }

    // Honor EXIF orientation if the decoded still carries one, so the quad
    // (portrait, top-left origin) and the pixels agree. No-op for the
    // portrait-oriented buffers the session emits today (orientation 1).
    let exif =
      (still.properties[kCGImagePropertyOrientation as String] as? NSNumber)?
        .int32Value ?? 1
    let oriented = exif == 1 ? still : still.oriented(forExifOrientation: exif)
    let stillSize = oriented.extent.size
    guard stillSize.width > 0, stillSize.height > 0 else { return nil }

    // 1. Analyzer space → still space (centered-crop FOV model), clamped so
    //    edge-hugging quads never leave the image.
    let mapped = PreviewPhotoQuadMapper.mapNormalizedQuad(
      analyzerQuad, from: analyzerSize, to: stillSize
    ).map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }

    // 2. On-still refinement. Falls back to `mapped` internally — a capture
    //    never fails because refinement failed.
    let refinement = refiner(oriented, mapped)
    let quad = refinement.quad
    guard quad.count == 4 else { return nil }

    // 3. Warp. Quad is top-left-origin; CIImage is bottom-left — flip Y once.
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
      return nil
    }
    let w = stillSize.width
    let h = stillSize.height
    let tl = CGPoint(x: quad[0].x * w, y: (1 - quad[0].y) * h)
    let tr = CGPoint(x: quad[1].x * w, y: (1 - quad[1].y) * h)
    let br = CGPoint(x: quad[2].x * w, y: (1 - quad[2].y) * h)
    let bl = CGPoint(x: quad[3].x * w, y: (1 - quad[3].y) * h)
    filter.setValue(oriented, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")
    filter.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")
    guard let outCI = filter.outputImage,
          let cg = context.createCGImage(outCI, from: outCI.extent)
    else { return nil }

    return DocumentRectifyOutput(
      image: cg,
      quad: quad,
      quadSource: refinement.refined ? "refined" : "preview"
    )
  }
}
```

- [ ] **Step 4: Run pipeline tests to verify they pass**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' -only-testing:supy_scanner-Unit-Tests/DocumentRectifyPipelineTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with 4 tests passing.

- [ ] **Step 5: Extend `DocumentDetector`'s snapshot with the analyzer size**

In `ios/Classes/document/DocumentDetector.swift`, replace lines 108–126 (the lock's doc comment through `setLatestQuad` — the old comment at 108–110 is superseded by the block below) with:

```swift
  /// Lock guarding `_latestQuad`/`_latestAnalyzerSize`. The detector itself
  /// only writes from `sampleBufferQueue`, but `captureAndRectify` reads from
  /// the session queue, so we need a tiny mutex.
  private let latestQuadLock = NSLock()
  private var _latestQuad: [CGPoint] = []
  private var _latestAnalyzerSize: CGSize = .zero

  /// A quad snapshot paired with the oriented (portrait) pixel size of the
  /// analyzer buffer it was detected in — required to map the quad into the
  /// differently-aspected still-photo space.
  struct Detection {
    let quad: [CGPoint]
    let analyzerSize: CGSize
  }

  /// Returns the most recent top-left-origin normalized quad accepted by the
  /// detector, or an empty array if there's no current detection. Thread-safe.
  func snapshotLatestQuad() -> [CGPoint] {
    snapshotLatestDetection()?.quad ?? []
  }

  /// Like `snapshotLatestQuad()` but paired with the analyzer's oriented
  /// buffer size. `nil` when there's no current detection. Thread-safe.
  func snapshotLatestDetection() -> Detection? {
    latestQuadLock.lock()
    defer { latestQuadLock.unlock() }
    guard _latestQuad.count == 4 else { return nil }
    return Detection(quad: _latestQuad, analyzerSize: _latestAnalyzerSize)
  }

  private func setLatestQuad(_ quad: [CGPoint], analyzerSize: CGSize) {
    latestQuadLock.lock()
    _latestQuad = quad
    _latestAnalyzerSize = analyzerSize
    latestQuadLock.unlock()
  }
```

Then fix the two `setLatestQuad` call sites (search `setLatestQuad(` in the same file):

- Line 296 — `self.setLatestQuad(metrics.quad)` inside the detection completion closure. This single site covers both accept and no-document: `metrics.quad` is `[]` when the quad was rejected (the comment above it says so), and `snapshotLatestDetection()` returns `nil` unless the stored quad has 4 points, so passing the size unconditionally is safe. Vision runs with `orientation: .right` (line ~224), so the normalized quad lives in the rotated portrait space and the oriented size swaps the buffer's axes. `pixelBuffer` is in scope from the enclosing sample-buffer method and is captured by the closure:

```swift
      let orientedSize = CGSize(
        width: CGFloat(CVPixelBufferGetHeight(pixelBuffer)),
        height: CGFloat(CVPixelBufferGetWidth(pixelBuffer))
      )
      self.setLatestQuad(metrics.quad, analyzerSize: orientedSize)
```

- Line 308 — `setLatestQuad([])` in the Vision-error `catch`:

```swift
      setLatestQuad([], analyzerSize: .zero)
```

- [ ] **Step 6: Wire the pipeline into `SupyDocumentScannerView`**

Three edits in `ios/Classes/document/SupyDocumentScannerView.swift`:

**(a)** Find the `PendingCapture` struct (holds `result`, `quad`, `jpegQuality`) and add one field after `quad`:

```swift
  /// Oriented analyzer size paired with `quad`; `nil` for full-frame captures.
  let analyzerSize: CGSize?
```

**(b)** Replace `captureAndRectify` (lines 431–464) so it snapshots the paired detection and threads the size through:

```swift
  private func captureAndRectify(jpegQuality: CGFloat, result: @escaping FlutterResult) {
    guard let detection = detector.snapshotLatestDetection() else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureUnsupported",
            message: "No quad detected",
            details: nil
          )
        )
      }
      return
    }
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let settings = self.makePhotoSettings()
      self.pendingCaptures[settings.uniqueID] = PendingCapture(
        result: result,
        quad: detection.quad,
        analyzerSize: detection.analyzerSize,
        jpegQuality: jpegQuality
      )
      let delegate = PhotoCaptureDelegate(owner: self)
      // Retain the delegate until the callback fires — AVFoundation only
      // holds a weak ref.
      objc_setAssociatedObject(
        settings,
        &PhotoCaptureDelegate.assocKey,
        delegate,
        .OBJC_ASSOCIATION_RETAIN
      )
      self.photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
  }
```

In `captureFullFrame` (lines 466–484), update its `PendingCapture(...)` construction to pass `analyzerSize: nil` (and keep `quad: nil`). In `finishPhotoCapture` (lines 538–547), pass the size through to the rectify branch:

```swift
        if let quad = pending.quad {
          self.processRectifyCapture(
            data: data,
            quad: quad,
            analyzerSize: pending.analyzerSize ?? .zero,
            jpegQuality: pending.jpegQuality,
            result: pending.result)
        } else {
          self.processFullFrameCapture(
            data: data, jpegQuality: pending.jpegQuality, result: pending.result)
        }
```

**(c)** Replace `processRectifyCapture` (lines 551–639) with the pipeline-backed version. JPEG encoding, temp-file write, error codes, and legacy payload keys are unchanged; the quad math moves into `DocumentRectifyPipeline`:

```swift
  private func processRectifyCapture(
    data: Data,
    quad: [CGPoint],
    analyzerSize: CGSize,
    jpegQuality: CGFloat,
    result: @escaping FlutterResult
  ) {
    guard let ciImage = CIImage(data: data) else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not decode captured still",
            details: nil
          )
        )
      }
      return
    }
    // Maps the analyzer-space quad into still space, refines it against an
    // on-still re-detection (IoU ≥ 0.8, preview fallback), and warps.
    guard let output = DocumentRectifyPipeline.rectify(
      still: ciImage,
      analyzerQuad: quad,
      analyzerSize: analyzerSize,
      context: DocumentEnhancer.sharedContext
    ) else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not render rectified image",
            details: nil
          )
        )
      }
      return
    }
    let uiImage = UIImage(cgImage: output.image)
    guard let jpeg = uiImage.jpegData(compressionQuality: jpegQuality) else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not encode rectified JPEG",
            details: nil
          )
        )
      }
      return
    }
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("supy-doc-\(UUID().uuidString).jpg")
    do {
      try jpeg.write(to: url, options: .atomic)
    } catch {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not write JPEG: \(error.localizedDescription)",
            details: nil
          )
        )
      }
      return
    }
    let payload: [String: Any] = [
      "path": url.path,
      "widthPx": output.image.width,
      "heightPx": output.image.height,
      // Final still-space quad actually used for the warp (was: raw
      // analyzer-space quad). Same convention — normalized, top-left origin.
      "quad": output.quad.map { ["x": Double($0.x), "y": Double($0.y)] },
      // Additive: "refined" (on-still re-detection accepted) | "preview".
      "quadSource": output.quadSource,
      // Legacy keys for existing `SupyDocumentPage.fromMap` consumers
      // (`controller.capture()`). Additive — never remove.
      "uri": "file://\(url.path)",
      "width": output.image.width,
      "height": output.image.height,
    ]
    DispatchQueue.main.async { result(payload) }
  }
```

- [ ] **Step 7: Run the full iOS document test suite**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` — all pre-existing suites (DocumentDetectorTests, DocumentEnhancerTests, SupyGuidanceClassifierTests, …) plus the three new ones pass. `DocumentDetectorTests` must pass unmodified — `snapshotLatestQuad()` behavior is preserved.

- [ ] **Step 8: Commit**

```bash
git add ios/Classes/document/DocumentRectifyPipeline.swift ios/Tests/document/DocumentRectifyPipelineTests.swift ios/Classes/document/DocumentDetector.swift ios/Classes/document/SupyDocumentScannerView.swift
git commit -m "feat(ios): aspect-map + refine still-capture quads in captureAndRectify

captureAndRectify previously applied the analyzer-stream quad directly to
the still, mis-cropping whenever the analyzer and photo aspect ratios
differ. The new DocumentRectifyPipeline maps the quad through the shared
FOV model, re-detects on the still (accepting at IoU >= 0.8, falling back
to the mapped preview quad), and reports the outcome via the additive
quadSource payload key.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Dart — `quadSource` on `SupyDocumentCapture`

**Files:**
- Modify: `lib/src/widgets/supy_document_scanner_controller.dart:14-86` (`SupyDocumentCapture`)
- Test: `test/widgets/supy_document_scanner_controller_test.dart`

**Interfaces:**
- Consumes: the `"quadSource"` payload key produced by Task 4 (`"refined" | "preview"`, absent on Android and full-frame captures).
- Produces: `SupyDocumentCapture.quadSource: String?` — read by Sprint-4's bench harness to measure refinement rate. Additive: existing positional/named usage of the class keeps compiling.

- [ ] **Step 1: Write the failing test**

Append to the top-level `main()` groups in `test/widgets/supy_document_scanner_controller_test.dart` (match the file's existing group style):

```dart
  group('SupyDocumentCapture.quadSource', () {
    test('parses quadSource when present', () {
      final capture = SupyDocumentCapture.fromMap(const <Object?, Object?>{
        'path': '/tmp/a.jpg',
        'widthPx': 100,
        'heightPx': 200,
        'quadSource': 'refined',
      });
      expect(capture.quadSource, 'refined');
    });

    test('quadSource is null when absent (Android / full-frame)', () {
      final capture = SupyDocumentCapture.fromMap(const <Object?, Object?>{
        'path': '/tmp/a.jpg',
        'widthPx': 100,
        'heightPx': 200,
      });
      expect(capture.quadSource, isNull);
    });

    test('quadSource participates in equality', () {
      const a = SupyDocumentCapture(
        path: '/tmp/a.jpg',
        widthPx: 1,
        heightPx: 1,
        quadSource: 'refined',
      );
      const b = SupyDocumentCapture(
        path: '/tmp/a.jpg',
        widthPx: 1,
        heightPx: 1,
        quadSource: 'preview',
      );
      const c = SupyDocumentCapture(
        path: '/tmp/a.jpg',
        widthPx: 1,
        heightPx: 1,
        quadSource: 'refined',
      );
      expect(a, isNot(equals(b)));
      expect(a, equals(c));
      expect(a.hashCode, c.hashCode);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/widgets/supy_document_scanner_controller_test.dart --reporter expanded
```

Expected: FAIL — compile error `No named parameter with the name 'quadSource'`.

- [ ] **Step 3: Implement**

In `lib/src/widgets/supy_document_scanner_controller.dart`, make these five additive edits to `SupyDocumentCapture`:

Constructor (line 17-22):

```dart
  const SupyDocumentCapture({
    required this.path,
    required this.widthPx,
    required this.heightPx,
    this.quad = const <Offset>[],
    this.quadSource,
  });
```

`fromMap` return (line 42-47):

```dart
    return SupyDocumentCapture(
      path: map['path']! as String,
      widthPx: (map['widthPx']! as num).toInt(),
      heightPx: (map['heightPx']! as num).toInt(),
      quad: List<Offset>.unmodifiable(quad),
      quadSource: map['quadSource'] as String?,
    );
```

Field (after the `quad` field, line 61):

```dart
  /// How the rectification quad was obtained on iOS: `'refined'` when the
  /// on-still re-detection was accepted, `'preview'` when the mapped preview
  /// quad was used. `null` on platforms/paths that don't report it.
  final String? quadSource;
```

`operator ==` (lines 63-70):

```dart
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentCapture &&
          other.path == path &&
          other.widthPx == widthPx &&
          other.heightPx == heightPx &&
          other.quadSource == quadSource &&
          _quadsEqual(other.quad, quad);
```

`hashCode` and `toString` (lines 72-77):

```dart
  @override
  int get hashCode =>
      Object.hash(path, widthPx, heightPx, quadSource, Object.hashAll(quad));

  @override
  String toString() =>
      'SupyDocumentCapture(path: $path, ${widthPx}x$heightPx, quad: $quad, '
      'quadSource: $quadSource)';
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/widgets/supy_document_scanner_controller_test.dart --reporter expanded && flutter analyze lib test
```

Expected: all tests PASS (new group + all pre-existing controller tests), `No issues found!` from analyze.

- [ ] **Step 5: Commit**

```bash
git add lib/src/widgets/supy_document_scanner_controller.dart test/widgets/supy_document_scanner_controller_test.dart
git commit -m "feat(dart): surface quadSource on SupyDocumentCapture

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Documentation — channel table, changelog, decisions, QA scenario

**Files:**
- Modify: `docs/ARCHITECTURE.md` (per-view `captureAndRectify` row)
- Modify: `CHANGELOG.md` (`## [Unreleased]`)
- Modify: `TODO.md` (new `## Decisions` section + Phase CSU checklist)
- Modify: `docs/QA.md` (new D-series scenario)

**Interfaces:**
- Consumes: the `quadSource` wire key (Task 4) and the amended spec `docs/superpowers/specs/2026-07-03-supy-document-scanner-replaces-scanbot-design.md`.
- Produces: the `TODO.md` decisions section that CLAUDE.md's compat rule refers to — Sprint 2's plan appends to it.

- [ ] **Step 1: Update the channel table in `docs/ARCHITECTURE.md`**

Find the per-view document method table row for `captureAndRectify` (columns `| Method | Args | Returns | Errors |`). Update its **Returns** cell to include the new key and quad semantics, keeping the cell's existing entries:

```
`{path, widthPx, heightPx, quad, quadSource, uri, width, height}` — `quad` is the final still-space quad used for the warp (normalized, top-left origin); `quadSource` is `refined` (on-still re-detection accepted at IoU ≥ 0.8) or `preview` (mapped preview-quad fallback). iOS emits `quadSource`; Android does not yet (Sprint 3).
```

- [ ] **Step 2: Update `CHANGELOG.md`**

Under `## [Unreleased]`, add to the existing `### Added` and `### Fixed` sections (create a section only if it doesn't exist, matching the file's heading style):

```markdown
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
```

- [ ] **Step 3: Create the decisions section + Phase CSU checklist in `TODO.md`**

Append at the end of `TODO.md`:

```markdown
## Decisions

- **2026-07-03 — Supy scanner becomes the default document backend (Phase CSU).**
  Spec: `docs/superpowers/specs/2026-07-03-supy-document-scanner-replaces-scanbot-design.md`.
  System modals (GMS/VisionKit) stay reachable via the existing
  `preferredBackend` values `gms`/`cameraX` as the kill-switch; a new additive
  `supy` backend value lands in Sprint 2. Scanbot-compat call sites are
  unchanged (additive-only surface).
- **2026-07-03 — No `navigatorKey`; route via the caller's `BuildContext`.**
  `SupyDocumentScanner.startMultiPage()` already receives a `BuildContext`, so
  the supy screen is pushed with `Navigator.maybeOf(context)`; if no navigator
  is reachable we warn once and fall back to the system backend. Zero retailer
  integration steps.
- **2026-07-03 — `captureAndRectify` quad semantics.** The `quad` payload key
  now carries the final still-space quad actually warped (previously the raw
  analyzer-space quad); additive `quadSource` reports `refined`/`preview`.
  Same normalized top-left-origin convention; consumers unaffected.

## Phase CSU — Supy scanner replaces Scanbot

Spec: `docs/superpowers/specs/2026-07-03-supy-document-scanner-replaces-scanbot-design.md`

### Sprint 1 — iOS capture completion (plan: `docs/superpowers/plans/2026-07-03-csu-sprint1-ios-capture-completion.md`)
- [x] CSU-S1-01 `QuadGeometry` convex-quad IoU + tests
- [x] CSU-S1-02 `PreviewPhotoQuadMapper` analyzer→still aspect mapping + tests
- [x] CSU-S1-03 `DocumentStillRefiner` on-still re-detection (IoU ≥ 0.8 gate, preview fallback) + tests
- [x] CSU-S1-04 `DocumentRectifyPipeline` wired into `captureAndRectify`; additive `quadSource` payload key
- [x] CSU-S1-05 `SupyDocumentCapture.quadSource` Dart passthrough + tests
- [x] CSU-S1-06 Docs: ARCHITECTURE channel row, CHANGELOG, decisions log, QA scenario

### Sprint 2 — Dart scanner screen (plan at sprint boundary)
- [ ] CSU-S2 `SupyDocumentScannerScreen`, `startMultiPage` BuildContext routing, minimal review UI, additive `supy` backend value, system fallback, `docs/MIGRATION.md` + `docs/PLAN.md` phase docs

### Sprint 3 — Android parity (plan at sprint boundary)
- [ ] CSU-S3 C++ guidance on embedded view, seeded still refinement, `filter` native mapping, GMS kill-switch

### Sprint 4 — Proof & Scanbot removal (plan at sprint boundary)
- [ ] CSU-S4 Side-by-side bench vs Scanbot, QA walkthrough, retailer pilot, Scanbot removal
```

(Check the boxes only for tasks already committed when this step runs; leave any not-yet-landed item unchecked.)

- [ ] **Step 4: Add the QA scenario to `docs/QA.md`**

Append to the D-series (use the next free D number — written as `D<n>` below), matching the existing `### D1 — Single-page receipt` heading + numbered-steps format:

```markdown
### D<n> — Embedded capture: on-still quad refinement (iOS)

Covers Phase CSU Sprint 1: `captureAndRectify` aspect mapping + on-still refinement.

1. Open the example app → "Smart Document" on an iPhone (not simulator).
2. Frame an A4/receipt on a contrasting background; wait for the ready state.
3. Trigger capture. Verify the rectified output's edges hug the document —
   no sliver of background band on the left/right (the pre-fix symptom of the
   16:9→4:3 mis-crop) and no clipped document edge.
4. Repeat with the document deliberately ~15° tilted and slightly off-center:
   the output must still be a clean top-down crop.
5. Repeat with the document half out of frame at capture time: capture must
   still succeed (never error because refinement failed) and return a usable
   crop of the visible region.
6. Debug-verify `SupyDocumentCapture.quadSource`: mostly `refined` in
   scenarios 3–4; `preview` is acceptable in scenario 5.
```

- [ ] **Step 5: Verify docs and commit**

```bash
grep -n "quadSource" docs/ARCHITECTURE.md CHANGELOG.md TODO.md docs/QA.md
```

Expected: at least one hit in each of the four files.

```bash
git add docs/ARCHITECTURE.md CHANGELOG.md TODO.md docs/QA.md
git commit -m "docs: record CSU sprint-1 capture refinement (channel row, changelog, decisions, QA)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Sprint verification sweep

**Files:** none created — verification only.

**Interfaces:**
- Consumes: everything above.
- Produces: green suites proving Sprint 1 is done; the go signal for writing the Sprint 2 plan.

- [ ] **Step 1: Full Dart suite**

```bash
flutter analyze lib test && flutter test --reporter expanded --coverage
```

Expected: `No issues found!`; every test passes (pre-existing suites unaffected).

- [ ] **Step 2: Full iOS native suite**

```bash
cd example/ios && pod install && xcodebuild test -workspace Runner.xcworkspace -scheme supy_scanner-Unit-Tests -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Confirm nothing outside sprint scope was staged**

```bash
git log --oneline --stat d427fd2..HEAD
```

Expected: only the files named in Tasks 1–6. If anything else appears, stop and surface it.

- [ ] **Step 4: Device QA note**

The new `docs/QA.md` D-scenario needs a physical iPhone; it is **not** a blocker for merging Sprint 1's commits, but it is the WS1 exit gate before Sprint 2's plan is executed. Record the result in the PR/session notes.
