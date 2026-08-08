import 'package:meta/meta.dart';

import '../barcode/supy_barcode_document.dart';
import 'supy_mrz_document.dart';

/// The kind of identity document a [SupyIdDocument] represents.
enum SupyIdDocumentType {
  /// A passport (MRZ document type beginning with `P`).
  passport,

  /// A national identity card (MRZ document type beginning with `I`/`A`/`C`).
  idCard,

  /// A driver's license (read from an AAMVA PDF417 barcode).
  driverLicense,

  /// A visa (MRZ document type beginning with `V`).
  visa,

  /// Type could not be determined from the available sources.
  unknown,
}

/// A parsed identity document composed from one or more capture sources.
///
/// Built by [SupyIdParser.compose] from any combination of an ICAO 9303
/// [SupyMrzDocument] (passport / ID back), an AAMVA
/// [SupyDriverLicenseBarcode] (US/Canada driver's license PDF417), and
/// front-side OCR text. The [firstName]/[lastName]/[documentNumber]/
/// [dateOfBirth]/[expiryDate]/[nationality] getters are normalized across
/// sources, preferring the MRZ when present (its fields are check-digit
/// validated) and falling back to the driver's-license barcode.
///
/// Dates are returned in the winning source's raw encoding — `YYMMDD` from an
/// MRZ, or the AAMVA `DBB`/`DBA` encoding from a driver's license — because
/// neither carries an unambiguous century. The caller owns the era policy,
/// mirroring [SupyMrzDocument] and `SupyVin`.
@immutable
class SupyIdDocument {
  /// Creates an identity document. Prefer [SupyIdParser.compose] over
  /// constructing this directly.
  const SupyIdDocument({
    required this.type,
    this.mrz,
    this.driverLicense,
    this.frontText,
  });

  /// The inferred document type.
  final SupyIdDocumentType type;

  /// The ICAO 9303 machine-readable zone, if one was supplied.
  final SupyMrzDocument? mrz;

  /// The AAMVA driver's-license barcode, if one was supplied.
  final SupyDriverLicenseBarcode? driverLicense;

  /// The raw front-side OCR text (Latin), if one was supplied. Left unparsed:
  /// front layouts are country-specific, and on Android ML Kit is Latin-only.
  final String? frontText;

  /// Given name(s), preferring the MRZ.
  String? get firstName => mrz?.givenNames ?? driverLicense?.firstName;

  /// Family name, preferring the MRZ.
  String? get lastName => mrz?.surname ?? driverLicense?.lastName;

  /// Document / license number, preferring the MRZ.
  String? get documentNumber =>
      mrz?.documentNumber ?? driverLicense?.documentNumber;

  /// Date of birth in the winning source's raw encoding (see class note).
  String? get dateOfBirth => mrz?.dateOfBirth ?? driverLicense?.dateOfBirth;

  /// Expiry date in the winning source's raw encoding (see class note).
  String? get expiryDate => mrz?.expiryDate ?? driverLicense?.expiryDate;

  /// Nationality (ICAO country code). Only the MRZ carries this.
  String? get nationality => mrz?.nationality;

  /// Whether a check-digit-validated source vouches for this document. `true`
  /// only when an MRZ is present and every check digit verifies.
  bool get isVerified => mrz?.isValid ?? false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyIdDocument &&
          other.type == type &&
          other.mrz == mrz &&
          other.driverLicense == driverLicense &&
          other.frontText == frontText;

  @override
  int get hashCode => Object.hash(type, mrz, driverLicense, frontText);

  @override
  String toString() =>
      'SupyIdDocument(${type.name}, name: $firstName $lastName, '
      'doc: $documentNumber, verified: $isVerified)';
}
