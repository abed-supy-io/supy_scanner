import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

// Canonical ICAO 9303 TD3 (passport) vectors — "Anna Maria Eriksson / UTO".
const String td3Line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
const String td3Line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

// A minimal AAMVA driver's-license PDF417 payload.
const String aamvaRaw =
    '@\n\rANSI 636000090002DL00410288ZV03190008DL'
    'DCADM\n'
    'DCSDOE\n'
    'DACJOHN\n'
    'DAQD12345678\n'
    'DBB01151986\n'
    'DBA01152030\n'
    '\r';

SupyMrzDocument get _passportMrz =>
    SupyMrzParser.parse('$td3Line1\n$td3Line2')!;

SupyDriverLicenseBarcode get _driverLicense =>
    const SupyBarcode(
          rawValue: aamvaRaw,
          format: SupyBarcodeFormat.pdf417,
        ).parseDocument()!
        as SupyDriverLicenseBarcode;

void main() {
  group('composition', () {
    test('returns null when no source is supplied', () {
      expect(SupyIdParser.compose(), isNull);
    });

    test('composes a passport from an MRZ', () {
      final doc = SupyIdParser.compose(mrz: _passportMrz)!;
      expect(doc.type, SupyIdDocumentType.passport);
      expect(doc.lastName, 'ERIKSSON');
      expect(doc.firstName, 'ANNA MARIA');
      expect(doc.documentNumber, 'L898902C3');
      expect(doc.nationality, 'UTO');
      expect(doc.mrz, isNotNull);
      expect(doc.driverLicense, isNull);
    });

    test('composes a driver license from an AAMVA barcode', () {
      final doc = SupyIdParser.compose(driverLicense: _driverLicense)!;
      expect(doc.type, SupyIdDocumentType.driverLicense);
      expect(doc.lastName, 'DOE');
      expect(doc.firstName, 'JOHN');
      expect(doc.documentNumber, 'D12345678');
      expect(doc.dateOfBirth, '01151986');
      expect(doc.nationality, isNull);
    });

    test('prefers the MRZ over the driver license for shared fields', () {
      final doc =
          SupyIdParser.compose(
            mrz: _passportMrz,
            driverLicense: _driverLicense,
          )!;
      // MRZ present, so type is inferred from it and its fields win.
      expect(doc.type, SupyIdDocumentType.passport);
      expect(doc.lastName, 'ERIKSSON');
      expect(doc.documentNumber, 'L898902C3');
      // Both underlying sources remain accessible.
      expect(doc.driverLicense, isNotNull);
    });

    test('carries front-side OCR text unparsed', () {
      const front = SupyRecognizedText(
        fullText: 'REPUBLIC OF UTOPIA\nERIKSSON',
        blocks: <SupyTextBlock>[],
      );
      final doc = SupyIdParser.compose(mrz: _passportMrz, frontText: front)!;
      expect(doc.frontText, contains('REPUBLIC OF UTOPIA'));
    });
  });

  group('verification', () {
    test('a valid MRZ marks the document verified', () {
      expect(SupyIdParser.compose(mrz: _passportMrz)!.isVerified, isTrue);
    });

    test('a driver-license-only document is not verified', () {
      expect(
        SupyIdParser.compose(driverLicense: _driverLicense)!.isVerified,
        isFalse,
      );
    });
  });

  group('value semantics', () {
    test('equal documents compare equal', () {
      final a = SupyIdParser.compose(mrz: _passportMrz);
      final b = SupyIdParser.compose(mrz: _passportMrz);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing sources compare unequal', () {
      final a = SupyIdParser.compose(mrz: _passportMrz);
      final b = SupyIdParser.compose(driverLicense: _driverLicense);
      expect(a, isNot(equals(b)));
    });
  });
}
