// Integration harness — boot smoke.
//
// Confirms the example app boots and the feature catalog renders. This is the
// fastest signal that wiring (pubspec, theme, channel registration) is still
// healthy. Camera + native paths are exercised in the per-use-case drivers,
// gated behind `runOnDevice`.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boot: catalog home renders with its sections', (tester) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    // App chrome.
    expect(find.text('supy_scanner catalog'), findsOneWidget);

    // Category section headers (see CatalogCategory).
    expect(find.text('Barcode'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);
    expect(find.text('OCR & Text'), findsOneWidget);
  });

  testWidgets('boot: core feature cards are present', (tester) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    // A representative card from each major area (titles come from
    // kCatalogEntries — the single source of truth for the catalog).
    expect(find.text('Embedded scanner view'), findsOneWidget);
    expect(find.text('Scan use-cases'), findsOneWidget);
    expect(find.text('Document scan'), findsOneWidget);
  });

  testWidgets('boot: debug HUD toggle is reachable from the app bar', (
    tester,
  ) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    // The catalog wraps its content in a SupyDebugHudScope, so the toggle
    // renders in the app bar. Tapping it must not throw.
    final toggle = find.byTooltip('Toggle SupyLog HUD');
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  });
}
