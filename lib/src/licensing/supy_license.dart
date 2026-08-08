import 'package:meta/meta.dart';

/// Commercial tier encoded in a Supy Scanner license.
///
/// The tier is advisory metadata for the host app (e.g. to gate premium
/// features or show plan info); the *enforcement* gate only cares that a
/// signed, unexpired license is present. See [SupyLicense].
enum SupyLicenseTier {
  /// Entry plan — single app, capped device activations.
  starter,

  /// Standard commercial plan.
  growth,

  /// Negotiated fleet plan (the retailer app rides this tier).
  enterprise,

  /// Tier could not be determined from the token.
  unknown;

  /// Parses a wire tier string. Unknown values map to [unknown].
  static SupyLicenseTier fromWire(String? value) => switch (value) {
    'starter' => SupyLicenseTier.starter,
    'growth' => SupyLicenseTier.growth,
    'enterprise' => SupyLicenseTier.enterprise,
    _ => SupyLicenseTier.unknown,
  };
}

/// A verified Supy Scanner license.
///
/// Produced only by the offline verifier after a successful Ed25519 signature
/// check against the embedded public key — construct instances directly only in
/// tests (via [SupyLicense.forTesting]). All time fields are UTC.
@immutable
class SupyLicense {
  /// Creates a license value. Prefer the verifier; use this in tests.
  @visibleForTesting
  const SupyLicense.forTesting({
    required this.id,
    required this.product,
    required this.tier,
    required this.seats,
    required this.issuedAt,
    required this.expiresAt,
    this.holder,
  });

  /// Internal constructor used by the verifier.
  const SupyLicense.verified({
    required this.id,
    required this.product,
    required this.tier,
    required this.seats,
    required this.issuedAt,
    required this.expiresAt,
    this.holder,
  });

  /// Opaque license identifier (matches the backend record).
  final String id;

  /// Product this license unlocks. The library only accepts `supy_scanner`.
  final String product;

  /// Commercial tier (advisory — see [SupyLicenseTier]).
  final SupyLicenseTier tier;

  /// Number of device activations the plan permits. `0` means unmetered.
  final int seats;

  /// When the license was issued (UTC).
  final DateTime issuedAt;

  /// When the license expires (UTC). A perpetual license uses a far-future date.
  final DateTime expiresAt;

  /// Human-readable holder (org / email), if the backend embedded one.
  final String? holder;

  /// Whether the license is expired relative to [now] (defaults to
  /// `DateTime.now()`). Compared in UTC.
  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt);

  @override
  String toString() =>
      'SupyLicense(id: $id, product: $product, tier: ${tier.name}, '
      'seats: $seats, expiresAt: ${expiresAt.toIso8601String()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyLicense &&
          other.id == id &&
          other.product == product &&
          other.tier == tier &&
          other.seats == seats &&
          other.issuedAt == issuedAt &&
          other.expiresAt == expiresAt &&
          other.holder == holder;

  @override
  int get hashCode =>
      Object.hash(id, product, tier, seats, issuedAt, expiresAt, holder);
}

/// Why a license failed to activate or why a scan was blocked.
enum SupyLicenseErrorCode {
  /// No license has been activated on this process yet.
  notActivated,

  /// The token is not in the expected `supy-lic.v1.<payload>.<sig>` shape.
  malformed,

  /// The Ed25519 signature did not verify against the embedded public key.
  badSignature,

  /// The token verified but is for a different product.
  wrongProduct,

  /// The token verified but its `exp` is in the past.
  expired,
}

/// Thrown when license activation fails, or when a scanning entry point is
/// called before a valid license is active.
///
/// This is an intentional, logged break of the historical "drop-in, no setup"
/// contract — hosts must call `SupyScanner.activate(...)` once at startup. See
/// the 2026-08-07 Phase PAID decision in `TODO.md`.
@immutable
class SupyLicenseException implements Exception {
  /// Creates a license exception.
  const SupyLicenseException(this.code, this.message);

  /// Machine-readable reason.
  final SupyLicenseErrorCode code;

  /// Human-readable explanation.
  final String message;

  @override
  String toString() => 'SupyLicenseException(${code.name}): $message';
}
