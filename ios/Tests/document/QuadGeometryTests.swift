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
