import 'package:meta/meta.dart';

/// Canonical scanner error codes surfaced across both native platforms.
///
/// See `docs/ARCHITECTURE.md` "Error model" for full descriptions.
enum SupyScanErrorCode {
  /// User dismissed the scanner without a result.
  cancelled,

  /// The user denied camera permission.
  permissionDenied,

  /// No usable camera was found on the device.
  cameraUnavailable,

  /// A required on-device model (OCR / document scanner) is not available.
  modelUnavailable,

  /// A requested barcode format is not supported on this platform.
  formatUnsupported,

  /// Catch-all for unexpected native failures.
  unknown;

  /// Parses a wire-format code into the enum. Falls back to [unknown].
  static SupyScanErrorCode fromWire(String? value) {
    switch (value) {
      case 'cancelled':
        return SupyScanErrorCode.cancelled;
      case 'permission_denied':
        return SupyScanErrorCode.permissionDenied;
      case 'camera_unavailable':
        return SupyScanErrorCode.cameraUnavailable;
      case 'model_unavailable':
        return SupyScanErrorCode.modelUnavailable;
      case 'format_unsupported':
        return SupyScanErrorCode.formatUnsupported;
      default:
        return SupyScanErrorCode.unknown;
    }
  }
}

/// Error wrapper for failures crossing the platform channel.
@immutable
class SupyScanError implements Exception {
  /// Creates a scan error.
  const SupyScanError({
    required this.code,
    required this.message,
    this.details,
  });

  /// Canonical error code.
  final SupyScanErrorCode code;

  /// Human-readable message from the native side.
  final String message;

  /// Optional native-specific payload for debugging.
  final Object? details;

  @override
  String toString() => 'SupyScanError(${code.name}): $message';
}
