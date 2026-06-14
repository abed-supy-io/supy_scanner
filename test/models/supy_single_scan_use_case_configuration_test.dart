import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupySingleScanUseCaseConfiguration', () {
    test('defaults render confirmation sheet with submit/retry copy', () {
      const cfg = SupySingleScanUseCaseConfiguration();
      expect(cfg.confirmationSheetEnabled, isTrue);
      expect(cfg.title, 'Barcode detected');
      expect(cfg.confirmButtonText, 'Submit');
      expect(cfg.retryButtonText, 'Retry');
      expect(cfg.showBarcodeFormat, isTrue);
      expect(cfg.showRawValue, isTrue);
    });

    test('value equality', () {
      const a = SupySingleScanUseCaseConfiguration(
        title: 'Scan a product',
        confirmButtonText: 'Use',
      );
      const b = SupySingleScanUseCaseConfiguration(
        title: 'Scan a product',
        confirmButtonText: 'Use',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs when sheet disabled', () {
      const a = SupySingleScanUseCaseConfiguration();
      const b = SupySingleScanUseCaseConfiguration(
        confirmationSheetEnabled: false,
      );
      expect(a, isNot(equals(b)));
    });

    test('differs on color overrides', () {
      const a = SupySingleScanUseCaseConfiguration();
      const b = SupySingleScanUseCaseConfiguration(
        confirmButtonBackgroundColor: Color(0xFF6448C3),
      );
      expect(a, isNot(equals(b)));
    });

    test('toString carries title + sheet state', () {
      const cfg = SupySingleScanUseCaseConfiguration(title: 'Scan SKU');
      expect(cfg.toString(), contains('Scan SKU'));
      expect(cfg.toString(), contains('confirmationSheetEnabled: true'));
    });
  });
}
