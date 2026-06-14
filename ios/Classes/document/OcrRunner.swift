import UIKit
import Vision

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
    pages: [(uri: URL, image: UIImage, width: Int, height: Int)],
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
        [
          "uri": page.uri.absoluteString,
          "width": page.width,
          "height": page.height,
        ]
      }
      let joined = recognized
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      DispatchQueue.main.async {
        completion(entries, joined)
      }
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
