import Flutter
import PDFKit
import UIKit
import VisionKit

/// Per-page encoding for the document scanner. Mirrors the Dart
/// `SupyDocumentOutputFormat` enum names exactly.
enum SupyDocumentOutputFormat: String {
  case jpg
  case png
  case pdf
}

/// Presents `VNDocumentCameraViewController` over the host app's root view
/// controller, persists each captured page as a JPEG in `NSTemporaryDirectory`,
/// runs `VNRecognizeTextRequest` OCR, and bridges the assembled result back
/// to the `scanDocument` MethodChannel call.
final class DocumentScannerPresenter: NSObject, VNDocumentCameraViewControllerDelegate {

  /// Pending FlutterResult while the scanner is on-screen.
  private var pendingResult: FlutterResult?
  private var pendingArgs: [String: Any]?

  /// Background queue for JPEG encoding + file writes.
  private let ioQueue = DispatchQueue(
    label: "io.supy.scanner.document.io",
    qos: .userInitiated
  )

  private let ocrRunner = OcrRunner()

  func present(args: [String: Any]?, result: @escaping FlutterResult) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard VNDocumentCameraViewController.isSupported else {
      result(
        FlutterError(
          code: "camera_unavailable",
          message: "VNDocumentCameraViewController is not supported on this device",
          details: nil
        )
      )
      return
    }
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "unknown",
          message: "A document scan is already in progress",
          details: nil
        )
      )
      return
    }
    guard let rootViewController = Self.rootViewController() else {
      result(
        FlutterError(
          code: "camera_unavailable",
          message: "No root view controller to present from",
          details: nil
        )
      )
      return
    }

    // useNativeCore is a v1.1 wire field reserved for the C++ pre-processing
    // path. Read it here so the contract is honored end-to-end; the document
    // presenter still routes to VisionKit in v1.0 regardless.
    if (args?["useNativeCore"] as? Bool) == true {
      SupyLog.i(
        "document scan requested useNativeCore=true; ignored on v1.0 (reserved for v1.1)."
      )
    }

    pendingResult = result
    pendingArgs = args

    let scanner = VNDocumentCameraViewController()
    scanner.delegate = self
    scanner.modalPresentationStyle = .fullScreen
    DispatchQueue.main.async {
      rootViewController.present(scanner, animated: true)
    }
  }

  /// Warms VisionKit + the text recognizer. Called by `prewarm` in S3-06.
  func prewarm() {
    ocrRunner.prewarm()
  }

  // MARK: - VNDocumentCameraViewControllerDelegate

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    let args = pendingArgs
    let jpegQuality = (args?["jpegQuality"] as? Int) ?? 95
    let maxPages = (args?["maxPages"] as? Int) ?? 0
    let languages = (args?["ocrLanguages"] as? [String]) ?? ["en-US"]
    let outputFormat =
      SupyDocumentOutputFormat(rawValue: (args?["outputFormat"] as? String) ?? "jpg") ?? .jpg
    // CQG-G2: caller-supplied minimum acceptable per-page quality. Default
    // `"veryPoor"` ⇒ ordinal 0, which admits every page (non-breaking).
    let minPageQualityOrdinal = Self.qualityOrdinal(args?["minPageQuality"] as? String)
    let locale = (args?["locale"] as? String) ?? "en"
    // VisionKit auto-enhancement washes pages out (bleached paper, faint text).
    // Default `filter` is `.color`, which re-processes VisionKit's UIImage
    // through DocumentEnhancer to recover paper tone and lift text contrast.
    // Callers can pass `filter: "original"` to keep VisionKit's output as-is.
    let filter = SupyDocumentFilter.parse(args?["filter"] as? String)
    // Legacy enhanceMode is still honored for the native C-core pipeline so
    // callers that opted into it before this PR don't regress.
    let enhanceMode = Self.parseEnhanceMode(args?["enhanceMode"] as? String)
    let images = collectPages(from: scan, maxPages: maxPages)

    controller.dismiss(animated: true)

    ioQueue.async { [weak self] in
      guard let self = self else { return }
      let filtered = self.applyFilter(pages: images, filter: filter)
      let enhanced = self.enhance(pages: filtered, mode: enhanceMode)
      let persisted = self.persist(
        pages: enhanced,
        jpegQuality: jpegQuality,
        format: outputFormat
      )
      // CQG-G2: gate low-quality pages at flow exit. VisionKit owns its own
      // per-page UI (no in-flow hook), so we mirror the Android-GMS path:
      // one summary `UIAlertController` with Keep-all / Discard-low, then
      // assemble PDF + run OCR on the survivors. Asymmetry documented in
      // `docs/ARCHITECTURE.md` (live-states + retake gate, GMS-equivalent).
      self.gateLowQualityPages(
        persisted: persisted,
        minOrdinal: minPageQualityOrdinal,
        locale: locale
      ) { [weak self] accepted in
        guard let self = self else { return }
        // PDF assembly piggybacks on the JPG/PNG persistence pass — VisionKit
        // doesn't expose a native PDF result, so we build one with PDFKit
        // *after* the quality gate so discarded pages don't enter the PDF.
        let pdfUri: String? = outputFormat == .pdf
          ? self.assemblePdf(from: accepted.map { $0.image })
          : nil
        self.ocrRunner.run(pages: accepted, languages: languages) { [weak self] entries, ocrText in
          var payload: [String: Any] = [
            "pages": entries,
            "ocrText": ocrText,
            "resolvedBackend": "gms",
          ]
          if let pdfUri = pdfUri { payload["pdfUri"] = pdfUri }
          self?.finish(success: payload)
        }
      }
    }
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    DispatchQueue.main.async { [weak self] in
      self?.finish(
        error: FlutterError(
          code: "unknown",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  func documentCameraViewControllerDidCancel(
    _ controller: VNDocumentCameraViewController
  ) {
    controller.dismiss(animated: true)
    DispatchQueue.main.async { [weak self] in
      self?.finish(
        error: FlutterError(
          code: "cancelled",
          message: "User cancelled the document scan",
          details: nil
        )
      )
    }
  }

  // MARK: - Helpers

  /// Re-processes VisionKit's output through DocumentEnhancer. This is the
  /// stage that produces Scanbot-class output — paper warmth preserved, text
  /// dark and crisp. No-op for `.original`.
  private func applyFilter(pages: [UIImage], filter: SupyDocumentFilter) -> [UIImage] {
    if filter == .original { return pages }
    return pages.map { DocumentEnhancer.enhance($0, filter: filter) }
  }

  /// Runs each page through the native enhance pipeline. Pages whose
  /// enhancement fails fall back to the original `UIImage` so we never lose a
  /// capture. No-op when [mode] is `.off`.
  private func enhance(pages: [UIImage], mode: SupyEnhanceMode) -> [UIImage] {
    if mode == .off { return pages }
    return pages.map { SupyNativeCoreBridge.enhanceImage($0, mode: mode, metrics: nil) }
  }

  private static func parseEnhanceMode(_ wire: String?) -> SupyEnhanceMode {
    switch wire?.lowercased() {
    case "fast": return .fast
    case "balanced": return .balanced
    case "max": return .max
    default: return .off
    }
  }

  private func collectPages(
    from scan: VNDocumentCameraScan,
    maxPages: Int
  ) -> [UIImage] {
    let total = scan.pageCount
    let limit = maxPages > 0 ? min(total, maxPages) : total
    guard limit > 0 else { return [] }
    return (0..<limit).map { scan.imageOfPage(at: $0) }
  }

  /// Writes each image to the temp dir in the requested per-page format and
  /// returns the tuples consumed by `OcrRunner`. Pages that fail to encode are
  /// skipped — the user gets a partial result rather than a total failure
  /// (see QA.md). On `.pdf` we still persist per-page JPEGs (consumers expect
  /// `pages[].uri` regardless of format); the PDF is assembled separately.
  private func persist(
    pages: [UIImage],
    jpegQuality: Int,
    format: SupyDocumentOutputFormat
  ) -> [(uri: URL, image: UIImage, width: Int, height: Int, quality: String?, qualityScore: Double?)] {
    let quality = CGFloat(max(0, min(100, jpegQuality))) / 100.0
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let stamp = ProcessInfo.processInfo.globallyUniqueString
    var persisted: [(uri: URL, image: UIImage, width: Int, height: Int, quality: String?, qualityScore: Double?)] = []
    persisted.reserveCapacity(pages.count)

    for (index, image) in pages.enumerated() {
      let (data, ext): (Data?, String) = {
        switch format {
        case .png:
          return (image.pngData(), "png")
        case .jpg, .pdf:
          return (image.jpegData(compressionQuality: quality), "jpg")
        }
      }()
      guard let payload = data else { continue }
      let url = directory.appendingPathComponent(
        "supy_scan_\(stamp)_\(index).\(ext)"
      )
      do {
        try payload.write(to: url, options: .atomic)
        let score = SupyNativeCoreBridge.scoreImage(image)
        let wire = score.flatMap { Self.bucketWire(Int($0.bucket)) }
        let qScore: Double? = score.map { Double($0.qualityScore) }
        persisted.append(
          (
            uri: url,
            image: image,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale),
            quality: wire,
            qualityScore: qScore
          )
        )
      } catch {
        continue
      }
    }
    return persisted
  }

  // MARK: - CQG-G2 quality gate

  /// Wire-string → ordinal lookup matching `SupyDocumentPageQuality`:
  /// veryPoor=0, poor=1, ok=2, good=3, excellent=4. Unknown / nil maps to
  /// 0 (admit everything — non-breaking default).
  private static func qualityOrdinal(_ wire: String?) -> Int {
    switch wire {
    case "poor": return 1
    case "ok": return 2
    case "good": return 3
    case "excellent": return 4
    default: return 0
    }
  }

  /// Shows a single summary `UIAlertController` when any page is below the
  /// caller-supplied `minOrdinal`. Callback fires on `ioQueue` with the
  /// surviving pages. Pages whose `quality == nil` (scorer unavailable)
  /// admit unconditionally — identical fail-open semantics to Android.
  private func gateLowQualityPages(
    persisted: [(uri: URL, image: UIImage, width: Int, height: Int, quality: String?, qualityScore: Double?)],
    minOrdinal: Int,
    locale: String,
    completion: @escaping ([(uri: URL, image: UIImage, width: Int, height: Int, quality: String?, qualityScore: Double?)]) -> Void
  ) {
    if minOrdinal == 0 || persisted.isEmpty {
      completion(persisted)
      return
    }
    let lowCount = persisted.reduce(into: 0) { count, page in
      if let q = page.quality, Self.qualityOrdinal(q) < minOrdinal { count += 1 }
    }
    if lowCount == 0 {
      completion(persisted)
      return
    }
    let ar = locale.hasPrefix("ar")
    let title = ar ? "بعض الصفحات منخفضة الجودة" : "Some pages look low-quality"
    let body = ar
      ? "تم رصد \(lowCount) صفحة بجودة منخفضة. هل تحتفظ بها أم تتجاهلها؟"
      : "\(lowCount) page(s) scored below the minimum quality. Keep them or discard?"
    let keep = ar ? "احتفظ بالكل" : "Keep all"
    let discard = ar ? "تجاهل المنخفضة" : "Discard low"
    DispatchQueue.main.async {
      guard let root = Self.rootViewController() else {
        // No host — fail open, return everything (matches Android fallback).
        self.ioQueue.async { completion(persisted) }
        return
      }
      let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: keep, style: .default) { _ in
        self.ioQueue.async { completion(persisted) }
      })
      alert.addAction(UIAlertAction(title: discard, style: .destructive) { _ in
        let survivors = persisted.filter { page in
          guard let q = page.quality else { return true }
          return Self.qualityOrdinal(q) >= minOrdinal
        }
        // Best-effort cleanup of dropped temp files. Failures are silent —
        // they're in `NSTemporaryDirectory()` and the OS will reap them.
        let dropped = persisted.filter { page in
          guard let q = page.quality else { return false }
          return Self.qualityOrdinal(q) < minOrdinal
        }
        for d in dropped { try? FileManager.default.removeItem(at: d.uri) }
        self.ioQueue.async { completion(survivors) }
      })
      root.present(alert, animated: true)
    }
  }

  private static func bucketWire(_ bucket: Int) -> String? {
    switch bucket {
    case 0: return "veryPoor"
    case 1: return "poor"
    case 2: return "ok"
    case 3: return "good"
    case 4: return "excellent"
    default: return nil
    }
  }

  /// Assembles `images` into a single PDF using PDFKit and writes it to
  /// `NSTemporaryDirectory()`. Returns the file URL string on success, or nil
  /// on failure — the consumer's `pdfUri` simply gets omitted in that case.
  private func assemblePdf(from images: [UIImage]) -> String? {
    guard !images.isEmpty else { return nil }
    let document = PDFDocument()
    for (index, image) in images.enumerated() {
      guard let page = PDFPage(image: image) else { continue }
      document.insert(page, at: index)
    }
    guard document.pageCount > 0, let data = document.dataRepresentation() else {
      return nil
    }
    let stamp = ProcessInfo.processInfo.globallyUniqueString
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("supy_scan_\(stamp).pdf")
    do {
      try data.write(to: url, options: .atomic)
      return url.absoluteString
    } catch {
      return nil
    }
  }

  private func finish(success payload: [String: Any]) {
    let result = pendingResult
    pendingResult = nil
    pendingArgs = nil
    if Thread.isMainThread {
      result?(payload)
    } else {
      DispatchQueue.main.async { result?(payload) }
    }
  }

  private func finish(error: FlutterError) {
    let result = pendingResult
    pendingResult = nil
    pendingArgs = nil
    if Thread.isMainThread {
      result?(error)
    } else {
      DispatchQueue.main.async { result?(error) }
    }
  }

  private static func rootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    let keyWindow = scenes
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
