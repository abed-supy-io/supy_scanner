import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyMultipleScanUseCaseConfiguration', () {
    test('defaults: unique mode, 1s debounce, starts collapsed', () {
      const cfg = SupyMultipleScanUseCaseConfiguration();
      expect(cfg.mode, SupyMultipleScanMode.unique);
      expect(cfg.countingRepeatDelay, const Duration(milliseconds: 1000));
      expect(cfg.initiallyCollapsed, isTrue);
      expect(cfg.submitButtonText, isNull);
      expect(cfg.clearButtonText, isNull);
    });

    test('value equality', () {
      const a = SupyMultipleScanUseCaseConfiguration(
        mode: SupyMultipleScanMode.counting,
        countingRepeatDelay: Duration(milliseconds: 500),
      );
      const b = SupyMultipleScanUseCaseConfiguration(
        mode: SupyMultipleScanMode.counting,
        countingRepeatDelay: Duration(milliseconds: 500),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs across mode', () {
      const a = SupyMultipleScanUseCaseConfiguration();
      const b = SupyMultipleScanUseCaseConfiguration(
        mode: SupyMultipleScanMode.counting,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString surfaces mode + delay', () {
      const cfg = SupyMultipleScanUseCaseConfiguration(
        mode: SupyMultipleScanMode.counting,
        countingRepeatDelay: Duration(milliseconds: 750),
      );
      expect(cfg.toString(), contains('counting'));
      expect(cfg.toString(), contains('750ms'));
    });
  });
}
