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
