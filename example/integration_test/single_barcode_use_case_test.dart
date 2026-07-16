// H2-05: integration harness — single barcode use case.
//
// Headless path: boot → tap "Scan Barcode" tile → assert destination page
// mounted. Tapping the page's "Open scanner" button fires a native call
// that throws MissingPluginException without a real plugin host, so that
// branch is gated behind `runOnDevice` and skipped in headless CI.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/demo/supy_demo_single_barcode.dart';
import 'package:supy_scanner_example/main.dart';

import 'support/runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigate: demo home → single barcode page', (tester) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan Barcode'));
    await tester.pumpAndSettle();

    expect(find.byType(SupyDemoSingleBarcodePage), findsOneWidget);
    expect(find.text('Open scanner'), findsOneWidget);
  });

  testWidgets(
    'device-only: trigger native scanner and surface a result',
    (tester) async {
      await tester.pumpWidget(const SupyScannerExampleApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan Barcode'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open scanner'));
      // On a real device the camera UI takes over here — manual scan needed.
      // Don't pumpAndSettle: native UI doesn't return synchronously.
      await tester.pump(const Duration(milliseconds: 250));

      // Headless skip prevents this from reaching the assertion. On device,
      // a tester would manually scan a sample EAN-13 — actual result-card
      // assertions go in docs/QA.md.
    },
    skip: !runOnDevice,
  );
}
