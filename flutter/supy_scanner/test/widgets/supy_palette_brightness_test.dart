import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// D2-4 — dark-mode correctness. Every branded screen must render under both
/// palette brightnesses, and a single `palette:` swap must re-skin the screen
/// end-to-end. Each screen binds its `Scaffold.backgroundColor` to
/// `palette.surface`, so reading that back proves the token propagated from the
/// screen root through to the rendered chrome.
void main() {
  // `supyDark` is the library default palette; `light` is the explicit swap.
  const defaultPalette = SupyScannerPalette.supyDark();
  const light = SupyScannerPalette.scanbotLight();

  Color scaffoldSurface<T extends Widget>(WidgetTester tester) {
    final scaffold = tester.widget<Scaffold>(
      find.descendant(of: find.byType(T), matching: find.byType(Scaffold)),
    );
    return scaffold.backgroundColor!;
  }

  group('SupyBarcodeScannerScreen resolves both brightnesses', () {
    // One case per use-case variant so the sheets (which also take a palette)
    // are exercised on both brightnesses too.
    final useCases = <String, SupyScanUseCase>{
      'single': const SupySingleScanUseCase(),
      'multiple': const SupyMultipleScanUseCase(),
      'find-and-pick': const SupyFindAndPickUseCase(
        config: SupyFindAndPickUseCaseConfiguration(
          expected: [SupyExpectedBarcode(rawValue: 'A')],
        ),
      ),
    };

    for (final entry in useCases.entries) {
      testWidgets('${entry.key}: default (Supy) palette renders + propagates', (
        tester,
      ) async {
        // supyDark is the default palette, so omit it and prove the default
        // brightness resolves end-to-end.
        await tester.pumpWidget(
          MaterialApp(home: SupyBarcodeScannerScreen(useCase: entry.value)),
        );
        expect(tester.takeException(), isNull);
        expect(
          scaffoldSurface<SupyBarcodeScannerScreen>(tester),
          defaultPalette.surface,
        );
      });

      testWidgets('${entry.key}: light palette renders + re-skins', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SupyBarcodeScannerScreen(
              useCase: entry.value,
              palette: light,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        // Same screen, one token swap → light surface now drives the chrome.
        expect(
          scaffoldSurface<SupyBarcodeScannerScreen>(tester),
          light.surface,
        );
        expect(
          scaffoldSurface<SupyBarcodeScannerScreen>(tester),
          isNot(defaultPalette.surface),
        );
      });
    }
  });

  group('SupyDocumentScannerScreen resolves both brightnesses', () {
    testWidgets('default (Supy) palette renders + propagates', (tester) async {
      // supyDark is the default palette; omit it and prove the default resolves.
      await tester.pumpWidget(
        MaterialApp(home: SupyDocumentScannerScreen(onComplete: (_) {})),
      );
      expect(tester.takeException(), isNull);
      expect(
        scaffoldSurface<SupyDocumentScannerScreen>(tester),
        defaultPalette.surface,
      );
    });

    testWidgets('light palette renders + re-skins', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SupyDocumentScannerScreen(onComplete: (_) {}, palette: light),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(scaffoldSurface<SupyDocumentScannerScreen>(tester), light.surface);
      expect(
        scaffoldSurface<SupyDocumentScannerScreen>(tester),
        isNot(defaultPalette.surface),
      );
    });
  });
}
