import Flutter
import UIKit

/// Registers the embedded barcode scanner PlatformView.
///
/// View-type identifier and per-view channel scheme are defined in
/// `docs/ARCHITECTURE.md`. The Android counterpart is
/// `SupyBarcodeScannerViewFactory.kt`.
final class SupyBarcodeScannerViewFactory: NSObject, FlutterPlatformViewFactory {

  static let viewTypeId = "io.supy.scanner/v1/barcode_view"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let params = args as? [String: Any?]
    return SupyBarcodeScannerView(
      frame: frame,
      viewId: viewId,
      creationParams: params,
      messenger: messenger
    )
  }

  // Matches the Android `StandardMessageCodec` codec used by the Dart side.
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}
