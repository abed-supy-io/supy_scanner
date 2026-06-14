import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyExpectedBarcode', () {
    test('defaults expectedCount to 1', () {
      const e = SupyExpectedBarcode(rawValue: 'abc');
      expect(e.expectedCount, 1);
      expect(e.label, isNull);
    });

    test('expectedCount must be >= 1', () {
      expect(
        () => SupyExpectedBarcode(rawValue: 'abc', expectedCount: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('value equality', () {
      const a = SupyExpectedBarcode(
        rawValue: 'abc',
        expectedCount: 3,
        label: 'Cola',
      );
      const b = SupyExpectedBarcode(
        rawValue: 'abc',
        expectedCount: 3,
        label: 'Cola',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SupyFindAndPickUseCaseConfiguration', () {
    test('defaults: empty list, expanded, allowUnexpected=false', () {
      const cfg = SupyFindAndPickUseCaseConfiguration();
      expect(cfg.expected, isEmpty);
      expect(cfg.initiallyCollapsed, isFalse);
      expect(cfg.allowUnexpected, isFalse);
      expect(cfg.sheetTitle, 'Pick list');
      expect(cfg.submitButtonText, 'Done');
    });

    test('value equality across expected list', () {
      const a = SupyFindAndPickUseCaseConfiguration(
        expected: [SupyExpectedBarcode(rawValue: 'x', expectedCount: 2)],
      );
      const b = SupyFindAndPickUseCaseConfiguration(
        expected: [SupyExpectedBarcode(rawValue: 'x', expectedCount: 2)],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs across expected list', () {
      const a = SupyFindAndPickUseCaseConfiguration(
        expected: [SupyExpectedBarcode(rawValue: 'x')],
      );
      const b = SupyFindAndPickUseCaseConfiguration(
        expected: [SupyExpectedBarcode(rawValue: 'y')],
      );
      expect(a, isNot(equals(b)));
    });

    test('toString surfaces row count + allowUnexpected', () {
      const cfg = SupyFindAndPickUseCaseConfiguration(
        expected: [
          SupyExpectedBarcode(rawValue: 'a'),
          SupyExpectedBarcode(rawValue: 'b'),
        ],
        allowUnexpected: true,
      );
      final s = cfg.toString();
      expect(s, contains('2 rows'));
      expect(s, contains('allowUnexpected: true'));
    });
  });
}
