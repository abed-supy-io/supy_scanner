// Integration harness — batch barcode use case.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/catalog/demos/batch_scan_demo.dart';

import 'support/catalog_nav.dart';
import 'support/runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigate: catalog → batch scan demo', (tester) async {
    await openCatalogEntry(tester, 'Batch scan');

    expect(find.byType(BatchScanDemo), findsOneWidget);
    // Session controls render while idle.
    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.text('Cap at 5'), findsOneWidget);
  });

  testWidgets(
    'device-only: open batch scanner, collect N codes, verify dedup',
    (tester) async {
      await openCatalogEntry(tester, 'Batch scan');
      // Manual scan loop — see docs/QA.md batch-scan scenarios.
    },
    skip: !runOnDevice,
  );
}
