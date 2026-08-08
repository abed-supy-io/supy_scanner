// Reliability harness for supy_scanner.
//
// Two scenarios:
//   1. 100x push/pop of a route containing `SupyBarcodeScannerView` — exercises
//      the native PlatformView lifecycle (attach/detach, AVCaptureSession
//      teardown on iOS, CameraX rebind on Android). Pass criterion: no
//      exceptions and the heap delta target in `docs/QA.md §B9` (<5 MB) when
//      profiled.
//   2. 50x pause/resume cycles on a single live `SupyBarcodeScannerController`
//      without dispose — guards against accumulated channel handlers or
//      retained completers.
//
// Heap-leak verification still needs Xcode Instruments / Android Studio
// Profiler against this binary; run with:
//   flutter test integration_test/reliability_harness_test.dart \
//     --profile -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '100x push/pop of SupyBarcodeScannerView completes without error',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _HarnessHome()));

      for (var i = 0; i < 100; i++) {
        await tester.tap(find.byKey(const ValueKey('push-scanner')));
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(
          find.byType(SupyBarcodeScannerView),
          findsOneWidget,
          reason: 'iteration $i — scanner did not mount',
        );

        final state = Navigator.of(tester.element(find.byType(MaterialApp)));
        state.pop();
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        expect(
          find.byType(SupyBarcodeScannerView),
          findsNothing,
          reason: 'iteration $i — scanner did not unmount',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    '50x pause/resume on a single live controller without dispose',
    (tester) async {
      final controller = SupyBarcodeScannerController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupyBarcodeScannerView(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 50; i++) {
        await controller.pause();
        await tester.pump(const Duration(milliseconds: 20));
        await controller.resume();
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(controller.paused, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _HarnessHome extends StatelessWidget {
  const _HarnessHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('push-scanner'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const _ScannerPage(),
            ),
          ),
          child: const Text('Open scanner'),
        ),
      ),
    );
  }
}

class _ScannerPage extends StatelessWidget {
  const _ScannerPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SupyBarcodeScannerView());
  }
}
