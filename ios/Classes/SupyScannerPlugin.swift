import AVFoundation
import Flutter
import UIKit

/// Entry point for the Supy Scanner iOS plugin.
///
/// Document OCR lands in Sprint 3 (S3-03). `scanDocument` currently returns
/// pages with an empty `ocrText` until then.
public class SupyScannerPlugin: NSObject, FlutterPlugin {

  private static let channelName = "io.supy.scanner/v1"

  private let documentPresenter = DocumentScannerPresenter()
  private let documentImportPresenter = DocumentImportPresenter()
  private let batchBarcodePresenter = BatchBarcodeScannerPresenter()
  private let ocrRunner = OcrRunner()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = SupyScannerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let factory = SupyBarcodeScannerViewFactory(messenger: registrar.messenger())
    registrar.register(
      factory,
      withId: SupyBarcodeScannerViewFactory.viewTypeId
    )

    let documentFactory = SupyDocumentScannerViewFactory(
      messenger: registrar.messenger()
    )
    registrar.register(
      documentFactory,
      withId: SupyDocumentScannerViewFactory.viewTypeId
    )

    let dataCaptureFactory = SupyDataCaptureScannerViewFactory(
      messenger: registrar.messenger()
    )
    registrar.register(
      dataCaptureFactory,
      withId: SupyDataCaptureScannerViewFactory.viewTypeId
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestCameraPermission":
      requestCameraPermission(result: result)
    case "scanDocument":
      guard let args = Self.expectMapArgs(call, result: result) else { return }
      // CQG-G3: `intent` is resolved (caller > preset > defaults) on the
      // Dart side before the wire hop. Plugin-side parsing is logged-only —
      // VisionKit multi-page is built-in (analogous to GMS), so there's no
      // native UI gate to toggle from `intent` here. Asymmetry documented
      // in `docs/ARCHITECTURE.md`.
      if let intent = args["intent"] as? String, intent != "generic" {
        SupyLog.i("scanDocument intent=\(intent) (resolved on Dart side; VisionKit owns multi-page)")
      }
      documentPresenter.present(args: args, result: result)
    case "importDocumentImage":
      // Native gallery import: PHPicker → on-device edge-detect + rectify +
      // enhance + persist. No args; resolves nil when the user dismisses the
      // picker. On-device only — no bytes cross the channel.
      documentImportPresenter.present(result: result)
    case "scanBarcodesBatch":
      guard let args = Self.expectMapArgs(call, result: result) else { return }
      batchBarcodePresenter.present(args: args, result: result)
    case "prewarm":
      documentPresenter.prewarm()
      result(nil)
    case "getDeviceTier":
      let wire: String
      switch SupyDeviceTier.detect() {
      case .high: wire = "high"
      case .mid: wire = "mid"
      case .low: wire = "low"
      }
      result(["tier": wire])
    case "debugForceTier":
      // Debug-only tier override. Dart side already gates with `kDebugMode`;
      // `#if DEBUG` is belt-and-braces so a release-built plugin binary
      // cannot honor a forged channel call.
      #if DEBUG
      let raw = (call.arguments as? [String: Any?])?["tier"] as? String
      let tier: SupyDeviceTier?
      switch raw {
      case "high": tier = .high
      case "mid": tier = .mid
      case "low": tier = .low
      case nil: tier = nil
      default:
        result(
          FlutterError(
            code: "unknown",
            message: "debugForceTier: unknown tier '\(raw ?? "nil")' (want high|mid|low|null)",
            details: nil
          )
        )
        return
      }
      SupyDeviceTier.setDebugOverride(tier)
      result(nil)
      #else
      result(nil)
      #endif
    case "parseInvoice":
      // Phase IXP — experimental, example-app-only. Dart wrapper is not
      // exported from the public barrel. Channel arg: `imagePath` (file URL
      // string of an already-captured page).
      guard let args = Self.expectMapArgs(call, result: result) else { return }
      guard let path = args["imagePath"] as? String, !path.isEmpty else {
        result(FlutterError(
          code: "unknown",
          message: "parseInvoice: missing or empty `imagePath` arg",
          details: nil
        ))
        return
      }
      let url = path.hasPrefix("file://") ? URL(string: path)! : URL(fileURLWithPath: path)
      guard let data = try? Data(contentsOf: url),
            let image = UIImage(data: data) else {
        result(FlutterError(
          code: "unknown",
          message: "parseInvoice: could not load image at \(path)",
          details: nil
        ))
        return
      }
      InvoiceParser.parse(image: image) { dict in
        result(dict)
      }
    case "recognizeText":
      guard let args = Self.expectMapArgs(call, result: result) else { return }
      guard let path = args["imagePath"] as? String, !path.isEmpty else {
        result(FlutterError(
          code: "unknown",
          message: "recognizeText: missing or empty `imagePath` arg",
          details: nil
        ))
        return
      }
      let url = path.hasPrefix("file://")
        ? URL(string: path)!
        : URL(fileURLWithPath: path)
      guard let data = try? Data(contentsOf: url),
            let image = UIImage(data: data) else {
        result(FlutterError(
          code: "model_unavailable",
          message: "recognizeText: could not load image at \(path)",
          details: nil
        ))
        return
      }
      let languages = (args["languages"] as? [String]) ?? []
      let includeElements = (args["includeElements"] as? Bool) ?? true
      ocrRunner.recognizeStructured(
        image: image,
        languages: languages,
        includeElements: includeElements
      ) { tree in
        result(tree)
      }
    case "decodeImage":
      guard let args = Self.expectMapArgs(call, result: result) else { return }
      guard let path = args["imagePath"] as? String, !path.isEmpty else {
        result(FlutterError(
          code: "unknown",
          message: "decodeImage: missing or empty `imagePath` arg",
          details: nil
        ))
        return
      }
      let url = path.hasPrefix("file://")
        ? URL(string: path)!
        : URL(fileURLWithPath: path)
      guard let data = try? Data(contentsOf: url),
            let image = UIImage(data: data) else {
        result(FlutterError(
          code: "unknown",
          message: "decodeImage: could not load image at \(path)",
          details: nil
        ))
        return
      }
      let wireFormats = (args["formats"] as? [String]) ?? []
      let useNativeCore = (args["useNativeCore"] as? Bool) ?? false
      BarcodeImageDecoder.decode(
        image: image,
        wireFormats: wireFormats,
        useNativeCore: useNativeCore
      ) { detections in
        DispatchQueue.main.async { result(detections) }
      }
    case "nativeCoreProbe":
      let version = SupyNativeCore.version()
      let abiVersion = Int(SupyNativeCore.abiVersion())
      if version.isEmpty {
        result(
          // Canonical `unknown` wire code (see
          // `lib/src/models/supy_scan_error.dart`); detail in message.
          FlutterError(
            code: "unknown",
            message: "Native core unavailable: empty version string",
            details: nil
          )
        )
      } else {
        result([
          "version": version,
          "abiVersion": abiVersion,
          // iOS uses VisionKit; the GMS ML Kit document scanner is
          // Android-only. v1.2 / Phase CXD1.
          "gmsDocumentScannerAvailable": false,
        ])
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Validates that `call.arguments` is either nil or a `[String: Any]`. A
  /// non-nil, non-dict payload means a malformed caller — surfaces the
  /// canonical `unknown` error and returns nil so the caller bails.
  private static func expectMapArgs(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) -> [String: Any]? {
    if call.arguments == nil { return [:] }
    if let dict = call.arguments as? [String: Any] { return dict }
    let actual = String(describing: type(of: call.arguments))
    result(
      FlutterError(
        code: "unknown",
        message: "\(call.method): arguments must be a [String: Any], got \(actual)",
        details: nil
      )
    )
    return nil
  }

  // MARK: - Camera permission

  private func requestCameraPermission(result: @escaping FlutterResult) {
    let current = AVCaptureDevice.authorizationStatus(for: .video)
    switch current {
    case .authorized:
      send(status: "granted", to: result)
    case .denied:
      // iOS surfaces `denied` after the user has rejected the prompt OR
      // toggled the permission off in Settings. Either way the system will
      // not re-prompt — treat as permanently denied so the consumer can
      // route the user to Settings.
      send(status: "permanentlyDenied", to: result)
    case .restricted:
      send(status: "permanentlyDenied", to: result)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        self?.send(status: granted ? "granted" : "denied", to: result)
      }
    @unknown default:
      send(status: "unknown", to: result)
    }
  }

  private func send(status: String, to result: @escaping FlutterResult) {
    let payload: [String: Any] = ["status": status]
    if Thread.isMainThread {
      result(payload)
    } else {
      DispatchQueue.main.async { result(payload) }
    }
  }
}
