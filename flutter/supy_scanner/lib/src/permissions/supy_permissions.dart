import '../channel/supy_scanner_channel.dart';

/// Camera-permission entry point for consumers.
///
/// Wraps the platform's native runtime permission flow. On iOS this prompts
/// once (`AVCaptureDevice.requestAccess`); subsequent calls resolve with the
/// current status without re-prompting. On Android this triggers a
/// `requestPermissions` dialog when the permission is in the `denied`
/// (but not permanently-denied) state.
final class SupyPermissions {
  const SupyPermissions._();

  /// Requests camera access. Safe to call when the permission is already
  /// granted — returns `granted` immediately.
  static Future<SupyCameraPermissionStatus> requestCamera() {
    return SupyScannerChannel.instance.requestCameraPermission();
  }
}
