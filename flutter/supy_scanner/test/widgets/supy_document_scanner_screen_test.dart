import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// The branded session screen is driven through its manual shutter, which
/// calls `controller.captureAndRectify()`. We attach an external controller to
/// a mock channel so the shutter resolves against canned capture payloads, and
/// force the embedded preview onto its desktop placeholder branch so it never
/// spins up a native PlatformView (or re-attaches the controller to a real
/// channel). `debugDefaultTargetPlatformOverride` is checked by the framework's
/// invariant pass, which runs BEFORE `addTearDown`, so we restore it inline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1/document/test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Records every method call and returns a distinct capture per shutter tap
  /// (`/tmp/p1.jpg`, `/tmp/p2.jpg`, …) so page ordering is observable.
  List<MethodCall> wireCaptures() {
    final calls = <MethodCall>[];
    var n = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'captureAndRectify') {
        n++;
        return <String, Object?>{
          'path': '/tmp/p$n.jpg',
          'widthPx': 100 + n,
          'heightPx': 200 + n,
        };
      }
      return null; // pause / resume / setTorch
    });
    return calls;
  }

  Future<void> onDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  SupyDocumentScannerController attachedController() {
    final controller = SupyDocumentScannerController();
    controller.attach(channel);
    return controller;
  }

  Widget host({
    required SupyDocumentScannerController controller,
    required ValueChanged<List<SupyDocumentPage>> onComplete,
    VoidCallback? onCancel,
    int maxPages = 0,
  }) {
    return MaterialApp(
      home: SupyDocumentScannerScreen(
        controller: controller,
        onComplete: onComplete,
        onCancel: onCancel,
        maxPages: maxPages,
      ),
    );
  }

  // Two pumps: one to flush the mock channel round-trip, one for the setState
  // rebuild. pumpAndSettle is avoided — the preview's pulse animation repeats.
  Future<void> tapShutter(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Capture page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('accumulates captures into ordered pages and completes on Done', (
    tester,
  ) async {
    await onDesktop(() async {
      wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      List<SupyDocumentPage>? completed;
      await tester.pumpWidget(
        host(controller: controller, onComplete: (p) => completed = p),
      );

      await tapShutter(tester);
      await tapShutter(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pump();

      expect(completed, isNotNull);
      expect(completed!.map((p) => p.uri), <String>[
        'file:///tmp/p1.jpg',
        'file:///tmp/p2.jpg',
      ]);
      expect(completed!.first.width, 101);
      expect(completed!.first.height, 201);
    });
  });

  testWidgets('Done is inert until at least one page exists', (tester) async {
    await onDesktop(() async {
      wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      var completions = 0;
      await tester.pumpWidget(
        host(controller: controller, onComplete: (_) => completions++),
      );

      // Tapping the disabled Done button is a no-op.
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pump();
      expect(completions, 0);

      await tapShutter(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pump();
      expect(completions, 1);
    });
  });

  testWidgets('Cancel invokes onCancel', (tester) async {
    await onDesktop(() async {
      wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      var cancelled = false;
      await tester.pumpWidget(
        host(
          controller: controller,
          onComplete: (_) {},
          onCancel: () => cancelled = true,
        ),
      );

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();
      expect(cancelled, isTrue);
    });
  });

  testWidgets('delete removes a captured page from the tray', (tester) async {
    await onDesktop(() async {
      wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      List<SupyDocumentPage>? completed;
      await tester.pumpWidget(
        host(controller: controller, onComplete: (p) => completed = p),
      );

      await tapShutter(tester);
      await tapShutter(tester);
      expect(
        find.byType(CircleAvatar),
        findsNWidgets(2),
      ); // one delete per page

      // Delete the first page; the second (p2) survives.
      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pump();

      expect(completed!.single.uri, 'file:///tmp/p2.jpg');
    });
  });

  testWidgets('respects maxPages — pauses preview and blocks further capture '
      'at the cap', (tester) async {
    await onDesktop(() async {
      final calls = wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      List<SupyDocumentPage>? completed;
      await tester.pumpWidget(
        host(
          controller: controller,
          onComplete: (p) => completed = p,
          maxPages: 1,
        ),
      );

      await tapShutter(tester);
      // Reaching the cap pauses the preview.
      expect(calls.map((c) => c.method), contains('pause'));

      // A second shutter tap while capped is inert (button disabled).
      await tapShutter(tester);
      expect(
        calls.where((c) => c.method == 'captureAndRectify').length,
        1,
        reason: 'only one capture reached the channel at maxPages: 1',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pump();
      expect(completed!.length, 1);
    });
  });
}
