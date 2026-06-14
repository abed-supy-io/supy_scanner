// H2-05: integration harness — embedded (live camera) use case.
//
// The embedded scanner mounts a real PlatformView. Headlessly the view
// falls back to its unsupported-platform placeholder so the page is still
// safe to pump in CI; native frames only flow on a connected device.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/demo/supy_demo_embedded_barcode.dart';
import 'package:supy_scanner_example/main.dart';

import 'support/runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigate: demo home → embedded barcode page', (tester) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Live Camera'));
    await tester.pumpAndSettle();

    expect(find.byType(SupyDemoEmbeddedBarcodePage), findsOneWidget);
  });

  testWidgets(
    'device-only: embedded preview reports a code via the controller',
    (tester) async {
      await tester.pumpWidget(const SupyScannerExampleApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live Camera'));
      await tester.pumpAndSettle();
      // Manual scan — assertions on the live result stream belong in
      // docs/QA.md embedded-scan scenarios.
    },
    skip: !runOnDevice,
  );
}
