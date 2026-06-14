// H2-05: integration harness — batch barcode use case.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/demo/supy_demo_batch_barcode.dart';
import 'package:supy_scanner_example/main.dart';

import 'support/runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigate: demo home → batch barcode page', (tester) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Batch Count'));
    await tester.pumpAndSettle();

    expect(find.byType(SupyDemoBatchBarcodePage), findsOneWidget);
  });

  testWidgets(
    'device-only: open batch scanner, collect N codes, verify dedup',
    (tester) async {
      await tester.pumpWidget(const SupyScannerExampleApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batch Count'));
      await tester.pumpAndSettle();
      // Manual scan loop — see docs/QA.md batch-scan scenarios.
    },
    skip: !runOnDevice,
  );
}
