import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../channel/supy_scanner_channel.dart';
import '../models/supy_barcode_format.dart';

/// Controls a mounted `SupyBarcodeScannerView` via its per-view MethodChannel.
///
/// Channel name follows `docs/ARCHITECTURE.md`:
/// `io.supy.scanner/v1/barcode/<viewId>`.
///
/// Construct one and pass it to `SupyBarcodeScannerView(controller: ...)`. Use
/// [setTorch] / [pause] / [resume] / [setFormats] from your app code.
class SupyBarcodeScannerController extends ChangeNotifier {
  /// Creates a controller. It becomes usable once the widget mounts.
  SupyBarcodeScannerController();

  MethodChannel? _channel;
  bool _torchOn = false;
  bool _paused = false;

  /// Whether the torch is currently on (best-effort — last requested value).
  bool get torchOn => _torchOn;

  /// Whether the camera is currently paused (last requested value).
  bool get paused => _paused;

  /// `true` once the widget has bound this controller to a live PlatformView.
  bool get isAttached => _channel != null;

  /// Internal — called by `SupyBarcodeScannerView` on platform view creation.
  /// Not part of the public API; do not call from app code.
  @internal
  void attach(MethodChannel channel) {
    _channel = channel;
    notifyListeners();
  }

  /// Internal — called by `SupyBarcodeScannerView` when the view is detached.
  @internal
  void detach() {
    _channel = null;
  }

  /// Toggles the torch / flash on the active camera.
  Future<void> setTorch({required bool on}) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('setTorch', <String, Object?>{'on': on});
    _torchOn = on;
    notifyListeners();
  }

  /// Pauses the camera preview + analyzer.
  Future<void> pause() async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('pause');
    _paused = true;
    notifyListeners();
  }

  /// Resumes the camera preview + analyzer.
  Future<void> resume() async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('resume');
    _paused = false;
    notifyListeners();
  }

  /// Updates the active barcode formats. Empty list (or `all`) restores the
  /// default detector.
  Future<void> setFormats(List<SupyBarcodeFormat> formats) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>(
      'setFormats',
      <String, Object?>{
        'formats': formats.map((f) => f.wireName).toList(growable: false),
      },
    );
  }

  @override
  void dispose() {
    _channel = null;
    super.dispose();
  }
}

/// Builds the per-view MethodChannel name.
String supyBarcodeMethodChannelName(int viewId) =>
    'io.supy.scanner/$kSupyScannerChannelVersion/barcode/$viewId';
