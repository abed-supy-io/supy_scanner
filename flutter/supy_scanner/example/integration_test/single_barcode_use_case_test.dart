// Integration harness — barcode scan use-cases.
//
// Headless path: boot → open the "Scan use-cases" catalog card → assert the
// destination demo mounted and its use-case list renders. Launching a use-case
// pushes the native scanner screen, which throws MissingPluginException
// without a real plugin host, so that branch is gated behind `runOnDevice` and
// skipped in headless CI.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/catalog/demos/use_cases_demo.dart';

import 'support/catalog_nav.dart';
import 'support/runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigate: catalog → scan use-cases demo', (tester) async {
    await openCatalogEntry(tester, 'Scan use-cases');

    expect(find.byType(UseCasesDemo), findsOneWidget);
    // The demo lists the Scanbot-parity use-cases behind a palette switch.
    expect(find.text('Single scan'), findsOneWidget);
    expect(find.text('Find and pick'), findsOneWidget);
  });

  testWidgets('device-only: launch a use-case and surface a result', (
    tester,
  ) async {
    await openCatalogEntry(tester, 'Scan use-cases');
    await tester.tap(find.text('Single scan'));
    // On a real device the camera UI takes over here — manual scan needed.
    // Don't pumpAndSettle: the native UI doesn't return synchronously.
    await tester.pump(const Duration(milliseconds: 250));

    // Headless skip prevents this from reaching a scan. On device, a tester
    // would manually scan a sample EAN-13 — result-card assertions live in
    // docs/QA.md.
  }, skip: !runOnDevice);
}
