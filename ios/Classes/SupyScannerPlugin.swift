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
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestCameraPermission":
      requestCameraPermission(result: result)
    case "scanDocument":
      let args = call.arguments as? [String: Any]
      documentPresenter.present(args: args, result: result)
    case "scanBarcodesBatch":
      let args = call.arguments as? [String: Any]
      batchBarcodePresenter.present(args: args, result: result)
    case "prewarm":
      documentPresenter.prewarm()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
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
