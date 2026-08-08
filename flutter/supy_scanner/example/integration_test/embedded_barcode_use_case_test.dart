// Integration harness — embedded (live camera) use case.
//
// The embedded scanner mounts a real PlatformView. Headlessly the view falls
// back to its unsupported-platform placeholder so the page is still safe to
// pump in CI; native frames only flow on a connected device.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner_example/catalog/demos/embedded_scanner_demo.dart';

import 'support/catalog_nav.dart';
import 'support/runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigate: catalog → embedded scanner demo', (tester) async {
    await openCatalogEntry(tester, 'Embedded scanner view');

    expect(find.byType(EmbeddedScannerDemo), findsOneWidget);
  });

  testWidgets(
    'device-only: embedded preview reports a code via the controller',
    (tester) async {
      await openCatalogEntry(tester, 'Embedded scanner view');
      // Manual scan — assertions on the live result stream belong in
      // docs/QA.md embedded-scan scenarios.
    },
    skip: !runOnDevice,
  );
}
