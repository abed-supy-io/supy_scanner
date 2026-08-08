import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

// Known-good VINs whose ISO 3780 check digits verify by hand:
//   1M8GDM9AXKP042788 — the ISO/Wikipedia canonical example (check digit 'X').
//   1HGCM82633A004352 — a widely cited Honda Accord VIN (check digit '3').
const String vinCheckX = '1M8GDM9AXKP042788';
const String vinHonda = '1HGCM82633A004352';

void main() {
  group('VIN parsing (OCR source)', () {
    test('decodes the structural sections', () {
      final vin = SupyVinParser.parse(vinHonda)!;
      expect(vin.rawValue, vinHonda);
      expect(vin.source, SupyVinSource.ocr);
      expect(vin.worldManufacturerIdentifier, '1HG');
      expect(vin.vehicleDescriptorSection, 'CM8263');
      expect(vin.vehicleIdentifierSection, '3A004352');
      expect(vin.checkDigit, '3');
      expect(vin.modelYearCode, '3');
      expect(vin.plantCode, 'A');
      expect(vin.serialNumber, '004352');
    });

    test('validates the check digit', () {
      expect(SupyVinParser.parse(vinHonda)!.isValid, isTrue);
      expect(SupyVinParser.parse(vinHonda)!.checkDigitValid, isTrue);
    });

    test('accepts X as the check digit (remainder 10)', () {
      final vin = SupyVinParser.parse(vinCheckX)!;
      expect(vin.checkDigit, 'X');
      expect(vin.checkDigitValid, isTrue);
      expect(vin.isValid, isTrue);
    });

    test('flags a wrong check digit without rejecting the parse', () {
      // Corrupt the check digit at position 9 (index 8): '3' -> '4'.
      final corrupted = vinHonda.replaceRange(8, 9, '4');
      final vin = SupyVinParser.parse(corrupted)!;
      expect(vin.isWellFormed, isTrue);
      expect(vin.checkDigitValid, isFalse);
      expect(vin.isValid, isFalse);
    });
  });

  group('extraction & robustness', () {
    test('finds a VIN embedded in surrounding OCR noise', () {
      const text = 'VEHICLE\nVIN: $vinHonda\nMake: Honda';
      final vin = SupyVinParser.parse(text);
      expect(vin, isNotNull);
      expect(vin!.rawValue, vinHonda);
      expect(vin.isValid, isTrue);
    });

    test('prefers a check-digit-valid VIN over an invalid candidate', () {
      // 17 A's is well-formed but its check digit does not verify.
      const invalid = 'AAAAAAAAAAAAAAAAA';
      final vin = SupyVinParser.parse('$invalid then $vinHonda');
      expect(vin, isNotNull);
      expect(vin!.rawValue, vinHonda);
    });

    test('ignores runs longer than 17 characters', () {
      // The VIN must not be a substring of a longer alphanumeric token.
      final vin = SupyVinParser.parse('${vinHonda}9');
      expect(vin, isNull);
    });

    test('does not match tokens containing I, O, or Q', () {
      // Replace a character with 'O' — no valid 17-char VIN run remains.
      final withO = vinHonda.replaceRange(4, 5, 'O');
      expect(SupyVinParser.parse(withO), isNull);
    });

    test('returns null when no VIN is present', () {
      expect(SupyVinParser.parse('just some ordinary text'), isNull);
      expect(SupyVinParser.parse(''), isNull);
    });
  });

  group('extensions', () {
    test('SupyRecognizeVin parses a VIN out of recognized text', () {
      const recognized = SupyRecognizedText(
        fullText: 'VIN $vinCheckX',
        blocks: <SupyTextBlock>[],
      );
      final vin = recognized.parseVin();
      expect(vin, isNotNull);
      expect(vin!.source, SupyVinSource.ocr);
      expect(vin.isValid, isTrue);
    });

    test('SupyBarcodeVin parses a VIN barcode payload', () {
      const barcode = SupyBarcode(
        rawValue: vinHonda,
        format: SupyBarcodeFormat.code39,
      );
      final vin = barcode.parseVin();
      expect(vin, isNotNull);
      expect(vin!.source, SupyVinSource.barcode);
      expect(vin.isValid, isTrue);
    });

    test('SupyBarcodeVin returns null for a non-VIN barcode', () {
      const barcode = SupyBarcode(
        rawValue: 'https://example.com',
        format: SupyBarcodeFormat.qr,
      );
      expect(barcode.parseVin(), isNull);
    });
  });
}
