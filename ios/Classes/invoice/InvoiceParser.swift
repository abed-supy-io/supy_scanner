import CoreGraphics
import Foundation
import UIKit
import Vision

/// Experimental on-device invoice parser. Phase IXP — example-app-only.
///
/// Pipeline: Vision text recognition (`.accurate`, no language correction,
/// custom-words seeded with invoice keywords) → layout-aware heuristics over
/// the bounding boxes.
///
/// No cloud calls, no Core ML model. Per `CLAUDE.md` iOS threading rule, all
/// Vision work runs on a background queue and we marshal back to main only at
/// the result boundary.
enum InvoiceParser {

  /// Parses [image] and returns a wire-shape dict matching `SupyInvoiceData`
  /// on the Dart side. Invokes [completion] on the main queue exactly once.
  ///
  /// Callers are expected to pass an already-enhanced page (the output of
  /// `scanDocument` with the default `.color` filter). Re-enhancing inside
  /// the parser doubles the Core Image work per page and adds hundreds of
  /// milliseconds on multi-page Lab scans.
  static func parse(
    image: UIImage,
    completion: @escaping ([String: Any]) -> Void
  ) {
    workQueue.async {
      let lines = recognizeLines(in: image)
      let result = extractFields(from: lines)
      DispatchQueue.main.async { completion(result) }
    }
  }

  // MARK: - Vision

  private static let workQueue = DispatchQueue(
    label: "io.supy.scanner.invoice.parse",
    qos: .userInitiated
  )

  /// Seeds the recognizer with currency codes and invoice keywords so they
  /// survive against the dictionary. `usesLanguageCorrection=false` keeps the
  /// codes intact ("USD" stays "USD", not "use").
  private static let customWords: [String] = [
    "USD", "EUR", "GBP", "AED", "SAR", "QAR", "KWD", "BHD", "OMR",
    "INR", "CAD", "AUD", "JPY", "CNY",
    "INVOICE", "Invoice", "TAX", "VAT", "TOTAL", "Subtotal", "Total",
    "BILL", "DUE", "BALANCE", "AMOUNT",
  ]

  /// One recognized line with its bounding box in *image pixel* coords
  /// (origin top-left, Y growing downward — easier to reason about for
  /// row clustering than Vision's normalized bottom-up box).
  struct Line {
    let text: String
    let frame: CGRect
    /// Box height in pixels — used as a font-size proxy for "largest near top".
    var height: CGFloat { frame.height }
    /// Y center, used for row banding.
    var midY: CGFloat { frame.midY }
    /// X left edge, used for column inference.
    var minX: CGFloat { frame.minX }
    var maxX: CGFloat { frame.maxX }
  }

  private static func recognizeLines(in image: UIImage) -> [Line] {
    guard let cg = image.cgImage else { return [] }
    let imgW = CGFloat(cg.width)
    let imgH = CGFloat(cg.height)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.customWords = customWords
    let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    guard let observations = request.results else { return [] }
    return observations.compactMap { obs in
      guard let candidate = obs.topCandidates(1).first else { return nil }
      // Vision boundingBox is normalized, bottom-left origin. Flip to
      // top-left pixel coords.
      let bb = obs.boundingBox
      let x = bb.minX * imgW
      let h = bb.height * imgH
      let yTop = (1 - bb.maxY) * imgH
      let w = bb.width * imgW
      return Line(text: candidate.string, frame: CGRect(x: x, y: yTop, width: w, height: h))
    }
  }

  // MARK: - Field extraction (visible for testing)

  /// Heuristic extractor. Public so `InvoiceParserTests` can drive it with
  /// synthetic `Line` fixtures without spinning up Vision.
  static func extractFields(from lines: [Line]) -> [String: Any] {
    let sorted = lines.sorted { $0.midY < $1.midY }
    let raw = sorted.map { $0.text }.joined(separator: "\n")

    var out: [String: Any] = [:]
    if let v = vendor(in: sorted) { out["vendor"] = v }
    if let d = date(in: sorted) { out["date"] = d }
    if let n = invoiceNumber(in: sorted) { out["invoiceNumber"] = n }
    if let c = currency(in: sorted) { out["currency"] = c }
    if let t = amount(in: sorted, keywords: totalKeywords) { out["total"] = t }
    if let t = amount(in: sorted, keywords: taxKeywords) { out["tax"] = t }
    out["lineItems"] = lineItems(in: sorted)
    out["rawText"] = raw
    return out
  }

  // MARK: - Vendor

  /// Largest-font line in the top 30% of the page that isn't a date/amount/
  /// keyword. Falls back to the first non-empty line.
  private static func vendor(in lines: [Line]) -> String? {
    guard let pageBottom = lines.map({ $0.frame.maxY }).max(), pageBottom > 0 else { return nil }
    let topBand = pageBottom * 0.3
    let candidates = lines.filter { $0.midY <= topBand && !looksLikeNoise($0.text) }
    let best = candidates.max(by: { $0.height < $1.height })
    if let best, !best.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return best.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return lines.first { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.text
  }

  private static func looksLikeNoise(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return true }
    if dateRegex.firstMatch(in: trimmed) != nil { return true }
    if amountRegex.firstMatch(in: trimmed) != nil && trimmed.count < 16 { return true }
    let lowered = trimmed.lowercased()
    for kw in (totalKeywords + taxKeywords + ["invoice", "receipt", "bill"]) {
      if lowered.contains(kw) { return true }
    }
    return false
  }

  // MARK: - Date

  /// Matches: 2026-06-17, 17/06/2026, 06-17-2026, 17 Jun 2026, Jun 17, 2026.
  /// Returns the raw matched string; downstream consumers can normalize.
  private static let dateRegex: NSRegularExpression = {
    let pattern = [
      #"\b\d{4}[-/.]\d{1,2}[-/.]\d{1,2}\b"#,
      #"\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b"#,
      #"\b\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{2,4}\b"#,
      #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4}\b"#,
    ].joined(separator: "|")
    return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
  }()

  private static func date(in lines: [Line]) -> String? {
    for l in lines {
      if let m = dateRegex.firstMatch(in: l.text) { return m }
    }
    return nil
  }

  // MARK: - Invoice number

  /// Keyword anchor: same line OR following line of an "invoice no" header,
  /// matching an alphanumeric token at least 3 chars long.
  private static let invoiceNumberRegex = try! NSRegularExpression(
    pattern: #"\b[A-Z0-9][A-Z0-9\-/]{2,}\b"#,
    options: []
  )

  private static func invoiceNumber(in lines: [Line]) -> String? {
    for (i, l) in lines.enumerated() {
      let lowered = l.text.lowercased()
      guard lowered.contains("invoice") || lowered.contains("inv #") || lowered.contains("inv.")
              || lowered.contains("invoice no") || lowered.contains("invoice #")
      else { continue }
      // Drop the keyword chunk before searching for the value.
      let stripped = l.text
        .replacingOccurrences(of: "invoice", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "no.", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "#", with: "")
        .replacingOccurrences(of: ":", with: " ")
      if let m = invoiceNumberRegex.firstMatch(in: stripped) { return m }
      // Try the next line down (label/value laid out as two rows).
      if i + 1 < lines.count {
        if let m = invoiceNumberRegex.firstMatch(in: lines[i + 1].text) { return m }
      }
    }
    return nil
  }

  // MARK: - Currency

  /// Detects ISO codes via boundary match and common symbols anywhere in the
  /// text. Returns the ISO 4217 code where possible.
  private static let isoCodes: [String] = [
    "USD", "EUR", "GBP", "AED", "SAR", "QAR", "KWD", "BHD", "OMR",
    "INR", "CAD", "AUD", "JPY", "CNY",
  ]
  private static let symbolToIso: [(String, String)] = [
    ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"),
    ("₹", "INR"), ("د.إ", "AED"), ("ر.س", "SAR"),
  ]

  private static func currency(in lines: [Line]) -> String? {
    let joined = lines.map { $0.text }.joined(separator: " ")
    for code in isoCodes {
      let pattern = "\\b" + code + "\\b"
      if joined.range(of: pattern, options: .regularExpression) != nil { return code }
    }
    for (sym, iso) in symbolToIso {
      if joined.contains(sym) { return iso }
    }
    return nil
  }

  // MARK: - Amount (total / tax)

  private static let totalKeywords = ["total", "grand total", "amount due", "balance due", "amount"]
  private static let taxKeywords = ["tax", "vat", "gst"]

  /// `1,234.56` `1234.56` `1234,56` `1 234.56`. Captures decimals;
  /// integer-only matches are allowed but ranked below.
  private static let amountRegex = try! NSRegularExpression(
    pattern: #"(?:\d{1,3}(?:[,\s\u00A0]\d{3})+|\d+)(?:[.,]\d{2})?"#,
    options: []
  )

  private static func amount(in lines: [Line], keywords: [String]) -> Double? {
    // Prefer the value on the same line as the keyword. If absent, take the
    // largest numeric on the line below (right-aligned label/value layout).
    for (i, l) in lines.enumerated() {
      let lowered = l.text.lowercased()
      guard keywords.contains(where: { lowered.contains($0) }) else { continue }
      // Strip keyword to avoid catching digits inside it (e.g. "VAT 14%").
      var scratch = l.text.lowercased()
      for kw in keywords { scratch = scratch.replacingOccurrences(of: kw, with: " ") }
      // Drop percent-suffixed numbers — those are tax rates, not amounts.
      let candidates = matches(amountRegex, in: scratch).filter { !isPercentage($0, in: scratch) }
      if let best = candidates.compactMap({ parseAmount($0) }).max() {
        return best
      }
      if i + 1 < lines.count {
        let next = lines[i + 1].text
        if let best = matches(amountRegex, in: next).compactMap({ parseAmount($0) }).max() {
          return best
        }
      }
    }
    return nil
  }

  private static func isPercentage(_ match: String, in text: String) -> Bool {
    guard let r = text.range(of: match) else { return false }
    let suffix = text[r.upperBound...].prefix(2)
    return suffix.contains("%")
  }

  /// "1,234.56" -> 1234.56. Heuristic: if both `,` and `.` are present, the
  /// rightmost is the decimal separator. Else if a single `,` has exactly
  /// two trailing digits, treat as European decimal. Else strip commas.
  static func parseAmount(_ raw: String) -> Double? {
    let cleaned = raw.replacingOccurrences(of: "\u{00A0}", with: "")
      .replacingOccurrences(of: " ", with: "")
    let hasComma = cleaned.contains(",")
    let hasDot = cleaned.contains(".")
    let normalized: String
    if hasComma && hasDot {
      let lastComma = cleaned.lastIndex(of: ",") ?? cleaned.startIndex
      let lastDot = cleaned.lastIndex(of: ".") ?? cleaned.startIndex
      if lastComma > lastDot {
        normalized = cleaned.replacingOccurrences(of: ".", with: "")
          .replacingOccurrences(of: ",", with: ".")
      } else {
        normalized = cleaned.replacingOccurrences(of: ",", with: "")
      }
    } else if hasComma {
      let parts = cleaned.split(separator: ",")
      if parts.count == 2 && parts[1].count == 2 {
        normalized = cleaned.replacingOccurrences(of: ",", with: ".")
      } else {
        normalized = cleaned.replacingOccurrences(of: ",", with: "")
      }
    } else {
      normalized = cleaned
    }
    return Double(normalized)
  }

  // MARK: - Line items

  /// Row clustering: bucket lines into bands by Y center (tolerance = median
  /// line height). A row is a candidate item iff it contains both a textual
  /// chunk (description) and a right-aligned numeric chunk.
  private static func lineItems(in lines: [Line]) -> [[String: Any]] {
    guard !lines.isEmpty else { return [] }
    let median = medianHeight(of: lines)
    let tolerance = max(median * 0.6, 6.0)

    // Group into rows.
    var rows: [[Line]] = []
    for line in lines.sorted(by: { $0.midY < $1.midY }) {
      if let last = rows.last, let anchor = last.first,
         abs(line.midY - anchor.midY) <= tolerance {
        rows[rows.count - 1].append(line)
      } else {
        rows.append([line])
      }
    }

    var items: [[String: Any]] = []
    for row in rows {
      let sortedRow = row.sorted { $0.minX < $1.minX }
      let numericFragments = sortedRow.compactMap { l -> (Line, Double)? in
        let trimmed = l.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = parseAmount(trimmed.filter { "0123456789.,".contains($0) }), !trimmed.isEmpty {
          return (l, v)
        }
        return nil
      }
      let textFragments = sortedRow.filter { l in
        let t = l.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains(where: { $0.isLetter })
      }
      guard let descriptionLine = textFragments.first,
            let rightmostNumeric = numericFragments.last
      else { continue }
      // Skip rows whose description IS a header keyword.
      let lowered = descriptionLine.text.lowercased()
      if (totalKeywords + taxKeywords).contains(where: { lowered.contains($0) }) { continue }
      // Numeric must sit visibly to the right of the description.
      guard rightmostNumeric.0.minX >= descriptionLine.maxX - 4 else { continue }

      var item: [String: Any] = [
        "description": textFragments.map { $0.text }.joined(separator: " ")
          .trimmingCharacters(in: .whitespacesAndNewlines),
        "amount": rightmostNumeric.1,
      ]
      // If there's a small integer fragment to the left of the amount, treat
      // as quantity (e.g. "Latte  2  10.00").
      let between = numericFragments.dropLast().filter { frag in
        frag.0.minX >= descriptionLine.maxX - 4
      }
      if let qty = between.first, qty.1 < 1000, qty.1.truncatingRemainder(dividingBy: 1) == 0 {
        item["quantity"] = Int(qty.1)
      }
      items.append(item)
    }
    return items
  }

  private static func medianHeight(of lines: [Line]) -> CGFloat {
    let sorted = lines.map { $0.height }.sorted()
    guard !sorted.isEmpty else { return 0 }
    return sorted[sorted.count / 2]
  }

  // MARK: - Regex helpers

  private static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { m in
      guard let r = Range(m.range, in: text) else { return nil }
      return String(text[r])
    }
  }
}

private extension NSRegularExpression {
  func firstMatch(in text: String) -> String? {
    let range = NSRange(text.startIndex..., in: text)
    guard let m = firstMatch(in: text, options: [], range: range),
          let r = Range(m.range, in: text)
    else { return nil }
    return String(text[r])
  }
}
