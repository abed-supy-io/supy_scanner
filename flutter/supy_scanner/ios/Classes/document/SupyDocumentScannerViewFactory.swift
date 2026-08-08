import Flutter
import UIKit

/// Registers the embedded document scanner PlatformView.
///
/// View-type identifier and per-view channel scheme are defined in
/// `docs/ARCHITECTURE.md`. Mirrors `SupyBarcodeScannerViewFactory`.
final class SupyDocumentScannerViewFactory: NSObject, FlutterPlatformViewFactory {

  static let viewTypeId = "io.supy.scanner/v1/document_view"

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
    return SupyDocumentScannerView(
      frame: frame,
      viewId: viewId,
      creationParams: params,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}
