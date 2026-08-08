import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'supy_license.dart';

/// Offline verifier for Supy Scanner license tokens.
///
/// A token is a detached-JWS-style string:
///
/// ```
/// supy-lic.v1.<base64url(payloadJson)>.<base64url(ed25519Signature)>
/// ```
///
/// The signature covers the ASCII bytes of `supy-lic.v1.<payloadB64>` (the
/// token with its final `.<sig>` segment removed). Verification is 100%
/// on-device — it never touches the network — so it is safe to run outside the
/// scanning path per the "no network in the scan path" constraint. The library
/// ships only the **public** key ([kSupyLicensePublicKeyBase64]); the matching
/// private signing key lives exclusively in the licensing backend's secrets.
class SupyLicenseVerifier {
  /// Creates a verifier. [product] is the product id the token must match.
  const SupyLicenseVerifier({this.product = 'supy_scanner'});

  /// The product id a token must declare to be accepted here.
  final String product;

  static final Ed25519 _algorithm = Ed25519();

  static const String _prefix = 'supy-lic.v1.';

  /// Verifies [token] against the embedded public key and returns the parsed
  /// [SupyLicense]. Does **not** check expiry — the caller does, so it can
  /// distinguish "expired" from "invalid".
  ///
  /// Throws [SupyLicenseException] with [SupyLicenseErrorCode.malformed],
  /// [SupyLicenseErrorCode.badSignature], or [SupyLicenseErrorCode.wrongProduct].
  Future<SupyLicense> verify(String token) async {
    final trimmed = token.trim();
    if (!trimmed.startsWith(_prefix)) {
      throw const SupyLicenseException(
        SupyLicenseErrorCode.malformed,
        'License token is missing the "supy-lic.v1." prefix.',
      );
    }

    final parts = trimmed.split('.');
    // supy-lic . v1 . <payload> . <sig>
    if (parts.length != 4 || parts[2].isEmpty || parts[3].isEmpty) {
      throw const SupyLicenseException(
        SupyLicenseErrorCode.malformed,
        'License token must have exactly four dot-separated segments.',
      );
    }

    final payloadB64 = parts[2];
    final signingInput = ascii.encode('$_prefix$payloadB64');

    final Uint8List signatureBytes;
    final Map<String, Object?> payload;
    try {
      signatureBytes = _b64urlDecode(parts[3]);
      final decoded = utf8.decode(_b64urlDecode(payloadB64));
      payload = jsonDecode(decoded) as Map<String, Object?>;
    } on FormatException catch (e) {
      throw SupyLicenseException(
        SupyLicenseErrorCode.malformed,
        'License token payload/signature is not valid base64url JSON: ${e.message}',
      );
    }

    final publicKey = SimplePublicKey(
      _b64urlDecode(kSupyLicensePublicKeyBase64),
      type: KeyPairType.ed25519,
    );
    final ok = await _algorithm.verify(
      signingInput,
      signature: Signature(signatureBytes, publicKey: publicKey),
    );
    if (!ok) {
      throw const SupyLicenseException(
        SupyLicenseErrorCode.badSignature,
        'License signature did not verify against the embedded public key.',
      );
    }

    final tokenProduct = payload['product'] as String?;
    if (tokenProduct != product) {
      throw SupyLicenseException(
        SupyLicenseErrorCode.wrongProduct,
        'License is for product "$tokenProduct", expected "$product".',
      );
    }

    return SupyLicense.verified(
      id: (payload['id'] as String?) ?? '',
      product: product,
      tier: SupyLicenseTier.fromWire(payload['tier'] as String?),
      seats: (payload['seats'] as num?)?.toInt() ?? 0,
      issuedAt: _parseEpochSeconds(payload['iat']),
      expiresAt: _parseEpochSeconds(payload['exp']),
      holder: payload['holder'] as String?,
    );
  }

  static DateTime _parseEpochSeconds(Object? value) {
    final seconds = (value as num?)?.toInt() ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static Uint8List _b64urlDecode(String value) {
    // Tolerate missing '=' padding, which base64url tokens usually omit.
    final padded = value.padRight((value.length + 3) & ~3, '=');
    return base64Url.decode(padded);
  }
}

/// Base64url-encoded Ed25519 **public** key (32 bytes) used to verify license
/// tokens on-device.
///
/// ⚠️ REPLACE THIS PLACEHOLDER before shipping. Generate a real keypair with
/// `licensing/scripts/generate-keys.mjs`; it prints the public key
/// to paste here and writes the private key to `.env` (never committed). The
/// placeholder below is all-zero bytes, so it verifies nothing — the gate stays
/// closed until a real key is pasted in.
const String kSupyLicensePublicKeyBase64 =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
