import Flutter
import UIKit
import VisionKit

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
    let images = collectPages(from: scan, maxPages: maxPages)

    controller.dismiss(animated: true)

    ioQueue.async { [weak self] in
      guard let self = self else { return }
      let persisted = self.persist(pages: images, jpegQuality: jpegQuality)
      self.ocrRunner.run(pages: persisted, languages: languages) { [weak self] entries, ocrText in
        self?.finish(success: [
          "pages": entries,
          "ocrText": ocrText,
        ])
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

  /// Writes each image to a JPEG in `NSTemporaryDirectory()` and returns the
  /// tuples consumed by `OcrRunner`. Pages that fail to encode are skipped —
  /// the user gets a partial result rather than a total failure (see QA.md).
  private func persist(
    pages: [UIImage],
    jpegQuality: Int
  ) -> [(uri: URL, image: UIImage, width: Int, height: Int)] {
    let quality = CGFloat(max(0, min(100, jpegQuality))) / 100.0
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let stamp = ProcessInfo.processInfo.globallyUniqueString
    var persisted: [(uri: URL, image: UIImage, width: Int, height: Int)] = []
    persisted.reserveCapacity(pages.count)

    for (index, image) in pages.enumerated() {
      guard let data = image.jpegData(compressionQuality: quality) else { continue }
      let url = directory.appendingPathComponent(
        "supy_scan_\(stamp)_\(index).jpg"
      )
      do {
        try data.write(to: url, options: .atomic)
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
