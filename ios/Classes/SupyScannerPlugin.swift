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
  private let batchBarcodePresenter = BatchBarcodeScannerPresenter()

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
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestCameraPermission":
      requestCameraPermission(result: result)
    case "scanDocument":
      guard let args = Self.expectMapArgs(call, result: result) else { return }
      documentPresenter.present(args: args, result: result)
    case "scanBarcodesBatch":
      guard let args = Self.expectMapArgs(call, result: result) else { return }
      batchBarcodePresenter.present(args: args, result: result)
    case "prewarm":
      documentPresenter.prewarm()
      result(nil)
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
