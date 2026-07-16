import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  const ean = SupyBarcode(
    rawValue: '1234567890123',
    format: SupyBarcodeFormat.ean13,
  );
  const qr = SupyBarcode(
    rawValue: 'https://supy.io',
    format: SupyBarcodeFormat.qr,
  );

  Widget host({
    required SupyMultipleScanAccumulator acc,
    required SupyMultipleScanUseCaseConfiguration cfg,
    VoidCallback? onSubmit,
    VoidCallback? onClear,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SupyMultipleScanSheet(
            accumulator: acc,
            config: cfg,
            onSubmit: onSubmit ?? () {},
            onClear: onClear ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('header shows unique count and expands to reveal rows', (
    tester,
  ) async {
    final acc = SupyMultipleScanAccumulator(
      config: const SupyMultipleScanUseCaseConfiguration(),
    );
    acc.offer(ean, now: DateTime.utc(2026));
    acc.offer(qr, now: DateTime.utc(2026));
    await tester.pumpWidget(
      host(acc: acc, cfg: const SupyMultipleScanUseCaseConfiguration()),
    );
    expect(find.text('Items scanned'), findsOneWidget);
    expect(find.text('2 unique'), findsOneWidget);
    // Starts collapsed → rows not visible
    expect(find.text('1234567890123'), findsNothing);

    await tester.tap(find.text('Items scanned'));
    await tester.pumpAndSettle();
    expect(find.text('1234567890123'), findsOneWidget);
    expect(find.text('https://supy.io'), findsOneWidget);
  });

  testWidgets('counting mode header shows scans + unique + xN badges', (
    tester,
  ) async {
    final acc = SupyMultipleScanAccumulator(
      config: const SupyMultipleScanUseCaseConfiguration(
        mode: SupyMultipleScanMode.counting,
        initiallyCollapsed: false,
      ),
    );
    final t = DateTime.utc(2026);
    acc.offer(ean, now: t);
    acc.offer(ean, now: t.add(const Duration(seconds: 2)));
    acc.offer(qr, now: t);
    await tester.pumpWidget(
      host(
        acc: acc,
        cfg: const SupyMultipleScanUseCaseConfiguration(
          mode: SupyMultipleScanMode.counting,
          initiallyCollapsed: false,
        ),
      ),
    );
    expect(find.text('3 scans · 2 unique'), findsOneWidget);
    expect(find.text('x2'), findsOneWidget);
  });

  testWidgets('submit/clear disabled when empty, enabled when items present', (
    tester,
  ) async {
    final acc = SupyMultipleScanAccumulator(
      config: const SupyMultipleScanUseCaseConfiguration(
        initiallyCollapsed: false,
      ),
    );
    var submits = 0;
    var clears = 0;
    await tester.pumpWidget(
      host(
        acc: acc,
        cfg: const SupyMultipleScanUseCaseConfiguration(
          initiallyCollapsed: false,
        ),
        onSubmit: () => submits++,
        onClear: () => clears++,
      ),
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    acc.offer(ean, now: DateTime.utc(2026));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.tap(find.text('Clear'));
    expect(submits, 1);
    expect(clears, 1);
  });
}
