import 'package:flutter/foundation.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// Opens the Phase PAID license gate for the whole example app.
///
/// Every scanning entry point calls `SupyLicenseGate.ensureActivated()` and
/// throws `SupyLicenseException` when no license is active, so — without this —
/// most catalog demos would throw the moment they run. The repo ships an
/// all-zeros placeholder verify key, so a real `SupyScanner.activate(token)`
/// can verify nothing in a dev build; the only debug-safe way to exercise the
/// scan path is the `@visibleForTesting` seam used here.
///
/// NEVER commit a real license token. This uses `SupyLicense.forTesting`, not a
/// signed token, precisely so no secret ever lands in the example source.
///
/// Gated on [kDebugMode] so a release build never force-injects a license — a
/// release example would exercise the real `activate()` path instead.
void ensureExampleLicense() {
  if (!kDebugMode) return;
  if (SupyScanner.isActivated) return;
  // ignore: invalid_use_of_visible_for_testing_member
  SupyScanner.debugSetLicense(
    // ignore: invalid_use_of_visible_for_testing_member
    SupyLicense.forTesting(
      id: 'example-catalog-debug',
      product: 'supy_scanner',
      tier: SupyLicenseTier.enterprise,
      seats: 0,
      issuedAt: DateTime.utc(2024),
      expiresAt: DateTime.utc(2099),
    ),
  );
}
