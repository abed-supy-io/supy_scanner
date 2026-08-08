import 'package:meta/meta.dart';

/// Where a [SupyVin] was read from.
enum SupyVinSource {
  /// Recognized from OCR text (a printed VIN plate or windshield label).
  ocr,

  /// Decoded from a barcode payload (Code 39 / Data Matrix VIN label).
  barcode,
}

/// A parsed ISO 3779 Vehicle Identification Number.
///
/// Produced by [SupyRecognizeVin.parseVin] over a `SupyRecognizedText` or by
/// [SupyBarcodeVin.parseVin] over a `SupyBarcode`. A VIN is 17 characters from
/// the alphabet `A–Z` (excluding `I`, `O`, `Q` to avoid `1`/`0` confusion) and
/// `0–9`, split into the world-manufacturer identifier, vehicle-descriptor
/// section, and vehicle-identifier section.
///
/// [checkDigitValid] applies the ISO 3780 transliteration/weight algorithm.
/// Note this check digit is mandatory only for North American VINs; many
/// vehicles sold elsewhere carry a well-formed VIN whose check digit does not
/// compute — inspect [isWellFormed] and [checkDigitValid] separately.
@immutable
class SupyVin {
  /// Creates a VIN. Prefer the `parseVin` extensions over constructing this
  /// directly.
  const SupyVin({
    required this.rawValue,
    required this.source,
    required this.worldManufacturerIdentifier,
    required this.vehicleDescriptorSection,
    required this.vehicleIdentifierSection,
    required this.checkDigit,
    required this.modelYearCode,
    required this.plantCode,
    required this.serialNumber,
    required this.isWellFormed,
    required this.checkDigitValid,
  });

  /// The full 17-character VIN, uppercased.
  final String rawValue;

  /// Where this VIN was read from.
  final SupyVinSource source;

  /// World Manufacturer Identifier (positions 1–3).
  final String worldManufacturerIdentifier;

  /// Vehicle Descriptor Section (positions 4–9, including the check digit).
  final String vehicleDescriptorSection;

  /// Vehicle Identifier Section (positions 10–17).
  final String vehicleIdentifierSection;

  /// The check-digit character (position 9): `0–9` or `X`.
  final String checkDigit;

  /// The raw model-year code (position 10). Left undecoded because the code
  /// repeats on a 30-year cycle — the caller owns the era policy.
  final String modelYearCode;

  /// The assembly-plant code (position 11).
  final String plantCode;

  /// The sequential production number (positions 12–17).
  final String serialNumber;

  /// Whether the value is a structurally valid VIN: exactly 17 characters, all
  /// in the VIN alphabet (`A–Z` minus `I`/`O`/`Q`, plus `0–9`).
  final bool isWellFormed;

  /// Whether the ISO 3780 check digit verifies. `false` does not necessarily
  /// mean a misread — see the class note on non-North-American VINs.
  final bool checkDigitValid;

  /// The strongest single integrity signal: well-formed *and* check-digit
  /// valid.
  bool get isValid => isWellFormed && checkDigitValid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyVin &&
          other.rawValue == rawValue &&
          other.source == source &&
          other.worldManufacturerIdentifier == worldManufacturerIdentifier &&
          other.vehicleDescriptorSection == vehicleDescriptorSection &&
          other.vehicleIdentifierSection == vehicleIdentifierSection &&
          other.checkDigit == checkDigit &&
          other.modelYearCode == modelYearCode &&
          other.plantCode == plantCode &&
          other.serialNumber == serialNumber &&
          other.isWellFormed == isWellFormed &&
          other.checkDigitValid == checkDigitValid;

  @override
  int get hashCode => Object.hash(
    rawValue,
    source,
    worldManufacturerIdentifier,
    vehicleDescriptorSection,
    vehicleIdentifierSection,
    checkDigit,
    modelYearCode,
    plantCode,
    serialNumber,
    isWellFormed,
    checkDigitValid,
  );

  @override
  String toString() =>
      'SupyVin(${source.name}, $rawValue, wmi: $worldManufacturerIdentifier, '
      'valid: $isValid)';
}
