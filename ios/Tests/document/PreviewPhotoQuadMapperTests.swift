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
