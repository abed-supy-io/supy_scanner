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

  func testEvaluateAcceptsOffsetSameSizeCandidateViaContainment() {
    // Seed is offset ~13% in x from the true page (preview→photo FOV error).
    // Symmetric IoU falls below 0.8, but the two quads outline the same page,
    // so containment keeps it and the correct (offset) detection wins.
    let candidate = seed.map { CGPoint(x: $0.x - 0.08, y: $0.y) }
    XCTAssertLessThan(QuadGeometry.iou(candidate, seed), 0.8)
    let result = DocumentStillRefiner.evaluate(
      candidates: [candidate], seedQuad: seed, minIoU: 0.8)
    XCTAssertTrue(result.refined)
    XCTAssertEqual(result.quad, candidate)
  }

  func testEvaluateRejectsSmallInnerRectangle() {
    // A small rectangle fully inside the seed (e.g. a printed table) has
    // containment 1.0 but is far too small — the area band must reject it so
    // the crop never snaps onto sub-content.
    let inner = [
      CGPoint(x: 0.45, y: 0.45), CGPoint(x: 0.55, y: 0.45),
      CGPoint(x: 0.55, y: 0.55), CGPoint(x: 0.45, y: 0.55),
    ]
    let result = DocumentStillRefiner.evaluate(
      candidates: [inner], seedQuad: seed, minIoU: 0.8)
    XCTAssertFalse(result.refined)
    XCTAssertEqual(result.quad, seed)
  }

  func testEvaluateRejectsFullFrameBackgroundRectangle() {
    // Regression: on device a ~0.51-area seed was snapped to the full frame.
    // A background rectangle covering the whole image contains the seed
    // (containment ~1.0) but is ~2× its area — the area band must veto it so
    // the crop keeps the framed page instead of the whole image.
    let halfFrameSeed = [
      CGPoint(x: 0.15, y: 0.135), CGPoint(x: 0.85, y: 0.135),
      CGPoint(x: 0.85, y: 0.865), CGPoint(x: 0.15, y: 0.865),
    ]
    let fullFrame = [
      CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
      CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
    ]
    // Same shape the on-device failure had: low IoU, containment ~1, ratio ~2.
    XCTAssertLessThan(QuadGeometry.iou(fullFrame, halfFrameSeed), 0.8)
    let result = DocumentStillRefiner.evaluate(
      candidates: [fullFrame], seedQuad: halfFrameSeed, minIoU: 0.8)
    XCTAssertFalse(result.refined)
    XCTAssertEqual(result.quad, halfFrameSeed)
  }

  func testEvaluateStillRejectsDisjointCandidate() {
    // A candidate that barely overlaps the seed is a different object — both
    // IoU and containment stay low, so it is rejected (no regression of the
    // wrong-object guard).
    let candidate = seed.map { CGPoint(x: $0.x + 0.5, y: $0.y) }
    let result = DocumentStillRefiner.evaluate(
      candidates: [candidate], seedQuad: seed, minIoU: 0.8)
    XCTAssertFalse(result.refined)
    XCTAssertEqual(result.quad, seed)
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

  /// Draws a near-black canvas with an optional white "page" rect (top-left-origin
  /// UIKit coordinates, matching the normalized quad convention).
  private static func makeStill(size: CGSize, pageRect: CGRect?) -> CIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { ctx in
      // Near-black background for strong edge contrast.
      UIColor(white: 0.05, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      if let pageRect {
        UIColor.white.setFill()
        ctx.fill(pageRect)
      }
    }
    return CIImage(image: image)!
  }
}
