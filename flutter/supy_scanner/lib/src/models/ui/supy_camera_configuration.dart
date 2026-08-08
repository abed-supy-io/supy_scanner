import 'package:meta/meta.dart';

/// Effective scan range — biases the camera/detector toward short-range or
/// long-range targets. Mirrors Scanbot's `cameraConfiguration.scanRange`.
enum SupyScanRange {
  /// Standard mid-range scanning (default).
  standard,

  /// Close-focus mode for tiny barcodes held near the lens.
  close,

  /// Long-range mode — pairs with the v1.1 native core's super-resolution
  /// path when `useNativeCore` is on. Without the native core, the host
  /// falls back to `standard`.
  extended;

  /// Wire-format string sent over the channel.
  String get wireName => switch (this) {
    SupyScanRange.standard => 'standard',
    SupyScanRange.close => 'close',
    SupyScanRange.extended => 'extended',
  };
}

/// Camera-level configuration applied at preview-start.
///
/// Mirrors Scanbot's `cameraConfiguration` block. Applied via the
/// PlatformView creation params so the native side can pick the right lens
/// and apply zoom / focus before the first frame.
@immutable
class SupyCameraConfiguration {
  /// Creates a camera configuration.
  const SupyCameraConfiguration({
    this.initialZoom = 1.0,
    this.minFocusDistanceLock = false,
    this.scanRange = SupyScanRange.standard,
  }) : assert(initialZoom > 0, 'initialZoom must be > 0');

  /// Zoom factor applied at preview-start (`1.0` = no zoom). Clamped natively
  /// to the device's supported range.
  final double initialZoom;

  /// When `true`, engages close-focus mode at preview-start. Equivalent to
  /// calling `SupyBarcodeScannerController.setMinFocusDistanceLock(on: true)`
  /// immediately after the camera comes up.
  final bool minFocusDistanceLock;

  /// Effective scan range bias. See [SupyScanRange].
  final SupyScanRange scanRange;

  /// Serializes to the channel argument shape.
  Map<String, Object?> toWire() => {
    'initialZoom': initialZoom,
    'minFocusDistanceLock': minFocusDistanceLock,
    'scanRange': scanRange.wireName,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyCameraConfiguration &&
          other.initialZoom == initialZoom &&
          other.minFocusDistanceLock == minFocusDistanceLock &&
          other.scanRange == scanRange;

  @override
  int get hashCode => Object.hash(initialZoom, minFocusDistanceLock, scanRange);

  @override
  String toString() =>
      'SupyCameraConfiguration(initialZoom: $initialZoom, '
      'minFocusDistanceLock: $minFocusDistanceLock, '
      'scanRange: ${scanRange.wireName})';
}
