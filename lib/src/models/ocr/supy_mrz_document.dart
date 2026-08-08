import 'package:meta/meta.dart';

/// The three ICAO 9303 Machine Readable Travel Document layouts supy_scanner
/// parses: TD1 (3×30, ID cards), TD2 (2×36, older travel docs), and TD3
/// (2×44, passports).
enum SupyMrzFormat {
  /// ID-card format: three lines of 30 characters.
  td1,

  /// Two lines of 36 characters (older passports and travel documents).
  td2,

  /// Passport format: two lines of 44 characters.
  td3,
}

/// Sex field of an MRZ, per ICAO 9303 (`M`, `F`, or unspecified `<`/`X`).
enum SupyMrzSex {
  /// Male (`M`).
  male,

  /// Female (`F`).
  female,

  /// Unspecified or non-binary (`<` filler or `X`).
  unspecified,
}

/// A parsed ICAO 9303 Machine Readable Zone.
///
/// Produced by [SupyRecognizeMrz.parseMrz] over a [SupyRecognizedText] (or by
/// [SupyMrzParser.parse] over a raw text block). All string fields are the
/// decoded MRZ values with filler `<` removed; dates are kept as raw `YYMMDD`
/// strings so the caller owns the century-window policy.
///
/// Each check digit is validated independently — inspect the per-field
/// `*Valid` flags, or [isValid] for the aggregate. A `false` flag does not
/// mean the field is absent, only that its check digit did not verify (a
/// common outcome of an OCR misread).
@immutable
class SupyMrzDocument {
  /// Creates an MRZ document. Prefer [SupyMrzParser.parse] over constructing
  /// this directly.
  const SupyMrzDocument({
    required this.format,
    required this.documentType,
    required this.issuingCountry,
    required this.surname,
    required this.givenNames,
    required this.documentNumber,
    required this.nationality,
    required this.dateOfBirth,
    required this.sex,
    required this.expiryDate,
    required this.documentNumberValid,
    required this.dateOfBirthValid,
    required this.expiryDateValid,
    required this.compositeValid,
    this.optionalData,
    this.optionalData2,
    this.optionalDataValid,
    this.lines = const <String>[],
  });

  /// Which of the three ICAO layouts this document matched.
  final SupyMrzFormat format;

  /// Document type code (e.g. `P` for passport, `I`/`ID` for ID card).
  final String documentType;

  /// Three-letter issuing state/organization code.
  final String issuingCountry;

  /// Holder surname (primary identifier).
  final String surname;

  /// Holder given names (secondary identifier), space-separated.
  final String givenNames;

  /// Document number.
  final String documentNumber;

  /// Three-letter nationality code.
  final String nationality;

  /// Date of birth as the raw `YYMMDD` string from the MRZ.
  final String dateOfBirth;

  /// Holder sex.
  final SupyMrzSex sex;

  /// Expiry date as the raw `YYMMDD` string from the MRZ.
  final String expiryDate;

  /// Optional data (TD3 personal number, TD2 optional field, TD1 optional
  /// data 1). `null` when the field was pure filler.
  final String? optionalData;

  /// Second optional field, TD1 only (line 2). `null` otherwise or when pure
  /// filler.
  final String? optionalData2;

  /// Whether the document-number check digit verified.
  final bool documentNumberValid;

  /// Whether the date-of-birth check digit verified.
  final bool dateOfBirthValid;

  /// Whether the expiry-date check digit verified.
  final bool expiryDateValid;

  /// Whether the optional-data check digit verified. `null` for layouts that
  /// carry no dedicated optional-data check digit (TD1, TD2).
  final bool? optionalDataValid;

  /// Whether the composite check digit (over the concatenated key fields)
  /// verified. This is the strongest single integrity signal.
  final bool compositeValid;

  /// The normalized MRZ lines this document was parsed from, in order.
  final List<String> lines;

  /// `true` when every applicable check digit verified — the document number,
  /// both dates, the composite, and (where present) the optional-data digit.
  bool get isValid =>
      documentNumberValid &&
      dateOfBirthValid &&
      expiryDateValid &&
      compositeValid &&
      (optionalDataValid ?? true);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyMrzDocument &&
          other.format == format &&
          other.documentType == documentType &&
          other.issuingCountry == issuingCountry &&
          other.surname == surname &&
          other.givenNames == givenNames &&
          other.documentNumber == documentNumber &&
          other.nationality == nationality &&
          other.dateOfBirth == dateOfBirth &&
          other.sex == sex &&
          other.expiryDate == expiryDate &&
          other.optionalData == optionalData &&
          other.optionalData2 == optionalData2 &&
          other.documentNumberValid == documentNumberValid &&
          other.dateOfBirthValid == dateOfBirthValid &&
          other.expiryDateValid == expiryDateValid &&
          other.optionalDataValid == optionalDataValid &&
          other.compositeValid == compositeValid;

  @override
  int get hashCode => Object.hashAll([
    format,
    documentType,
    issuingCountry,
    surname,
    givenNames,
    documentNumber,
    nationality,
    dateOfBirth,
    sex,
    expiryDate,
    optionalData,
    optionalData2,
    documentNumberValid,
    dateOfBirthValid,
    expiryDateValid,
    optionalDataValid,
    compositeValid,
  ]);

  @override
  String toString() =>
      'SupyMrzDocument(${format.name}, $documentType $issuingCountry, '
      '$surname/$givenNames, doc: $documentNumber, valid: $isValid)';
}
