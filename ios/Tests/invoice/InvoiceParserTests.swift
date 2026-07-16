import CoreGraphics
import XCTest

@testable import supy_scanner

/// Pure-logic tests for `InvoiceParser.extractFields(from:)` — Phase IXP.
///
/// These drive the heuristic field extractor with synthetic `Line` fixtures
/// in image-pixel coordinates (origin top-left). No Vision, no UIImage, no
/// VisionKit — the parser must be deterministic on a fixed line layout.
final class InvoiceParserTests: XCTestCase {

  // MARK: - Helpers

  private typealias Line = InvoiceParser.Line

  /// Builds a line at row `row` (each row is `rowHeight` tall, starting at
  /// `y0`) with a given X column. Image-pixel coords, top-left origin.
  private func line(
    _ text: String,
    row: Int,
    x: CGFloat = 40,
    width: CGFloat = 200,
    rowHeight: CGFloat = 24,
    y0: CGFloat = 40
  ) -> Line {
    let y = y0 + CGFloat(row) * rowHeight * 1.4
    return Line(text: text, frame: CGRect(x: x, y: y, width: width, height: rowHeight))
  }

  // MARK: - parseAmount

  func testParseAmountHandlesUsAndEuFormats() {
    XCTAssertEqual(InvoiceParser.parseAmount("1,234.56") ?? 0, 1234.56, accuracy: 0.001)
    XCTAssertEqual(InvoiceParser.parseAmount("1.234,56") ?? 0, 1234.56, accuracy: 0.001)
    XCTAssertEqual(InvoiceParser.parseAmount("42") ?? 0, 42, accuracy: 0.001)
    XCTAssertEqual(InvoiceParser.parseAmount("0.99") ?? 0, 0.99, accuracy: 0.001)
    XCTAssertNil(InvoiceParser.parseAmount("not a number"))
    XCTAssertNil(InvoiceParser.parseAmount(""))
  }

  // MARK: - Vendor

  func testVendorPicksLargestLineInTopBand() {
    // "ACME COFFEE" is the largest line near the top — should win over the
    // smaller address line directly below it.
    let lines: [Line] = [
      Line(text: "ACME COFFEE", frame: CGRect(x: 50, y: 40, width: 300, height: 48)),
      Line(text: "123 Main St", frame: CGRect(x: 50, y: 110, width: 200, height: 18)),
      line("Subtotal 10.00", row: 8),
      line("Total 12.50", row: 9),
    ]
    let out = InvoiceParser.extractFields(from: lines)
    XCTAssertEqual(out["vendor"] as? String, "ACME COFFEE")
  }

  // MARK: - Date

  func testDateMatchesIsoSlashAndTextual() {
    for fixture in ["2026-06-17", "17/06/2026", "17 Jun 2026", "Jun 17, 2026"] {
      let lines: [Line] = [
        line("ACME", row: 0),
        line("Date: \(fixture)", row: 1),
        line("Total 9.99", row: 5),
      ]
      let out = InvoiceParser.extractFields(from: lines)
      XCTAssertEqual(out["date"] as? String, fixture, "failed for \(fixture)")
    }
  }

  // MARK: - Total / Tax

  func testTotalAndTaxExtractedSeparately() {
    let lines: [Line] = [
      line("ACME COFFEE", row: 0),
      line("Subtotal 10.00", row: 5),
      line("VAT 5%", row: 6),
      line("Tax 0.50", row: 7),
      line("TOTAL 10.50", row: 8),
    ]
    let out = InvoiceParser.extractFields(from: lines)
    XCTAssertEqual(out["total"] as? Double ?? 0, 10.50, accuracy: 0.001)
    XCTAssertEqual(out["tax"] as? Double ?? 0, 0.50, accuracy: 0.001)
  }

  func testTaxPercentDoesNotPolluteTaxAmount() {
    // "VAT 5%" is a rate, not an amount — the extractor must skip it and
    // not return `5` as the tax field.
    let lines: [Line] = [
      line("ACME", row: 0),
      line("Subtotal 100.00", row: 5),
      line("VAT 5%", row: 6),
      line("TOTAL 105.00", row: 7),
    ]
    let out = InvoiceParser.extractFields(from: lines)
    XCTAssertEqual(out["total"] as? Double ?? 0, 105.0, accuracy: 0.001)
    XCTAssertNil(out["tax"])
  }

  // MARK: - Currency

  func testCurrencyDetectedFromSymbolOrIsoCode() {
    let withSymbol: [Line] = [
      line("ACME", row: 0),
      line("Total $42.00", row: 5),
    ]
    XCTAssertEqual(InvoiceParser.extractFields(from: withSymbol)["currency"] as? String, "USD")

    let withIso: [Line] = [
      line("ACME", row: 0),
      line("Total 42.00 EUR", row: 5),
    ]
    XCTAssertEqual(InvoiceParser.extractFields(from: withIso)["currency"] as? String, "EUR")
  }

  // MARK: - Invoice number

  func testInvoiceNumberAnchoredToKeyword() {
    let lines: [Line] = [
      line("ACME", row: 0),
      line("Invoice No: INV-2026-0042", row: 2),
      line("Total 12.00", row: 5),
    ]
    let out = InvoiceParser.extractFields(from: lines)
    XCTAssertEqual(out["invoiceNumber"] as? String, "INV-2026-0042")
  }

  // MARK: - Line items

  func testLineItemsClusterRightAlignedAmounts() {
    // Two product lines with description on the left and an amount in a
    // right-aligned column. The summary rows (subtotal/total) must NOT
    // appear in lineItems.
    let descX: CGFloat = 40
    let amtX: CGFloat = 300
    let lines: [Line] = [
      Line(text: "ACME COFFEE", frame: CGRect(x: 40, y: 40, width: 200, height: 36)),
      Line(text: "Espresso", frame: CGRect(x: descX, y: 200, width: 120, height: 22)),
      Line(text: "3.50", frame: CGRect(x: amtX, y: 200, width: 60, height: 22)),
      Line(text: "Croissant", frame: CGRect(x: descX, y: 230, width: 120, height: 22)),
      Line(text: "2.75", frame: CGRect(x: amtX, y: 230, width: 60, height: 22)),
      Line(text: "Subtotal", frame: CGRect(x: descX, y: 300, width: 120, height: 22)),
      Line(text: "6.25", frame: CGRect(x: amtX, y: 300, width: 60, height: 22)),
      Line(text: "TOTAL 6.25", frame: CGRect(x: descX, y: 340, width: 200, height: 22)),
    ]
    let out = InvoiceParser.extractFields(from: lines)
    let items = out["lineItems"] as? [[String: Any]] ?? []
    XCTAssertGreaterThanOrEqual(items.count, 2, "expected at least 2 line items, got \(items.count)")
    let descriptions = items.compactMap { $0["description"] as? String }
    XCTAssertTrue(descriptions.contains(where: { $0.contains("Espresso") }))
    XCTAssertTrue(descriptions.contains(where: { $0.contains("Croissant") }))
    // Summary rows must not leak in as line items.
    XCTAssertFalse(descriptions.contains(where: { $0.lowercased().contains("total") }))
  }

  // MARK: - rawText

  func testRawTextAlwaysPresent() {
    let lines: [Line] = [
      line("ACME", row: 0),
      line("Total 1.00", row: 5),
    ]
    let out = InvoiceParser.extractFields(from: lines)
    let raw = out["rawText"] as? String ?? ""
    XCTAssertTrue(raw.contains("ACME"))
    XCTAssertTrue(raw.contains("Total 1.00"))
  }

  func testEmptyInputReturnsEmptyFieldsButRawText() {
    let out = InvoiceParser.extractFields(from: [])
    XCTAssertNil(out["vendor"])
    XCTAssertNil(out["date"])
    XCTAssertNil(out["total"])
    XCTAssertEqual(out["rawText"] as? String, "")
    XCTAssertEqual((out["lineItems"] as? [[String: Any]])?.count, 0)
  }
}
