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
///
/// The session is a two-stage flow: a branded viewfinder (solid brand bars, a
/// white shutter, an auto-capture toggle, and a page-stack thumbnail with a
/// count badge) and a page-review grid (thumbnails, delete, "Export as PDF"
/// finish). Multi accumulates in the viewfinder and the page-stack thumbnail
/// opens review; Single / Receipt advance to review after one capture.
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
    SupyDocumentScanMode mode = SupyDocumentScanMode.multi,
  }) {
    return MaterialApp(
      home: SupyDocumentScannerScreen(
        controller: controller,
        onComplete: onComplete,
        onCancel: onCancel,
        maxPages: maxPages,
        mode: mode,
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

  // Opens the review grid from the viewfinder by tapping the page-stack
  // thumbnail. Its label follows English singular/plural agreement ("1 page").
  Future<void> openReview(WidgetTester tester, int pages) async {
    final label = '$pages ${pages == 1 ? 'page' : 'pages'}';
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pump();
  }

  Finder exportButton() => find.widgetWithText(FilledButton, 'Export as PDF');

  testWidgets('multi: accumulates ordered pages; badge opens review; export '
      'returns them', (tester) async {
    await onDesktop(() async {
      wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      List<SupyDocumentPage>? completed;
      await tester.pumpWidget(
        host(controller: controller, onComplete: (p) => completed = p),
      );

      // Multi stays in the viewfinder between shots — no review yet.
      await tapShutter(tester);
      await tapShutter(tester);
      expect(exportButton(), findsNothing);

      await openReview(tester, 2);
      expect(exportButton(), findsOneWidget);

      await tester.tap(exportButton());
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

  testWidgets('single: one capture advances straight to review', (
    tester,
  ) async {
    await onDesktop(() async {
      final calls = wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      List<SupyDocumentPage>? completed;
      await tester.pumpWidget(
        host(
          controller: controller,
          onComplete: (p) => completed = p,
          mode: SupyDocumentScanMode.single,
        ),
      );

      // A single shot pauses the preview and lands on review immediately.
      await tapShutter(tester);
      expect(calls.map((c) => c.method), contains('pause'));
      expect(exportButton(), findsOneWidget);

      await tester.tap(exportButton());
      await tester.pump();

      expect(completed!.single.uri, 'file:///tmp/p1.jpg');
    });
  });

  testWidgets('finish is unreachable until at least one page exists', (
    tester,
  ) async {
    await onDesktop(() async {
      wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      var completions = 0;
      await tester.pumpWidget(
        host(controller: controller, onComplete: (_) => completions++),
      );

      // With zero pages there is no page-count badge and no way into review,
      // so the terminal export action does not exist yet.
      expect(find.bySemanticsLabel('0 pages'), findsNothing);
      expect(exportButton(), findsNothing);
      expect(completions, 0);
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

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      expect(cancelled, isTrue);
    });
  });

  testWidgets('multi: delete removes a captured page in review', (
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
      await openReview(tester, 2);

      // One delete affordance per page thumbnail.
      expect(find.byType(CircleAvatar), findsNWidgets(2));

      // Delete the first page; the second (p2) survives.
      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pump();

      await tester.tap(exportButton());
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

      await openReview(tester, 1);
      await tester.tap(exportButton());
      await tester.pump();
      expect(completed!.length, 1);
    });
  });

  testWidgets('viewfinder shows the brand chrome: title, shutter, auto-capture '
      'toggle', (tester) async {
    await onDesktop(() async {
      wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(controller: controller, onComplete: (_) {}));

      expect(find.text('Scan Document'), findsOneWidget);
      expect(find.bySemanticsLabel('Capture page'), findsOneWidget);
      expect(find.bySemanticsLabel('Auto'), findsOneWidget);
      // The removed mode tabs must not resurface.
      expect(find.text('Single'), findsNothing);
      expect(find.text('Receipt'), findsNothing);
    });
  });

  // Wires a single capture that carries the native scorer's quality bucket, so
  // the review-grid badge has something to render.
  void wireCaptureWithQuality(String quality) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'captureAndRectify') {
        return <String, Object?>{
          'path': '/tmp/p1.jpg',
          'widthPx': 101,
          'heightPx': 201,
          'quality': quality,
        };
      }
      return null;
    });
  }

  testWidgets('review grid shows the color-coded quality badge from the native '
      'score', (tester) async {
    await onDesktop(() async {
      wireCaptureWithQuality('good');
      final controller = attachedController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(
          controller: controller,
          onComplete: (_) {},
          mode: SupyDocumentScanMode.single,
        ),
      );

      // Single lands straight on review, where the badge labels the page.
      await tapShutter(tester);
      expect(exportButton(), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
    });
  });

  testWidgets('review grid omits the quality badge when the page has no score', (
    tester,
  ) async {
    await onDesktop(() async {
      // Default captures carry no `quality` key (older native / import paths).
      wireCaptures();
      final controller = attachedController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(
          controller: controller,
          onComplete: (_) {},
          mode: SupyDocumentScanMode.single,
        ),
      );

      await tapShutter(tester);
      expect(exportButton(), findsOneWidget);
      for (final label in ['Very poor', 'Poor', 'OK', 'Good', 'Excellent']) {
        expect(find.text(label), findsNothing);
      }
    });
  });
}
