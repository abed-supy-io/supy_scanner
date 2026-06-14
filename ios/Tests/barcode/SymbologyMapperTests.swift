import Vision
import XCTest

@testable import supy_scanner

final class SymbologyMapperTests: XCTestCase {

  func testEmptyListReturnsNilSoVisionFallsBackToAllFormats() {
    XCTAssertNil(SymbologyMapper.toVisionSymbologies([]))
  }

  func testAllSentinelReturnsNilSoVisionFallsBackToAllFormats() {
    XCTAssertNil(SymbologyMapper.toVisionSymbologies(["all"]))
  }

  func testAllSentinelWinsEvenWhenCombinedWithExplicitFormats() {
    XCTAssertNil(SymbologyMapper.toVisionSymbologies(["qr", "all", "ean13"]))
  }

  func testUnknownWireNamesAreFilteredOut() {
    let result = SymbologyMapper.toVisionSymbologies(["qr", "bogus"])
    XCTAssertEqual(result, [.qr])
  }

  func testAllUnknownListReturnsNilRatherThanEmptyArray() {
    XCTAssertNil(SymbologyMapper.toVisionSymbologies(["bogus", "nope"]))
  }

  func testEveryKnownWireNameMapsToTheExpectedVisionSymbologies() {
    let cases: [(String, [VNBarcodeSymbology])] = [
      ("qr", [.qr]),
      ("ean13", [.ean13]),
      ("ean8", [.ean8]),
      ("upcA", [.ean13]),       // Vision returns UPC-A as EAN-13 with a leading 0
      ("upcE", [.upce]),
      ("code39", [.code39]),
      ("code93", [.code93]),
      ("code128", [.code128]),
      ("itf", [.i2of5, .itf14]),
      ("pdf417", [.pdf417]),
      ("dataMatrix", [.dataMatrix]),
      ("aztec", [.aztec]),
      ("codabar", [.codabar]),
    ]
    for (wire, expected) in cases {
      XCTAssertEqual(SymbologyMapper.toVisionSymbologies([wire]), expected, "wire=\(wire)")
    }
  }

  func testVisionToWireDisambiguatesUpcAFromEan13ByLeadingZero() {
    XCTAssertEqual(SymbologyMapper.visionToWire(.ean13, payload: "0123456789012"), "upcA")
    XCTAssertEqual(SymbologyMapper.visionToWire(.ean13, payload: "1234567890123"), "ean13")
    XCTAssertEqual(SymbologyMapper.visionToWire(.ean13, payload: nil), "ean13")
    XCTAssertEqual(SymbologyMapper.visionToWire(.ean13, payload: "012345"), "ean13")
  }

  func testVisionToWireMapsItfDualSymbologiesToASingleWireName() {
    XCTAssertEqual(SymbologyMapper.visionToWire(.i2of5, payload: nil), "itf")
    XCTAssertEqual(SymbologyMapper.visionToWire(.itf14, payload: nil), "itf")
  }

  func testVisionToWireForKnownSymbologies() {
    let cases: [(VNBarcodeSymbology, String)] = [
      (.qr, "qr"),
      (.ean8, "ean8"),
      (.upce, "upcE"),
      (.code39, "code39"),
      (.code93, "code93"),
      (.code128, "code128"),
      (.pdf417, "pdf417"),
      (.dataMatrix, "dataMatrix"),
      (.aztec, "aztec"),
      (.codabar, "codabar"),
    ]
    for (symbology, expected) in cases {
      XCTAssertEqual(SymbologyMapper.visionToWire(symbology, payload: nil), expected)
    }
  }
}
