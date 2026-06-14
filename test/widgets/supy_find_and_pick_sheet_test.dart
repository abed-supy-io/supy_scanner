import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  const cola = SupyBarcode(
    rawValue: '111',
    format: SupyBarcodeFormat.ean13,
  );
  const chips = SupyBarcode(
    rawValue: '222',
    format: SupyBarcodeFormat.ean13,
  );

  SupyFindAndPickUseCaseConfiguration cfg({bool collapsed = false}) {
    return SupyFindAndPickUseCaseConfiguration(
      initiallyCollapsed: collapsed,
      expected: const [
        SupyExpectedBarcode(rawValue: '111', expectedCount: 2, label: 'Cola'),
        SupyExpectedBarcode(rawValue: '222', label: 'Chips'),
      ],
    );
  }

  Widget host({
    required SupyFindAndPickAccumulator acc,
    required SupyFindAndPickUseCaseConfiguration config,
    VoidCallback? onSubmit,
    VoidCallback? onClear,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SupyFindAndPickSheet(
            accumulator: acc,
            config: config,
            onSubmit: onSubmit ?? () {},
            onClear: onClear ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('header shows X/Y picked, rows render labels', (tester) async {
    final c = cfg();
    final acc = SupyFindAndPickAccumulator(config: c);
    await tester.pumpWidget(host(acc: acc, config: c));
    expect(find.text('Pick list'), findsOneWidget);
    expect(find.text('0/2 picked'), findsOneWidget);
    expect(find.text('Cola'), findsOneWidget);
    expect(find.text('Chips'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget); // cola counter
  });

  testWidgets('submit disabled until all rows complete', (tester) async {
    final c = cfg();
    final acc = SupyFindAndPickAccumulator(config: c);
    var submits = 0;
    await tester.pumpWidget(
      host(acc: acc, config: c, onSubmit: () => submits++),
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    acc.offer(cola);
    acc.offer(cola);
    acc.offer(chips);
    await tester.pumpAndSettle();
    expect(find.text('2/2 picked'), findsOneWidget);
    await tester.tap(find.text('Done'));
    expect(submits, 1);
  });

  testWidgets('reset fires onClear', (tester) async {
    final c = cfg();
    final acc = SupyFindAndPickAccumulator(config: c);
    var clears = 0;
    acc.offer(cola);
    await tester.pumpWidget(
      host(acc: acc, config: c, onClear: () => clears++),
    );
    await tester.tap(find.text('Reset'));
    expect(clears, 1);
  });

  testWidgets('collapsed: rows hidden until tapped', (tester) async {
    final c = cfg(collapsed: true);
    final acc = SupyFindAndPickAccumulator(config: c);
    await tester.pumpWidget(host(acc: acc, config: c));
    expect(find.text('Cola'), findsNothing);
    await tester.tap(find.text('Pick list'));
    await tester.pumpAndSettle();
    expect(find.text('Cola'), findsOneWidget);
  });
}
