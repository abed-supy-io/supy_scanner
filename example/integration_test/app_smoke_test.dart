// H2-05: integration harness — boot smoke.
//
// Confirms the example app boots and the four demo tiles render. This is
// the fastest signal that wiring (pubspec, theme, channel registration) is
// still healthy. Camera + native paths are exercised in the per-use-case
// drivers, gated behind `runOnDevice`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boot: demo home renders all four use-case tiles',
      (tester) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Scan Barcode'), findsOneWidget);
    expect(find.text('Batch Count'), findsOneWidget);
    expect(find.text('Live Camera'), findsOneWidget);
    expect(find.text('Capture Document'), findsOneWidget);
  });

  testWidgets('boot: developer tab bar is reachable from demo home',
      (tester) async {
    await tester.pumpWidget(const SupyScannerExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Open developer tabs'), findsOneWidget);
    await tester.tap(find.text('Open developer tabs'));
    await tester.pumpAndSettle();

    // The dev surface uses a TabBar — at least one Tab should now be in the
    // tree. Specific tab labels are an implementation detail of main.dart so
    // we don't assert on them here; that belongs in main.dart's own widget
    // test (see H2-08).
    expect(find.byType(Tab), findsWidgets);
  });
}
