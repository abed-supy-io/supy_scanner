import 'package:supy_scanner/supy_scanner.dart';

/// Injects a valid, far-future test license so the [SupyLicenseGate] lets
/// scanning entry points through. Supy Scanner is a licensed library (Phase
/// PAID, 2026-08-07) — every test that exercises a scan entry point must
/// activate first. Call from `setUp`; pair with [clearTestLicense] in
/// `tearDown` to keep the static state isolated between tests.
void activateTestLicense() {
  SupyScanner.debugSetLicense(
    SupyLicense.forTesting(
      id: 'test-license',
      product: 'supy_scanner',
      tier: SupyLicenseTier.enterprise,
      seats: 0,
      issuedAt: DateTime.utc(2024),
      expiresAt: DateTime.utc(2099),
    ),
  );
}

/// Clears any activated license. Call from `tearDown`.
void clearTestLicense() => SupyScanner.deactivate();
