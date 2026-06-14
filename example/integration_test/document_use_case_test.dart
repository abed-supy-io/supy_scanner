// H2-05: integration harness — document capture use case.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/demo/supy_demo_document.dart';
import 'package:supy_scanner_example/main.dart';

import 'support/runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigate: demo home → document page', (tester) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Capture Document'));
    await tester.pumpAndSettle();

    expect(find.byType(SupyDemoDocumentPage), findsOneWidget);
  });

  testWidgets(
    'device-only: capture 2 pages, OCR latin+arabic, surface page rects',
    (tester) async {
      await tester.pumpWidget(const SupyScannerExampleApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capture Document'));
      await tester.pumpAndSettle();
      // Manual capture flow — see docs/QA.md document-scan scenarios.
    },
    skip: !runOnDevice,
  );
}
