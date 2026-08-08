// Integration harness — document capture use case.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/catalog/demos/document_scan_demo.dart';

import 'support/catalog_nav.dart';
import 'support/runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigate: catalog → document scan demo', (tester) async {
    await openCatalogEntry(tester, 'Document scan');

    expect(find.byType(DocumentScanDemo), findsOneWidget);
  });

  testWidgets('filter picker exposes all four SupyDocumentFilter segments', (
    tester,
  ) async {
    await openCatalogEntry(tester, 'Document scan');

    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Gray'), findsOneWidget);
    expect(find.text('B&W'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);

    // Tapping a segment must not throw — the picker is interactive while idle.
    await tester.tap(find.text('B&W'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'device-only: capture 2 pages, OCR latin+arabic, surface page rects',
    (tester) async {
      await openCatalogEntry(tester, 'Document scan');
      // Manual capture flow — see docs/QA.md document-scan scenarios.
    },
    skip: !runOnDevice,
  );
}
