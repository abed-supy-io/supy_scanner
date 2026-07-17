import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyScanUseCase variants', () {
    test('SupySingleScanUseCase equality + hashCode', () {
      const a = SupySingleScanUseCase();
      const b = SupySingleScanUseCase();
      const c = SupySingleScanUseCase(
        config: SupySingleScanUseCaseConfiguration(showRawValue: false),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('SupyMultipleScanUseCase equality + hashCode', () {
      const a = SupyMultipleScanUseCase();
      const b = SupyMultipleScanUseCase();
      const c = SupyMultipleScanUseCase(
        config: SupyMultipleScanUseCaseConfiguration(
          mode: SupyMultipleScanMode.counting,
        ),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('SupyFindAndPickUseCase equality + hashCode', () {
      const cfg = SupyFindAndPickUseCaseConfiguration(
        expected: [SupyExpectedBarcode(rawValue: 'A')],
      );
      const a = SupyFindAndPickUseCase(config: cfg);
      const b = SupyFindAndPickUseCase(config: cfg);
      const d = SupyFindAndPickUseCase(
        config: SupyFindAndPickUseCaseConfiguration(
          expected: [SupyExpectedBarcode(rawValue: 'B')],
        ),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(d)));
    });

    test('variants are mutually unequal', () {
      const s = SupySingleScanUseCase();
      const m = SupyMultipleScanUseCase();
      const f = SupyFindAndPickUseCase(
        config: SupyFindAndPickUseCaseConfiguration(
          expected: [SupyExpectedBarcode(rawValue: 'X')],
        ),
      );
      expect(s, isNot(equals(m)));
      expect(s, isNot(equals(f)));
      expect(m, isNot(equals(f)));
    });

    test('toString includes variant name', () {
      expect(
        const SupySingleScanUseCase().toString(),
        contains('SupySingleScanUseCase'),
      );
      expect(
        const SupyMultipleScanUseCase().toString(),
        contains('SupyMultipleScanUseCase'),
      );
      expect(
        const SupyFindAndPickUseCase(
          config: SupyFindAndPickUseCaseConfiguration(
            expected: [SupyExpectedBarcode(rawValue: 'A')],
          ),
        ).toString(),
        contains('SupyFindAndPickUseCase'),
      );
    });
  });

  group('SupyBarcodeScannerScreen widget tree', () {
    // Note: SupyBarcodeScannerView embeds a native PlatformView; under
    // `flutter test` the platform side is absent, so we verify the screen
    // builds without throwing and the variant-driven scaffolding lands.
    Widget host(SupyScanUseCase useCase) =>
        MaterialApp(home: SupyBarcodeScannerScreen(useCase: useCase));

    testWidgets('builds with single-scan use case', (tester) async {
      await tester.pumpWidget(host(const SupySingleScanUseCase()));
      expect(find.byType(SupyBarcodeScannerScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      // No confirmation sheet until a barcode is detected.
      expect(find.byType(SupySingleScanConfirmationSheet), findsNothing);
    });

    testWidgets('builds with multi-scan use case + shows sheet', (
      tester,
    ) async {
      await tester.pumpWidget(host(const SupyMultipleScanUseCase()));
      expect(find.byType(SupyMultipleScanSheet), findsOneWidget);
      expect(find.byType(SupyFindAndPickSheet), findsNothing);
    });

    testWidgets('builds with find-and-pick use case + shows sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SupyFindAndPickUseCase(
            config: SupyFindAndPickUseCaseConfiguration(
              expected: [SupyExpectedBarcode(rawValue: 'A')],
            ),
          ),
        ),
      );
      expect(find.byType(SupyFindAndPickSheet), findsOneWidget);
      expect(find.byType(SupyMultipleScanSheet), findsNothing);
    });

    testWidgets('owns and disposes its controller when none supplied', (
      tester,
    ) async {
      await tester.pumpWidget(host(const SupySingleScanUseCase()));
      // Remove the screen — should not throw on dispose.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not dispose externally-owned controller', (tester) async {
      final controller = SupyBarcodeScannerController();
      await tester.pumpWidget(
        MaterialApp(
          home: SupyBarcodeScannerScreen(
            useCase: const SupySingleScanUseCase(),
            controller: controller,
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // Controller is still usable — caller's responsibility to dispose.
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });
}
