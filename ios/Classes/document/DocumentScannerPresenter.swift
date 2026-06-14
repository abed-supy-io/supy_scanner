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
      NSLog(
        "SupyScanner: document scan requested useNativeCore=true; ignored on v1.0 (reserved for v1.1)."
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
    let jpegQuality = (args?["jpegQuality"] as? Int) ?? 85
    let maxPages = (args?["maxPages"] as? Int) ?? 0
    let languages = (args?["ocrLanguages"] as? [String]) ?? ["en-US"]
    let outputFormat =
      SupyDocumentOutputFormat(rawValue: (args?["outputFormat"] as? String) ?? "jpg") ?? .jpg
    let images = collectPages(from: scan, maxPages: maxPages)

    controller.dismiss(animated: true)

    ioQueue.async { [weak self] in
      guard let self = self else { return }
      let persisted = self.persist(
        pages: images,
        jpegQuality: jpegQuality,
        format: outputFormat
      )
      // PDF assembly piggybacks on the JPG/PNG persistence pass — VisionKit
      // doesn't expose a native PDF result, so we build one with PDFKit. On
      // PNG/JPG runs `pdfUri` is omitted from the payload.
      let pdfUri: String? =
        outputFormat == .pdf ? self.assemblePdf(from: images) : nil
      self.ocrRunner.run(pages: persisted, languages: languages) { [weak self] entries, ocrText in
        var payload: [String: Any] = [
          "pages": entries,
          "ocrText": ocrText,
        ]
        if let pdfUri = pdfUri { payload["pdfUri"] = pdfUri }
        self?.finish(success: payload)
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
  ) -> [(uri: URL, image: UIImage, width: Int, height: Int)] {
    let quality = CGFloat(max(0, min(100, jpegQuality))) / 100.0
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let stamp = ProcessInfo.processInfo.globallyUniqueString
    var persisted: [(uri: URL, image: UIImage, width: Int, height: Int)] = []
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
        persisted.append(
          (
            uri: url,
            image: image,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale)
          )
        )
      } catch {
        continue
      }
    }
    return persisted
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
