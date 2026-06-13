import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/supy_batch_barcode_options.dart';
import '../models/supy_batch_barcode_result.dart';
import '../models/supy_document_data.dart';
import '../models/supy_scan_error.dart';
import '../models/supy_scan_options.dart';

/// Wire-version of the platform channel. Bump only for breaking changes
/// (parallel `v2` surface, not a mutation of `v1`).
const String kSupyScannerChannelVersion = 'v1';

/// Singleton boundary between Dart and the native scanner plugins.
///
/// All channel calls in `lib/` go through here so that argument shapes and
/// error translation live in one place.
class SupyScannerChannel {
  SupyScannerChannel._({MethodChannel? methodChannel})
      : _methodChannel = methodChannel ??
            const MethodChannel(
              'io.supy.scanner/$kSupyScannerChannelVersion',
            );

  /// Factory for tests — inject a mock [MethodChannel].
  @visibleForTesting
  factory SupyScannerChannel.test(MethodChannel methodChannel) =>
      SupyScannerChannel._(methodChannel: methodChannel);

  /// Default singleton used by the library.
  static final SupyScannerChannel instance = SupyScannerChannel._();

  final MethodChannel _methodChannel;

  /// Triggers the native multi-page document scanner.
  Future<SupyDocumentData?> scanDocument(
    SupyDocumentScanOptions options,
  ) async {
    try {
      final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
        'scanDocument',
        options.toWire(),
      );
      if (result == null) return null;
      return SupyDocumentData.fromMap(result);
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  /// Triggers the native long-lived batch barcode session.
  ///
  /// Returns `null` if the user cancelled without scanning anything. Otherwise
  /// returns a [SupyBatchBarcodeResult] with the unique items and the count of
  /// suppressed duplicates.
  Future<SupyBatchBarcodeResult?> scanBarcodesBatch(
    SupyBatchBarcodeScanOptions options,
  ) async {
    try {
      final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
        'scanBarcodesBatch',
        options.toWire(),
      );
      if (result == null) return null;
      return SupyBatchBarcodeResult.fromMap(result);
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  /// Warms up native models (e.g., downloads the GMS Document Scanner model
  /// on Android). Safe to call multiple times.
  Future<void> prewarm() async {
    try {
      await _methodChannel.invokeMethod<void>('prewarm');
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  /// Asks the OS for camera permission. Returns the resulting status.
  Future<SupyCameraPermissionStatus> requestCameraPermission() async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, Object?>(
        'requestCameraPermission',
      );
      return SupyCameraPermissionStatus.fromWire(raw?['status'] as String?);
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  static SupyScanError _wrap(PlatformException e) => SupyScanError(
        code: SupyScanErrorCode.fromWire(e.code),
        message: e.message ?? 'PlatformException without message',
        details: e.details,
      );
}

/// Outcome of a [SupyScannerChannel.requestCameraPermission] call.
enum SupyCameraPermissionStatus {
  /// Camera access has been granted by the user.
  granted,
  /// The user has denied camera access for the current session.
  denied,
  /// The user has permanently denied camera access; the host app must
  /// route them to system settings to recover.
  permanentlyDenied,
  /// Status could not be determined (typically simulators or unsupported
  /// platforms).
  unknown;

  /// Parses a native-side wire value into a [SupyCameraPermissionStatus].
  /// Unknown values map to [SupyCameraPermissionStatus.unknown].
  static SupyCameraPermissionStatus fromWire(String? value) {
    switch (value) {
      case 'granted':
        return SupyCameraPermissionStatus.granted;
      case 'denied':
        return SupyCameraPermissionStatus.denied;
      case 'permanentlyDenied':
        return SupyCameraPermissionStatus.permanentlyDenied;
      default:
        return SupyCameraPermissionStatus.unknown;
    }
  }
}
