import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../channel/supy_scanner_channel.dart';

/// Controls a mounted `SupyTextPatternScannerView` via its per-view
/// MethodChannel.
///
/// Channel name follows `docs/ARCHITECTURE.md`:
/// `io.supy.scanner/v1/datacapture/<viewId>`.
///
/// The pattern matching itself is pure-Dart and lives on the view; this
/// controller only drives the camera (torch / pause / resume), mirroring
/// `SupyBarcodeScannerController`.
class SupyTextPatternScannerController extends ChangeNotifier {
  /// Creates a controller. It becomes usable once the widget mounts.
  SupyTextPatternScannerController();

  MethodChannel? _channel;
  bool _torchOn = false;
  bool _paused = false;

  /// Whether the torch is currently on (best-effort — last requested value).
  bool get torchOn => _torchOn;

  /// Whether the camera is currently paused (last requested value).
  bool get paused => _paused;

  /// `true` once the widget has bound this controller to a live PlatformView.
  bool get isAttached => _channel != null;

  /// Internal — called by `SupyTextPatternScannerView` on platform view
  /// creation. Not part of the public API; do not call from app code.
  @internal
  void attach(MethodChannel channel) {
    _channel = channel;
    notifyListeners();
  }

  /// Internal — called by `SupyTextPatternScannerView` when the view detaches.
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

  /// Pauses the camera preview + OCR analyzer.
  Future<void> pause() async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('pause');
    _paused = true;
    notifyListeners();
  }

  /// Resumes the camera preview + OCR analyzer.
  Future<void> resume() async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('resume');
    _paused = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _channel = null;
    super.dispose();
  }
}

/// Builds the per-view MethodChannel name for a text-pattern scanner view.
String supyDataCaptureMethodChannelName(int viewId) =>
    'io.supy.scanner/$kSupyScannerChannelVersion/datacapture/$viewId';
