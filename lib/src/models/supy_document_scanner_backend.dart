/// Which native document scanning backend handled (or should handle) a scan.
///
/// On Android, the plugin prefers the GMS ML Kit Document Scanner when Play
/// Services are usable, and falls back to the in-process CameraX activity
/// otherwise (non-GMS markets — Huawei, unbranded ROMs). iOS only has the
/// VisionKit-backed path, which is reported as [gms] for symmetry.
///
/// See `docs/CAMERAX_FALLBACK.md` and PLAN.md Phase CXD1.
enum SupyDocumentScannerBackend {
  /// GMS ML Kit Document Scanner (Android) or VisionKit (iOS).
  gms,

  /// CameraX in-process fallback used on Android devices without usable
  /// Google Play Services.
  cameraX,

  /// Backend could not be determined.
  unknown;

  /// Wire-format value sent on the method channel.
  String get wireName {
    switch (this) {
      case SupyDocumentScannerBackend.gms:
        return 'gms';
      case SupyDocumentScannerBackend.cameraX:
        return 'cameraX';
      case SupyDocumentScannerBackend.unknown:
        return 'unknown';
    }
  }

  /// Parses a wire-format backend string into a [SupyDocumentScannerBackend].
  /// Unknown values map to [SupyDocumentScannerBackend.unknown].
  static SupyDocumentScannerBackend fromWire(String? value) {
    switch (value) {
      case 'gms':
        return SupyDocumentScannerBackend.gms;
      case 'cameraX':
        return SupyDocumentScannerBackend.cameraX;
      default:
        return SupyDocumentScannerBackend.unknown;
    }
  }
}
