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

  func testNonFourPointRefinerQuadFallsBackToPreview() throws {
    let still = Self.makeStill(size: stillSize)
    // Defensive path: a refiner that reports refined but hands back a
    // degenerate (non-4-point) quad must NOT fail the capture — the pipeline
    // falls back to the mapped preview quad and reports "preview".
    let output = DocumentRectifyPipeline.rectify(
      still: still,
      analyzerQuad: analyzerQuad,
      analyzerSize: analyzerSize,
      context: CIContext(),
      refiner: { _, _ in DocumentStillRefinement(quad: [], refined: true) }
    )
    let result = try XCTUnwrap(output)
    XCTAssertEqual(result.quadSource, "preview")
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
