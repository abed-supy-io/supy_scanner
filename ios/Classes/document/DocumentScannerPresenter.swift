import Flutter
import ImageIO
import PDFKit
import UIKit
import VisionKit

// SPM builds the Obj-C bridge as a separate module; CocoaPods folds it into
// this umbrella module.
#if SWIFT_PACKAGE
import supy_scanner_objc
#endif

/// Per-page encoding for the document scanner. Mirrors the Dart
/// `SupyDocumentOutputFormat` enum names exactly.
enum SupyDocumentOutputFormat: String {
  case jpg
  case png
  case pdf
  /// v1.2 Phase DC8: JPG pages + a multi-page TIFF on `tiffUri`.
  case tiff
  /// v1.2 Phase DC8: JPG pages + a PDF carrying an invisible, selectable OCR
  /// text layer on `pdfUri`.
  case searchablePdf
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
    // Phase DPX: the full document pipeline (detect → perspective-correct →
    // crop → deskew → illumination/whitening/contrast → resize). VisionKit has
    // no preview seed, so the processor detects the document on the still and
    // crops it — recovering the tight, Full-HD-class scan its stock auto-crop
    // misses on white-page-on-light-surface captures. `filter` maps into the
    // enhancement mode; per-page `processing` overrides come from the wire.
    let processing = DocumentProcessingOptions.parse(
      args,
      fallbackFilter: filter,
      fallbackQuality: jpegQuality
    )
    // Legacy enhanceMode is still honored for the native C-core pipeline so
    // callers that opted into it before this PR don't regress.
    let enhanceMode = Self.parseEnhanceMode(args?["enhanceMode"] as? String)
    let images = collectPages(from: scan, maxPages: maxPages)

    controller.dismiss(animated: true)

    ioQueue.async { [weak self] in
      guard let self = self else { return }
      let processed = images.map { DocumentProcessor.process($0, options: processing) }
      let enhanced = self.enhance(pages: processed, mode: enhanceMode)
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
        // Export assembly piggybacks on the JPG/PNG persistence pass — VisionKit
        // exposes no native PDF/TIFF result, so we build them *after* the
        // quality gate so discarded pages don't enter the artifact.
        switch outputFormat {
        case .searchablePdf:
          // One OCR pass yields both `ocrText` and the word boxes for the
          // invisible text layer — no second recognition pass.
          self.ocrRunner.runWithWords(pages: accepted, languages: languages) {
            [weak self] entries, ocrText, wordsPerPage in
            guard let self = self else { return }
            let pageWords = zip(accepted.map { $0.image }, wordsPerPage)
              .map { (image: $0.0, words: $0.1) }
            let pdfUri = self.assembleSearchablePdf(from: pageWords)
            var payload: [String: Any] = [
              "pages": entries,
              "ocrText": ocrText,
              "resolvedBackend": "gms",
            ]
            if let pdfUri = pdfUri { payload["pdfUri"] = pdfUri }
            self.finish(success: payload)
          }
        case .tiff:
          let tiffUri = self.assembleTiff(from: accepted.map { $0.image })
          self.ocrRunner.run(pages: accepted, languages: languages) { [weak self] entries, ocrText in
            var payload: [String: Any] = [
              "pages": entries,
              "ocrText": ocrText,
              "resolvedBackend": "gms",
            ]
            if let tiffUri = tiffUri { payload["tiffUri"] = tiffUri }
            self?.finish(success: payload)
          }
        default:
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
        case .jpg, .pdf, .tiff, .searchablePdf:
          // tiff/searchablePdf still surface per-page JPEGs on `pages[].uri`;
          // the TIFF / searchable PDF is assembled separately from these images.
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

  /// Assembles `images` into a single multi-page TIFF via ImageIO's built-in
  /// encoder (`public.tiff`) and writes it to `NSTemporaryDirectory()`. Returns
  /// the file URL string, or nil on failure. v1.2 Phase DC8.
  private func assembleTiff(from images: [UIImage]) -> String? {
    let cgImages = images.compactMap { Self.orientedCGImage($0) }
    guard !cgImages.isEmpty else { return nil }
    let stamp = ProcessInfo.processInfo.globallyUniqueString
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("supy_scan_\(stamp).tiff")
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.tiff" as CFString,
        cgImages.count,
        nil
      )
    else { return nil }
    for cgImage in cgImages {
      CGImageDestinationAddImage(destination, cgImage, nil)
    }
    guard CGImageDestinationFinalize(destination) else { return nil }
    return url.absoluteString
  }

  /// Assembles a searchable PDF: each page's image is drawn, then every
  /// recognized word is stamped on top in `UIColor.clear` — the glyphs enter
  /// the PDF content stream (selectable and searchable) but render invisibly,
  /// mirroring the Android `alpha = 0` text layer. Word boxes are normalized
  /// `[0..1]`, top-left origin. v1.2 Phase DC8.
  private func assembleSearchablePdf(
    from pages: [(image: UIImage, words: [SupyOcrWord])]
  ) -> String? {
    guard !pages.isEmpty else { return nil }
    let stamp = ProcessInfo.processInfo.globallyUniqueString
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("supy_scan_\(stamp).pdf")

    // The renderer needs an initial bounds; each page overrides it via
    // `beginPage(withBounds:)` so mixed page sizes stay correct.
    let first = pages[0].image
    let firstBounds = CGRect(origin: .zero, size: first.size)
    let renderer = UIGraphicsPDFRenderer(bounds: firstBounds)
    do {
      try renderer.writePDF(to: url) { context in
        for page in pages {
          let size = page.image.size
          let bounds = CGRect(origin: .zero, size: size)
          context.beginPage(withBounds: bounds, pageInfo: [:])
          page.image.draw(in: bounds)
          for word in page.words where !word.text.isEmpty {
            let rect = CGRect(
              x: word.left * size.width,
              y: word.top * size.height,
              width: word.width * size.width,
              height: word.height * size.height
            )
            guard rect.width > 0, rect.height > 0 else { continue }
            let font = UIFont.systemFont(ofSize: max(1, rect.height))
            let attributes: [NSAttributedString.Key: Any] = [
              .font: font,
              .foregroundColor: UIColor.clear,
            ]
            (word.text as NSString).draw(in: rect, withAttributes: attributes)
          }
        }
      }
      return url.absoluteString
    } catch {
      return nil
    }
  }

  /// Returns a `CGImage` with the image's orientation baked in. ImageIO's TIFF
  /// encoder ignores `UIImage.imageOrientation`, so a non-`.up` page would be
  /// written rotated; redraw it upright first. VisionKit pages are normally
  /// `.up`, so this is usually the fast path.
  private static func orientedCGImage(_ image: UIImage) -> CGImage? {
    if image.imageOrientation == .up, let cg = image.cgImage { return cg }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    let redrawn = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    return redrawn.cgImage
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
