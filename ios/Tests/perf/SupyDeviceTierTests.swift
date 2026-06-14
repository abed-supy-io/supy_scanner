import XCTest

@testable import supy_scanner

final class SupyDeviceTierTests: XCTestCase {

  func testHighLeavesEveryAnalyzerDialUncapped() {
    XCTAssertNil(SupyDeviceTier.high.barcodeAnalyzerSize)
    XCTAssertNil(SupyDeviceTier.high.analyzerFpsCap)
    XCTAssertNil(SupyDeviceTier.high.idlePauseThresholdMs)
    XCTAssertNil(SupyDeviceTier.high.ocrLongEdgeCap)
  }

  func testMidDialsMatchPerformanceDocsPolicyTable() {
    let size = SupyDeviceTier.mid.barcodeAnalyzerSize
    XCTAssertEqual(size?.width, 960)
    XCTAssertEqual(size?.height, 720)
    XCTAssertEqual(SupyDeviceTier.mid.analyzerFpsCap, 24)
    XCTAssertEqual(SupyDeviceTier.mid.idlePauseThresholdMs, 8_000)
    XCTAssertEqual(SupyDeviceTier.mid.ocrLongEdgeCap, 1600)
  }

  func testLowDialsMatchPerformanceDocsPolicyTable() {
    let size = SupyDeviceTier.low.barcodeAnalyzerSize
    XCTAssertEqual(size?.width, 640)
    XCTAssertEqual(size?.height, 480)
    XCTAssertEqual(SupyDeviceTier.low.analyzerFpsCap, 20)
    XCTAssertEqual(SupyDeviceTier.low.idlePauseThresholdMs, 4_000)
    XCTAssertEqual(SupyDeviceTier.low.ocrLongEdgeCap, 1280)
  }

  func testHighAndMidPassRequestedJpegQualityThroughUnchanged() {
    XCTAssertEqual(SupyDeviceTier.high.jpegQuality(requested: 0.95), 0.95)
    XCTAssertEqual(SupyDeviceTier.mid.jpegQuality(requested: 0.95), 0.95)
  }

  func testLowCapsJpegQualityAtPointSevenFiveButDoesNotRaiseLowerRequests() {
    XCTAssertEqual(SupyDeviceTier.low.jpegQuality(requested: 0.95), 0.75)
    XCTAssertEqual(SupyDeviceTier.low.jpegQuality(requested: 0.60), 0.60)
    XCTAssertEqual(SupyDeviceTier.low.jpegQuality(requested: 0.75), 0.75)
  }
}
