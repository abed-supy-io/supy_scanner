import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyArOverlayConfiguration', () {
    test('defaults: enabled, label on, sensible stroke/radius', () {
      const cfg = SupyArOverlayConfiguration();
      expect(cfg.enabled, isTrue);
      expect(cfg.showLabel, isTrue);
      expect(cfg.strokeWidth, 2.0);
      expect(cfg.cornerRadius, 6.0);
      expect(cfg.labelTextSize, 12.0);
    });

    test('rejects negative strokeWidth', () {
      expect(
        () => SupyArOverlayConfiguration(strokeWidth: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects negative cornerRadius', () {
      expect(
        () => SupyArOverlayConfiguration(cornerRadius: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects non-positive labelTextSize', () {
      expect(
        () => SupyArOverlayConfiguration(labelTextSize: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('value equality', () {
      const a = SupyArOverlayConfiguration(
        strokeColor: Color(0xFFAA0000),
        strokeWidth: 3,
      );
      const b = SupyArOverlayConfiguration(
        strokeColor: Color(0xFFAA0000),
        strokeWidth: 3,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs across knobs', () {
      const a = SupyArOverlayConfiguration();
      const b = SupyArOverlayConfiguration(showLabel: false);
      expect(a, isNot(equals(b)));
    });
  });
}
