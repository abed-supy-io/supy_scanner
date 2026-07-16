import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  const barcode = SupyBarcode(
    rawValue: '1234567890123',
    format: SupyBarcodeFormat.ean13,
  );

  Widget host({
    required SupySingleScanUseCaseConfiguration config,
    required VoidCallback onConfirm,
    required VoidCallback onRetry,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SupySingleScanConfirmationSheet(
          barcode: barcode,
          config: config,
          onConfirm: onConfirm,
          onRetry: onRetry,
        ),
      ),
    );
  }

  testWidgets('renders title, raw value, and format chip by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        config: const SupySingleScanUseCaseConfiguration(),
        onConfirm: () {},
        onRetry: () {},
      ),
    );
    expect(find.text('Barcode detected'), findsOneWidget);
    expect(find.text('1234567890123'), findsOneWidget);
    expect(find.text('ean13'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping Submit fires onConfirm', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      host(
        config: const SupySingleScanUseCaseConfiguration(),
        onConfirm: () => confirmed++,
        onRetry: () {},
      ),
    );
    await tester.tap(find.text('Submit'));
    expect(confirmed, 1);
  });

  testWidgets('tapping Retry fires onRetry', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      host(
        config: const SupySingleScanUseCaseConfiguration(),
        onConfirm: () {},
        onRetry: () => retried++,
      ),
    );
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('hides format chip and raw value when configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        config: const SupySingleScanUseCaseConfiguration(
          showBarcodeFormat: false,
          showRawValue: false,
        ),
        onConfirm: () {},
        onRetry: () {},
      ),
    );
    expect(find.text('ean13'), findsNothing);
    expect(find.text('1234567890123'), findsNothing);
    expect(find.text('Barcode detected'), findsOneWidget);
  });
}
