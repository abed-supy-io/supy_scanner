import CoreImage
import Flutter
import PhotosUI
import UIKit

// SPM builds the Obj-C bridge as a separate module; CocoaPods folds it into
// this umbrella module.
#if SWIFT_PACKAGE
import supy_scanner_objc
#endif

/// Presents the system photo picker (`PHPickerViewController`), runs on-device
/// document edge-detection + perspective rectification on the chosen image, and
/// bridges a single cropped page back to the `importDocumentImage` channel call.
///
/// No image bytes cross the channel and nothing leaves the device — the pick,
/// detect, warp, enhance, and persist all happen natively. Dismissal without a
/// pick resolves the call with `nil` (Dart `null`), matching the branded
/// capture flow's "user backed out" outcome.
final class DocumentImportPresenter: NSObject, PHPickerViewControllerDelegate {

  /// Pending FlutterResult while the picker is on-screen.
  private var pendingResult: FlutterResult?

  /// Background queue for Vision + Core Image + file writes.
  private let ioQueue = DispatchQueue(
    label: "io.supy.scanner.document.import.io",
    qos: .userInitiated
  )

  func present(result: @escaping FlutterResult) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "unknown",
          message: "A document import is already in progress",
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

    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    picker.modalPresentationStyle = .automatic
    rootViewController.present(picker, animated: true)
  }

  // MARK: - PHPickerViewControllerDelegate

  func picker(
    _ picker: PHPickerViewController,
    didFinishPicking results: [PHPickerResult]
  ) {
    picker.dismiss(animated: true)

    guard let provider = results.first?.itemProvider,
          provider.canLoadObject(ofClass: UIImage.self)
    else {
      // Empty selection == user tapped Cancel. Resolve to nil.
      finish(success: nil)
      return
    }

    provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
      guard let self = self else { return }
      guard let image = object as? UIImage, error == nil else {
        self.finish(
          error: FlutterError(
            code: "unknown",
            message: "Could not load the selected image"
              + (error.map { ": \($0.localizedDescription)" } ?? ""),
            details: nil
          )
        )
        return
      }
      self.ioQueue.async { self.process(image: image) }
    }
  }

  // MARK: - Pipeline

  /// Detect → rectify → enhance → persist. Runs on `ioQueue`.
  private func process(image: UIImage) {
    // Bake orientation into pixels so the CIImage is upright (orientation 1);
    // the rectify pipeline reasons in top-left-origin normalized space.
    guard let upright = Self.uprightCGImage(image) else {
      finish(
        error: FlutterError(
          code: "unknown",
          message: "Could not decode the selected image",
          details: nil
        )
      )
      return
    }
    let still = CIImage(cgImage: upright)
    let stillSize = still.extent.size

    // Best document quad on the still, or the full frame when nothing
    // rectangular is found — an import should never fail to return a page.
    let detected = DocumentStillRefiner.detectBestQuad(still: still)
    let quad =
      detected ?? [
        CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
        CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
      ]

    // Identity mapping (analyzerSize == stillSize) — the quad is already in
    // still space. Echo refiner: we detected on the still directly, so there's
    // no preview seed to re-detect against.
    let output = DocumentRectifyPipeline.rectify(
      still: still,
      analyzerQuad: quad,
      analyzerSize: stillSize,
      context: DocumentEnhancer.sharedContext,
      refiner: { _, seed in DocumentStillRefinement(quad: seed, refined: false) }
    )

    let scale = image.scale
    let cropped: UIImage
    if let output = output {
      cropped = UIImage(cgImage: output.image, scale: scale, orientation: .up)
    } else {
      // Rectify failed (e.g. degenerate quad); fall back to the upright image.
      cropped = UIImage(cgImage: upright, scale: scale, orientation: .up)
    }

    // Match the branded capture path's default `.color` enhancement so an
    // imported page is visually interchangeable with a scanned one.
    let enhanced = DocumentEnhancer.enhance(cropped, filter: .color)

    guard let payload = persist(page: enhanced) else {
      finish(
        error: FlutterError(
          code: "unknown",
          message: "Could not persist the imported page",
          details: nil
        )
      )
      return
    }
    finish(success: payload)
  }

  /// Encodes `page` to a JPEG in `NSTemporaryDirectory()` and returns the
  /// channel payload (`uri`/`width`/`height` + optional quality). Returns nil
  /// on an encode/write failure.
  private func persist(page: UIImage) -> [String: Any]? {
    guard let data = page.jpegData(compressionQuality: 0.95) else { return nil }
    let stamp = ProcessInfo.processInfo.globallyUniqueString
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("supy_import_\(stamp).jpg")
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      return nil
    }
    var payload: [String: Any] = [
      "uri": url.absoluteString,
      "width": Int(page.size.width * page.scale),
      "height": Int(page.size.height * page.scale),
    ]
    if let score = SupyNativeCoreBridge.scoreImage(page) {
      if let wire = Self.bucketWire(Int(score.bucket)) { payload["quality"] = wire }
      payload["qualityScore"] = Double(score.qualityScore)
    }
    return payload
  }

  // MARK: - Helpers

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

  /// Returns a `.up`-oriented `CGImage` for `image`, redrawing when the source
  /// carries a non-`.up` EXIF orientation (as camera-roll photos usually do).
  private static func uprightCGImage(_ image: UIImage) -> CGImage? {
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

  private func finish(success payload: [String: Any]?) {
    let result = pendingResult
    pendingResult = nil
    if Thread.isMainThread {
      result?(payload)
    } else {
      DispatchQueue.main.async { result?(payload) }
    }
  }

  private func finish(error: FlutterError) {
    let result = pendingResult
    pendingResult = nil
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
