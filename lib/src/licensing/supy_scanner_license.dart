import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

import 'supy_license.dart';
import 'supy_license_verifier.dart';

/// Commercial license entry point for the Supy Scanner library.
///
/// Supy Scanner is a paid, licensed library (see the 2026-08-07 Phase PAID
/// decision in `TODO.md`). Host apps must activate a license **once** at
/// startup before invoking any scanning entry point:
///
/// ```dart
/// await SupyScanner.activate(const String.fromEnvironment('SUPY_SCANNER_LICENSE'));
/// ```
///
/// Activation verifies the token fully **on-device** (offline Ed25519), so it
/// respects the "no network call in the scanning path" constraint — the network
/// is only ever touched by the host when it fetches/refreshes the token out of
/// band, never by the scanner itself.
abstract final class SupyScanner {
  static SupyLicense? _license;
  static SupyLicenseVerifier _verifier = const SupyLicenseVerifier();

  /// The currently active license, or `null` if none is active.
  static SupyLicense? get license => _license;

  /// Whether a valid, unexpired license is active on this process.
  static bool get isActivated {
    final current = _license;
    return current != null && !current.isExpiredAt(DateTime.now());
  }

  /// Verifies [licenseKey] and, on success, activates it for this process.
  ///
  /// Returns the parsed [SupyLicense]. Throws [SupyLicenseException] if the
  /// token is malformed, its signature is invalid, it is for another product,
  /// or it has already expired.
  static Future<SupyLicense> activate(String licenseKey) async {
    final verified = await _verifier.verify(licenseKey);
    if (verified.isExpiredAt(DateTime.now())) {
      throw SupyLicenseException(
        SupyLicenseErrorCode.expired,
        'License ${verified.id} expired on '
        '${verified.expiresAt.toIso8601String()}.',
      );
    }
    _license = verified;
    return verified;
  }

  /// Clears the active license. Subsequent scans throw until re-activated.
  static void deactivate() => _license = null;

  /// Test seam — inject a license without a real signed token.
  @visibleForTesting
  static void debugSetLicense(SupyLicense? license) => _license = license;

  /// Test seam — swap the verifier (e.g. to use a test keypair).
  @visibleForTesting
  static void debugSetVerifier(SupyLicenseVerifier verifier) =>
      _verifier = verifier;
}

/// Internal chokepoint every scanning entry point calls before doing work.
///
/// Kept separate from [SupyScanner] so the public surface stays small and the
/// guard can be unit-tested and reused from every launcher/facade/channel.
@internal
abstract final class SupyLicenseGate {
  /// Throws [SupyLicenseException] unless a valid, unexpired license is active.
  static void ensureActivated() {
    final current = SupyScanner.license;
    if (current == null) {
      throw const SupyLicenseException(
        SupyLicenseErrorCode.notActivated,
        'Supy Scanner is a licensed library. Call SupyScanner.activate(<key>) '
        'once at startup before scanning. See docs/MIGRATION.md.',
      );
    }
    if (current.isExpiredAt(DateTime.now())) {
      throw SupyLicenseException(
        SupyLicenseErrorCode.expired,
        'Supy Scanner license ${current.id} expired on '
        '${current.expiresAt.toIso8601String()}. Renew it and re-activate.',
      );
    }
  }
}
