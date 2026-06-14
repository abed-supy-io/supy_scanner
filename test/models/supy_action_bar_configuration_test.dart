import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyActionButtonSpec', () {
    test('value equality', () {
      const a = SupyActionButtonSpec();
      const b = SupyActionButtonSpec();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs when visibility changes', () {
      const a = SupyActionButtonSpec();
      const b = SupyActionButtonSpec(visible: false);
      expect(a, isNot(equals(b)));
    });

    test('differs when colors change', () {
      const a = SupyActionButtonSpec();
      const b = SupyActionButtonSpec(backgroundColor: Color(0xFF112233));
      expect(a, isNot(equals(b)));
    });
  });

  group('SupyActionBarConfiguration', () {
    test('value equality on default', () {
      const a = SupyActionBarConfiguration();
      const b = SupyActionBarConfiguration();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('zoomFactor must be > 0', () {
      expect(
        () => SupyActionBarConfiguration(zoomFactor: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('differs when a button spec changes', () {
      const a = SupyActionBarConfiguration();
      const b = SupyActionBarConfiguration(
        flashButton: SupyActionButtonSpec(visible: false),
      );
      expect(a, isNot(equals(b)));
    });

    test('toString carries visibility + zoomFactor', () {
      const cfg = SupyActionBarConfiguration(zoomFactor: 1.5);
      expect(cfg.toString(), contains('1.5'));
      expect(cfg.toString(), contains('visible: true'));
    });
  });
}
