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
  double _zoom = 1.0;
  SupyCameraPosition _cameraPosition = SupyCameraPosition.back;
  bool _minFocusDistanceLock = false;

  /// Whether the torch is currently on (best-effort — last requested value).
  bool get torchOn => _torchOn;

  /// Whether the camera is currently paused (last requested value).
  bool get paused => _paused;

  /// Last-requested zoom factor (1.0 = no zoom).
  double get zoom => _zoom;

  /// Last-requested camera position (back/front).
  SupyCameraPosition get cameraPosition => _cameraPosition;

  /// Whether the min-focus-distance lock is engaged (close-focus mode for
  /// tiny barcodes).
  bool get minFocusDistanceLock => _minFocusDistanceLock;

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

  /// Sets the camera zoom factor. `1.0` = no zoom; values are clamped by the
  /// native side to the device's supported range. The cached [zoom] reflects
  /// the actual applied (clamped) value reported by the native side.
  Future<void> setZoom(double factor) async {
    final channel = _channel;
    if (channel == null) return;
    final result = await channel.invokeMapMethod<String, Object?>(
      'setZoom',
      <String, Object?>{'factor': factor},
    );
    final applied = (result?['zoom'] as num?)?.toDouble();
    _zoom = applied ?? factor;
    notifyListeners();
  }

  /// Flips between back- and front-facing camera. Returns the position now
  /// active (the native side picks the next available lens).
  Future<SupyCameraPosition> flipCamera() async {
    final channel = _channel;
    if (channel == null) return _cameraPosition;
    final result = await channel.invokeMapMethod<String, Object?>('flipCamera');
    final wire = result?['position'] as String?;
    _cameraPosition = SupyCameraPosition._fromWire(wire) ?? _cameraPosition;
    notifyListeners();
    return _cameraPosition;
  }

  /// Engages (or disengages) close-focus mode — Scanbot's
  /// `minFocusDistanceLock`. Useful for scanning tiny barcodes held close to
  /// the lens.
  ///
  /// On platforms where the native side cannot honor this (Android v1 has no
  /// public min-focus-distance API in CameraX), the call resolves without
  /// throwing and the cached [minFocusDistanceLock] flag is left untouched so
  /// it doesn't lie to the caller.
  Future<void> setMinFocusDistanceLock({required bool on}) async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>(
        'setMinFocusDistanceLock',
        <String, Object?>{'on': on},
      );
    } on PlatformException catch (e) {
      if (e.code == 'unsupported_operation') {
        // Native side declined — don't update local state.
        return;
      }
      rethrow;
    }
    _minFocusDistanceLock = on;
    notifyListeners();
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

/// Which camera lens the scanner is using.
enum SupyCameraPosition {
  /// Rear-facing camera (default).
  back,

  /// Front-facing camera.
  front;

  static SupyCameraPosition? _fromWire(String? value) {
    switch (value) {
      case 'back':
        return SupyCameraPosition.back;
      case 'front':
        return SupyCameraPosition.front;
      default:
        return null;
    }
  }
}
