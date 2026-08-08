import '../../models/ocr/supy_recognized_text.dart';
import '../../models/ocr/supy_vin.dart';
import '../../models/supy_barcode.dart';

/// Extracts and validates ISO 3779 Vehicle Identification Numbers.
///
/// A VIN is a contiguous 17-character run over the VIN alphabet (`A–Z` minus
/// `I`/`O`/`Q`, plus `0–9`). This is a pure-Dart, on-device pass; it does no
/// I/O and never mutates its input. The VIN alphabet is Latin, so it works on
/// both iOS Vision and Android ML Kit.
abstract final class SupyVinParser {
  /// A standalone 17-character VIN token: VIN-alphabet only, not part of a
  /// longer alphanumeric run.
  static final RegExp _vinToken = RegExp(
    r'(?<![A-Z0-9])[A-HJ-NPR-Z0-9]{17}(?![A-Z0-9])',
  );

  /// ISO 3780 weights for positions 1–17 (position 9, the check digit, is 0).
  static const List<int> _weights = [
    8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2, //
  ];

  /// Parses the first VIN found in [text], preferring one whose check digit
  /// verifies. Returns `null` when no 17-character VIN token is present.
  static SupyVin? parse(
    String text, {
    SupyVinSource source = SupyVinSource.ocr,
  }) {
    final upper = text.toUpperCase();
    SupyVin? fallback;
    for (final match in _vinToken.allMatches(upper)) {
      final vin = _build(match.group(0)!, source);
      if (vin.checkDigitValid) return vin;
      fallback ??= vin;
    }
    return fallback;
  }

  static SupyVin _build(String vin, SupyVinSource source) {
    return SupyVin(
      rawValue: vin,
      source: source,
      worldManufacturerIdentifier: vin.substring(0, 3),
      vehicleDescriptorSection: vin.substring(3, 9),
      vehicleIdentifierSection: vin.substring(9, 17),
      checkDigit: vin[8],
      modelYearCode: vin[9],
      plantCode: vin[10],
      serialNumber: vin.substring(11, 17),
      isWellFormed: true,
      checkDigitValid: _verifyCheckDigit(vin),
    );
  }

  /// Transliterated value of a VIN character (ISO 3780): `0–9` → 0–9;
  /// `A–H`→1–8, `J–N`→1–5, `P`→7, `R`→9, `S–Z`→2–9. Returns `-1` for `I`/`O`/`Q`
  /// or any non-VIN character.
  static int _transliterate(String c) {
    final code = c.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) return code - 0x30; // 0–9
    switch (c) {
      case 'A':
      case 'J':
        return 1;
      case 'B':
      case 'K':
      case 'S':
        return 2;
      case 'C':
      case 'L':
      case 'T':
        return 3;
      case 'D':
      case 'M':
      case 'U':
        return 4;
      case 'E':
      case 'N':
      case 'V':
        return 5;
      case 'F':
      case 'W':
        return 6;
      case 'G':
      case 'P':
      case 'X':
        return 7;
      case 'H':
      case 'Y':
        return 8;
      case 'R':
      case 'Z':
        return 9;
      default:
        return -1; // I, O, Q, or non-alphanumeric
    }
  }

  /// Verifies the ISO 3780 check digit at position 9. `X` encodes a remainder
  /// of 10.
  static bool _verifyCheckDigit(String vin) {
    if (vin.length != 17) return false;
    var sum = 0;
    for (var i = 0; i < 17; i++) {
      final v = _transliterate(vin[i]);
      if (v < 0) return false;
      sum += v * _weights[i];
    }
    final remainder = sum % 11;
    final expected = remainder == 10 ? 'X' : '$remainder';
    return vin[8] == expected;
  }
}

/// Adds opt-in VIN parsing to a `SupyRecognizedText` OCR result.
extension SupyRecognizeVin on SupyRecognizedText {
  /// Interprets the recognized text as an ISO 3779 VIN, or returns `null` if
  /// no 17-character VIN is present. Pure-Dart, on-device, non-mutating.
  SupyVin? parseVin() => SupyVinParser.parse(fullText);
}

/// Adds opt-in VIN parsing to a decoded [SupyBarcode] (Code 39 / Data Matrix
/// VIN labels).
extension SupyBarcodeVin on SupyBarcode {
  /// Interprets [SupyBarcode.rawValue] as an ISO 3779 VIN, or returns `null`
  /// if it holds no 17-character VIN. Tags the result [SupyVinSource.barcode].
  SupyVin? parseVin() =>
      SupyVinParser.parse(rawValue, source: SupyVinSource.barcode);
}
