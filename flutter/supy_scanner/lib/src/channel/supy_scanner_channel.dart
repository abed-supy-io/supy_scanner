import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../licensing/supy_scanner_license.dart';
import '../models/barcode/supy_decode_image_options.dart';
import '../models/ocr/supy_recognize_text_options.dart';
import '../models/ocr/supy_recognized_text.dart';
import '../models/supy_barcode.dart';
import '../models/supy_batch_barcode_options.dart';
import '../models/supy_batch_barcode_result.dart';
import '../models/supy_document_data.dart';
import '../models/supy_document_page.dart';
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
    : _methodChannel =
          methodChannel ??
          const MethodChannel('io.supy.scanner/$kSupyScannerChannelVersion');

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
    SupyLicenseGate.ensureActivated();
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

  /// Opens the platform photo picker, runs on-device document edge-detection
  /// + perspective rectification on the chosen image natively, and returns the
  /// cropped page — or `null` if the user dismissed the picker.
  ///
  /// The whole flow (picker UI, detection, warp, persistence) is native; no
  /// image bytes cross the channel and no new Flutter plugin dependency is
  /// pulled in. Mirrors the branded capture path so an imported page is
  /// interchangeable with a camera-captured one.
  ///
  /// Pass [options] to control how the imported page is enhanced — the same
  /// [SupyDocumentScanOptions.filter] / [SupyDocumentScanOptions.enhanceMode] /
  /// [SupyDocumentScanOptions.processing] the camera path uses. When omitted,
  /// the native side applies its default paper-preserving enhancement (v1.0
  /// behaviour).
  Future<SupyDocumentPage?> importDocumentImage([
    SupyDocumentScanOptions? options,
  ]) async {
    SupyLicenseGate.ensureActivated();
    try {
      final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
        'importDocumentImage',
        options?.toWire(),
      );
      if (result == null) return null;
      return SupyDocumentPage.fromMap(result);
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
    SupyLicenseGate.ensureActivated();
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

  /// Runs a standalone OCR pass over the image at [options].imagePath and
  /// returns the recognized block/line/element tree with normalized bounding
  /// boxes.
  ///
  /// This is the foundation for the Dart-side MRZ/VIN/ID parsers — a single
  /// native method, all domain interpretation happens in `lib/`.
  Future<SupyRecognizedText> recognizeText(
    SupyRecognizeTextOptions options,
  ) async {
    SupyLicenseGate.ensureActivated();
    try {
      final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
        'recognizeText',
        options.toWire(),
      );
      if (result == null) {
        throw const SupyScanError(
          code: SupyScanErrorCode.unknown,
          message: 'recognizeText returned null',
        );
      }
      return SupyRecognizedText.fromMap(result);
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  /// Decodes every barcode in the still image at [options].imagePath and
  /// returns them in native detection order.
  ///
  /// A one-shot, camera-less decode over a file already on disk — the
  /// deterministic counterpart to the live [SupyBarcodeScannerView]. Returns an
  /// empty list when the image contains no barcode of a requested format.
  Future<List<SupyBarcode>> decodeImage(SupyDecodeImageOptions options) async {
    SupyLicenseGate.ensureActivated();
    try {
      final result = await _methodChannel.invokeListMethod<Object?>(
        'decodeImage',
        options.toWire(),
      );
      if (result == null) return const <SupyBarcode>[];
      return result
          .whereType<Map<Object?, Object?>>()
          .map(SupyBarcode.fromMap)
          .toList(growable: false);
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

  /// Returns the native C++ core's version + ABI version, or throws
  /// [SupyScanError] if the native core is not available on this build.
  ///
  /// v1.1 scaffold (see docs/V1.1_PLAN.md). Used by integration tests and
  /// the example app to verify the JNI / Swift bridge is wired correctly.
  Future<SupyNativeCoreProbe> nativeCoreProbe() async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, Object?>(
        'nativeCoreProbe',
      );
      if (raw == null) {
        throw const SupyScanError(
          code: SupyScanErrorCode.unknown,
          message: 'nativeCoreProbe returned null',
        );
      }
      final version = raw['version'] as String?;
      final abiVersion = raw['abiVersion'] as int?;
      if (version == null || version.isEmpty) {
        throw const SupyScanError(
          code: SupyScanErrorCode.unknown,
          message: 'nativeCoreProbe response is missing key "version"',
        );
      }
      if (abiVersion == null) {
        throw const SupyScanError(
          code: SupyScanErrorCode.unknown,
          message: 'nativeCoreProbe response is missing key "abiVersion"',
        );
      }
      return SupyNativeCoreProbe(
        version: version,
        abiVersion: abiVersion,
        gmsDocumentScannerAvailable:
            (raw['gmsDocumentScannerAvailable'] as bool?) ?? false,
      );
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  /// Returns the device performance tier (`high`, `mid`, or `low`) as
  /// computed by the native heuristic in `DeviceTier` (Android) /
  /// `SupyDeviceTier` (iOS).
  ///
  /// Used by the perfgate harness (`tools/perfgate/`) to pick the right
  /// baseline JSON file. Cached natively for the process lifetime.
  Future<SupyDeviceTier> getDeviceTier() async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, Object?>(
        'getDeviceTier',
      );
      return SupyDeviceTier.fromWire(raw?['tier'] as String?);
    } on PlatformException catch (e) {
      throw _wrap(e);
    }
  }

  /// Forces the native device-tier heuristic to report [tier] on all
  /// subsequent calls (analyzer downscale, FPS cap, OCR long-edge cap, idle
  /// threshold, JPEG quality clamp, `getDeviceTier()`). Pass `null` to clear.
  ///
  /// Debug-only: on release builds (`!kDebugMode`) this is a no-op and never
  /// reaches the channel. The native side additionally refuses the call on
  /// non-debuggable Android builds (`FLAG_DEBUGGABLE`) and on iOS binaries
  /// built without `#if DEBUG`.
  ///
  /// [SupyDeviceTier.unknown] is treated as a clear (same as `null`) — the
  /// override surface is write-only for the three real tiers.
  Future<void> debugForceTier(SupyDeviceTier? tier) async {
    if (!kDebugMode) return;
    final wire = switch (tier) {
      SupyDeviceTier.high => 'high',
      SupyDeviceTier.mid => 'mid',
      SupyDeviceTier.low => 'low',
      SupyDeviceTier.unknown => null,
      null => null,
    };
    try {
      await _methodChannel.invokeMethod<void>(
        'debugForceTier',
        <String, Object?>{'tier': wire},
      );
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

/// Result of a [SupyScannerChannel.nativeCoreProbe] call — exposes the
/// semver of the C++ core and the ABI version it was compiled against.
@immutable
class SupyNativeCoreProbe {
  /// Creates a native-core probe result.
  const SupyNativeCoreProbe({
    required this.version,
    required this.abiVersion,
    this.gmsDocumentScannerAvailable = false,
  });

  /// Semantic version reported by the native core (e.g. `'1.1.0-dev.1'`).
  final String version;

  /// ABI version. The Dart side currently expects `1`; mismatches indicate
  /// a stale plugin/native build pair.
  final int abiVersion;

  /// Whether the GMS ML Kit Document Scanner module is usable on this
  /// device. `true` on Android with usable Play Services + the document
  /// scanner module; `false` on non-GMS Android devices and always on iOS.
  /// v1.2 / Phase CXD1.
  final bool gmsDocumentScannerAvailable;

  @override
  String toString() =>
      'SupyNativeCoreProbe(version: $version, abiVersion: $abiVersion, '
      'gmsDocumentScannerAvailable: $gmsDocumentScannerAvailable)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyNativeCoreProbe &&
          other.version == version &&
          other.abiVersion == abiVersion &&
          other.gmsDocumentScannerAvailable == gmsDocumentScannerAvailable;

  @override
  int get hashCode =>
      Object.hash(version, abiVersion, gmsDocumentScannerAvailable);
}

/// Device performance tier reported by the native side. Mirrors
/// `io.supy.scanner.perf.DeviceTier` (Android) and `SupyDeviceTier` (iOS).
enum SupyDeviceTier {
  /// High-end devices (recent flagships).
  high,

  /// Mid-range devices — the default fallback.
  mid,

  /// Low-RAM or older devices.
  low,

  /// Tier could not be determined.
  unknown;

  /// Parses a wire-format tier string into a [SupyDeviceTier].
  static SupyDeviceTier fromWire(String? value) {
    switch (value) {
      case 'high':
        return SupyDeviceTier.high;
      case 'mid':
        return SupyDeviceTier.mid;
      case 'low':
        return SupyDeviceTier.low;
      default:
        return SupyDeviceTier.unknown;
    }
  }
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
