import XCTest

@testable import supy_scanner

final class SupyDeviceTierTests: XCTestCase {

  func testHighLeavesEveryAnalyzerDialUncapped() {
    XCTAssertNil(SupyDeviceTier.high.barcodeAnalyzerSize)
    XCTAssertNil(SupyDeviceTier.high.analyzerFpsCap)
    XCTAssertNil(SupyDeviceTier.high.idlePauseThresholdMs)
    XCTAssertNil(SupyDeviceTier.high.ocrLongEdgeCap)
  }

  /// Unlike the barcode `analyzerFpsCap` (HIGH = uncapped), the document
  /// detector is capped on every tier — the Vision segmentation model is heavy
  /// enough that even flagships benefit, and edge guidance needs no more than
  /// ~20 FPS. Caps must descend high ≥ mid ≥ low.
  func testDocumentDetectorFpsCapPerTier() {
    XCTAssertEqual(SupyDeviceTier.high.documentDetectorFpsCap, 20)
    XCTAssertEqual(SupyDeviceTier.mid.documentDetectorFpsCap, 15)
    XCTAssertEqual(SupyDeviceTier.low.documentDetectorFpsCap, 12)
    XCTAssertGreaterThanOrEqual(
      SupyDeviceTier.high.documentDetectorFpsCap,
      SupyDeviceTier.mid.documentDetectorFpsCap)
    XCTAssertGreaterThanOrEqual(
      SupyDeviceTier.mid.documentDetectorFpsCap,
      SupyDeviceTier.low.documentDetectorFpsCap)
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

  func testLowCapsJpegQualityAtPointEightEightButDoesNotRaiseLowerRequests() {
    XCTAssertEqual(SupyDeviceTier.low.jpegQuality(requested: 0.95), 0.88)
    XCTAssertEqual(SupyDeviceTier.low.jpegQuality(requested: 0.60), 0.60)
    XCTAssertEqual(SupyDeviceTier.low.jpegQuality(requested: 0.88), 0.88)
  }
}
