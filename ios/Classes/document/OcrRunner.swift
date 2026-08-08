import UIKit
import Vision

/// A recognized word plus its normalized `[0..1]` top-left bounding box — the
/// unit of the invisible text layer drawn by the searchable-PDF exporter.
/// v1.2 Phase DC8.
struct SupyOcrWord {
  let text: String
  let left: Double
  let top: Double
  let width: Double
  let height: Double
}

/// Runs `VNRecognizeTextRequest` over a set of pages and concatenates the
/// recognized strings.
///
/// Unlike the Android side, Vision text recognition supports `ar` in addition
/// to Latin scripts, so the iOS pipeline is the language-complete one for
/// Supy's coverage matrix.
final class OcrRunner {

  /// Background queue for VNRequest work. Vision is CPU-heavy; never run on
  /// the main thread.
  private let workQueue = DispatchQueue(
    label: "io.supy.scanner.document.ocr",
    qos: .userInitiated
  )

  /// Runs OCR over each `(uri, image)` pair on a background queue and
  /// invokes [completion] on the main queue once. Per-page failures yield
  /// empty text for that page rather than failing the whole batch.
  func run(
    pages: [(uri: URL, image: UIImage, width: Int, height: Int, quality: String?, qualityScore: Double?)],
    languages: [String],
    completion: @escaping (_ pages: [[String: Any]], _ ocrText: String) -> Void
  ) {
    guard !pages.isEmpty else {
      DispatchQueue.main.async { completion([], "") }
      return
    }

    let longEdgeCap = SupyDeviceTier.detect().ocrLongEdgeCap

    workQueue.async {
      let recognized: [String] = pages.map { page in
        let prepared = Self.downscaleIfNeeded(page.image, longEdgeCap: longEdgeCap)
        return Self.recognizeText(in: prepared, languages: languages)
      }
      let entries: [[String: Any]] = pages.map { page in
        var entry: [String: Any] = [
          "uri": page.uri.absoluteString,
          "width": page.width,
          "height": page.height,
        ]
        if let q = page.quality { entry["quality"] = q }
        if let qs = page.qualityScore { entry["qualityScore"] = qs }
        return entry
      }
      let joined = recognized
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      DispatchQueue.main.async {
        completion(entries, joined)
      }
    }
  }

  /// Like [run], but also returns each page's word boxes so a single OCR pass
  /// feeds both `ocrText` and the searchable-PDF invisible text layer — no
  /// second recognition pass. `wordsPerPage` is index-aligned with [pages].
  /// Word boxes are normalized `[0..1]` (top-left origin), so the downscale
  /// applied for recognition doesn't affect them. v1.2 Phase DC8.
  func runWithWords(
    pages: [(uri: URL, image: UIImage, width: Int, height: Int, quality: String?, qualityScore: Double?)],
    languages: [String],
    completion: @escaping (_ pages: [[String: Any]], _ ocrText: String, _ wordsPerPage: [[SupyOcrWord]]) -> Void
  ) {
    guard !pages.isEmpty else {
      DispatchQueue.main.async { completion([], "", []) }
      return
    }

    let longEdgeCap = SupyDeviceTier.detect().ocrLongEdgeCap

    workQueue.async {
      var recognized: [String] = []
      var wordsPerPage: [[SupyOcrWord]] = []
      recognized.reserveCapacity(pages.count)
      wordsPerPage.reserveCapacity(pages.count)
      for page in pages {
        let prepared = Self.downscaleIfNeeded(page.image, longEdgeCap: longEdgeCap)
        let (text, words) = Self.recognizeTextAndWords(in: prepared, languages: languages)
        recognized.append(text)
        wordsPerPage.append(words)
      }
      let entries: [[String: Any]] = pages.map { page in
        var entry: [String: Any] = [
          "uri": page.uri.absoluteString,
          "width": page.width,
          "height": page.height,
        ]
        if let q = page.quality { entry["quality"] = q }
        if let qs = page.qualityScore { entry["qualityScore"] = qs }
        return entry
      }
      let joined = recognized
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      DispatchQueue.main.async {
        completion(entries, joined, wordsPerPage)
      }
    }
  }

  /// Runs a single-image structured OCR pass and returns the block → line →
  /// element tree consumed by `SupyRecognizedText.fromMap` on the Dart side.
  ///
  /// Vision has no paragraph/block concept, so all recognized lines are
  /// wrapped in one synthetic block whose box is the union of its lines.
  /// Bounding boxes are normalized `[0..1]` with the origin flipped from
  /// Vision's bottom-left to Supy's top-left convention.
  func recognizeStructured(
    image: UIImage,
    languages: [String],
    includeElements: Bool,
    completion: @escaping (_ tree: [String: Any]) -> Void
  ) {
    let longEdgeCap = SupyDeviceTier.detect().ocrLongEdgeCap
    workQueue.async {
      let prepared = Self.downscaleIfNeeded(image, longEdgeCap: longEdgeCap)
      let tree = Self.recognizeStructured(
        in: prepared,
        languages: languages,
        includeElements: includeElements
      )
      DispatchQueue.main.async { completion(tree) }
    }
  }

  /// Warms the recognizer by running a request on a 1x1 image. Used by
  /// `prewarm()` in S3-06.
  func prewarm() {
    workQueue.async {
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
      let blank = renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
      }
      _ = Self.recognizeText(in: blank, languages: ["en-US"])
    }
  }

  private static func recognizeText(
    in image: UIImage,
    languages: [String]
  ) -> String {
    guard let cgImage = image.cgImage else { return "" }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if !languages.isEmpty {
      request.recognitionLanguages = languages
    }
    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: cgOrientation(from: image.imageOrientation),
      options: [:]
    )
    do {
      try handler.perform([request])
    } catch {
      return ""
    }
    guard let observations = request.results else { return "" }
    return observations
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
  }

  /// Single OCR pass returning both the joined line text and every word's
  /// normalized box — the data the searchable-PDF exporter needs. Failures
  /// yield `("", [])` for the page rather than throwing.
  private static func recognizeTextAndWords(
    in image: UIImage,
    languages: [String]
  ) -> (text: String, words: [SupyOcrWord]) {
    guard let cgImage = image.cgImage else { return ("", []) }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if !languages.isEmpty {
      request.recognitionLanguages = languages
    }
    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: cgOrientation(from: image.imageOrientation),
      options: [:]
    )
    do {
      try handler.perform([request])
    } catch {
      return ("", [])
    }
    guard let observations = request.results else { return ("", []) }
    var lineTexts: [String] = []
    var words: [SupyOcrWord] = []
    for obs in observations {
      guard let candidate = obs.topCandidates(1).first else { continue }
      lineTexts.append(candidate.string)
      words.append(contentsOf: wordBoxes(in: candidate, text: candidate.string))
    }
    return (lineTexts.joined(separator: "\n"), words)
  }

  private static func recognizeStructured(
    in image: UIImage,
    languages: [String],
    includeElements: Bool
  ) -> [String: Any] {
    let empty: [String: Any] = ["fullText": "", "blocks": []]
    guard let cgImage = image.cgImage else { return empty }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if !languages.isEmpty {
      request.recognitionLanguages = languages
    }
    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: cgOrientation(from: image.imageOrientation),
      options: [:]
    )
    do {
      try handler.perform([request])
    } catch {
      return empty
    }
    guard let observations = request.results, !observations.isEmpty else {
      return empty
    }

    var lines: [[String: Any]] = []
    var lineTexts: [String] = []
    var union: CGRect?

    for obs in observations {
      guard let candidate = obs.topCandidates(1).first else { continue }
      let text = candidate.string
      lineTexts.append(text)
      union = union.map { $0.union(obs.boundingBox) } ?? obs.boundingBox

      var elements: [[String: Any]] = []
      if includeElements {
        elements = words(in: candidate, text: text)
      }
      lines.append([
        "text": text,
        "boundingBox": normRect(obs.boundingBox),
        "elements": elements,
      ])
    }

    let fullText = lineTexts.joined(separator: "\n")
    let block: [String: Any] = [
      "text": fullText,
      "boundingBox": normRect(union ?? .zero),
      "lines": lines,
    ]
    return ["fullText": fullText, "blocks": [block]]
  }

  /// Splits a recognized line into whitespace-delimited words and resolves
  /// each word's box via `VNRecognizedText.boundingBox(for:)`. Serialized shape
  /// for the structured OCR tree; wraps the shared [wordBoxes] tokenizer.
  private static func words(
    in candidate: VNRecognizedText,
    text: String
  ) -> [[String: Any]] {
    return wordBoxes(in: candidate, text: text).map { word in
      [
        "text": word.text,
        "boundingBox": [
          "left": word.left,
          "top": word.top,
          "width": word.width,
          "height": word.height,
        ],
      ]
    }
  }

  /// Shared tokenizer: splits [text] on whitespace and resolves each word's
  /// normalized `[0..1]` top-left box via `VNRecognizedText.boundingBox(for:)`.
  private static func wordBoxes(
    in candidate: VNRecognizedText,
    text: String
  ) -> [SupyOcrWord] {
    var out: [SupyOcrWord] = []
    var idx = text.startIndex
    while idx < text.endIndex {
      while idx < text.endIndex, text[idx].isWhitespace {
        idx = text.index(after: idx)
      }
      guard idx < text.endIndex else { break }
      let start = idx
      while idx < text.endIndex, !text[idx].isWhitespace {
        idx = text.index(after: idx)
      }
      let word = String(text[start..<idx])
      let box: CGRect
      if let rect = try? candidate.boundingBox(for: start..<idx)?.boundingBox {
        box = rect
      } else {
        box = .zero
      }
      let n = normRect(box)
      out.append(
        SupyOcrWord(
          text: word,
          left: n["left"] ?? 0,
          top: n["top"] ?? 0,
          width: n["width"] ?? 0,
          height: n["height"] ?? 0
        )
      )
    }
    return out
  }

  /// Normalizes a Vision bounding box (origin bottom-left) to Supy's
  /// top-left `[0..1]` `{left, top, width, height}` convention.
  private static func normRect(_ bb: CGRect) -> [String: Double] {
    return [
      "left": Double(bb.origin.x),
      "top": Double(1.0 - bb.origin.y - bb.size.height),
      "width": Double(bb.size.width),
      "height": Double(bb.size.height),
    ]
  }

  /// Downscales [image] so its long edge is at most [longEdgeCap]. The
  /// persisted page bytes returned to the consumer are unaffected — this
  /// only reduces the in-memory copy fed to Vision.
  private static func downscaleIfNeeded(
    _ image: UIImage,
    longEdgeCap: Int?
  ) -> UIImage {
    guard let cap = longEdgeCap else { return image }
    let longEdge = max(image.size.width, image.size.height) * image.scale
    guard longEdge > CGFloat(cap) else { return image }
    let scale = CGFloat(cap) / longEdge
    let targetSize = CGSize(
      width: image.size.width * scale,
      height: image.size.height * scale
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private static func cgOrientation(
    from orientation: UIImage.Orientation
  ) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
