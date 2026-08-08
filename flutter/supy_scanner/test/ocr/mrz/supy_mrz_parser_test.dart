import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

// Canonical ICAO 9303 specimen MRZ lines (the "Anna Maria Eriksson" / issuing
// state "UTO" examples from Parts 4–6). Each specimen's check digits are
// published and verified by hand in the parser tests below.

const String td3Line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
const String td3Line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

const String td2Line1 = 'I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<';
const String td2Line2 = 'D231458907UTO7408122F1204159<<<<<<<6';

const String td1Line1 = 'I<UTOD231458907<<<<<<<<<<<<<<<';
const String td1Line2 = '7408122F1204159UTO<<<<<<<<<<<6';
const String td1Line3 = 'ERIKSSON<<ANNA<MARIA<<<<<<<<<<';

void main() {
  group('TD3 (passport, 2×44)', () {
    late SupyMrzDocument doc;

    setUp(() {
      doc = SupyMrzParser.parse('$td3Line1\n$td3Line2')!;
    });

    test('detects the format', () {
      expect(doc.format, SupyMrzFormat.td3);
    });

    test('decodes the identity fields', () {
      expect(doc.documentType, 'P');
      expect(doc.issuingCountry, 'UTO');
      expect(doc.surname, 'ERIKSSON');
      expect(doc.givenNames, 'ANNA MARIA');
      expect(doc.documentNumber, 'L898902C3');
      expect(doc.nationality, 'UTO');
      expect(doc.dateOfBirth, '740812');
      expect(doc.sex, SupyMrzSex.female);
      expect(doc.expiryDate, '120415');
      expect(doc.optionalData, 'ZE184226B');
    });

    test('every check digit verifies', () {
      expect(doc.documentNumberValid, isTrue);
      expect(doc.dateOfBirthValid, isTrue);
      expect(doc.expiryDateValid, isTrue);
      expect(doc.optionalDataValid, isTrue);
      expect(doc.compositeValid, isTrue);
      expect(doc.isValid, isTrue);
    });
  });

  group('TD2 (2×36)', () {
    late SupyMrzDocument doc;

    setUp(() {
      doc = SupyMrzParser.parse('$td2Line1\n$td2Line2')!;
    });

    test('detects the format', () {
      expect(doc.format, SupyMrzFormat.td2);
    });

    test('decodes the identity fields', () {
      expect(doc.documentType, 'I');
      expect(doc.issuingCountry, 'UTO');
      expect(doc.surname, 'ERIKSSON');
      expect(doc.givenNames, 'ANNA MARIA');
      expect(doc.documentNumber, 'D23145890');
      expect(doc.nationality, 'UTO');
      expect(doc.dateOfBirth, '740812');
      expect(doc.sex, SupyMrzSex.female);
      expect(doc.expiryDate, '120415');
    });

    test('check digits verify; TD2 has no optional-data digit', () {
      expect(doc.documentNumberValid, isTrue);
      expect(doc.dateOfBirthValid, isTrue);
      expect(doc.expiryDateValid, isTrue);
      expect(doc.optionalDataValid, isNull);
      expect(doc.compositeValid, isTrue);
      expect(doc.isValid, isTrue);
    });
  });

  group('TD1 (ID card, 3×30)', () {
    late SupyMrzDocument doc;

    setUp(() {
      doc = SupyMrzParser.parse('$td1Line1\n$td1Line2\n$td1Line3')!;
    });

    test('detects the format', () {
      expect(doc.format, SupyMrzFormat.td1);
    });

    test('decodes the identity fields', () {
      expect(doc.documentType, 'I');
      expect(doc.issuingCountry, 'UTO');
      expect(doc.surname, 'ERIKSSON');
      expect(doc.givenNames, 'ANNA MARIA');
      expect(doc.documentNumber, 'D23145890');
      expect(doc.nationality, 'UTO');
      expect(doc.dateOfBirth, '740812');
      expect(doc.sex, SupyMrzSex.female);
      expect(doc.expiryDate, '120415');
    });

    test('every check digit verifies', () {
      expect(doc.documentNumberValid, isTrue);
      expect(doc.dateOfBirthValid, isTrue);
      expect(doc.expiryDateValid, isTrue);
      expect(doc.compositeValid, isTrue);
      expect(doc.isValid, isTrue);
    });
  });

  group('extraction & robustness', () {
    test('finds the MRZ embedded in surrounding OCR noise', () {
      final text = [
        'PASSPORT',
        'Type P   Code UTO',
        'Surname ERIKSSON',
        td3Line1,
        td3Line2,
        'Signature',
      ].join('\n');
      final doc = SupyMrzParser.parse(text);
      expect(doc, isNotNull);
      expect(doc!.format, SupyMrzFormat.td3);
      expect(doc.surname, 'ERIKSSON');
    });

    test('tolerates stray spaces inside a line from OCR', () {
      final doc = SupyMrzParser.parse(
        '$td3Line1\n${td3Line2.substring(0, 10)}'
        ' ${td3Line2.substring(10)}',
      );
      expect(doc, isNotNull);
      expect(doc!.documentNumber, 'L898902C3');
      expect(doc.documentNumberValid, isTrue);
    });

    test('returns null when no MRZ is present', () {
      expect(SupyMrzParser.parse('just an ordinary paragraph of text'), isNull);
      expect(SupyMrzParser.parse(''), isNull);
    });

    test('flags a single bad check digit without rejecting the parse', () {
      // Corrupt the date-of-birth check digit (index 19: '2' -> '3').
      final corrupted =
          '${td3Line2.substring(0, 19)}3${td3Line2.substring(20)}';
      final doc = SupyMrzParser.parse('$td3Line1\n$corrupted');
      expect(doc, isNotNull);
      expect(doc!.dateOfBirthValid, isFalse);
      expect(doc.documentNumberValid, isTrue);
      expect(doc.isValid, isFalse);
    });
  });

  group('SupyRecognizeMrz extension', () {
    test('parses an MRZ out of a SupyRecognizedText result', () {
      const recognized = SupyRecognizedText(
        fullText: '$td3Line1\n$td3Line2',
        blocks: <SupyTextBlock>[],
      );
      final doc = recognized.parseMrz();
      expect(doc, isNotNull);
      expect(doc!.format, SupyMrzFormat.td3);
      expect(doc.isValid, isTrue);
    });

    test('returns null for text with no MRZ', () {
      const recognized = SupyRecognizedText(
        fullText: 'receipt total 12.00',
        blocks: <SupyTextBlock>[],
      );
      expect(recognized.parseMrz(), isNull);
    });
  });
}
