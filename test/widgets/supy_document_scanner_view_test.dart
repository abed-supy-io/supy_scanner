import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// Force the view onto the desktop "unsupported" branch so its preview
/// renders the placeholder instead of an unregistered native PlatformView.
/// The overlay (hint card / header / footer) is drawn in a Stack on top of
/// the preview, so it is fully exercisable on this branch.
///
/// IMPORTANT: `debugDefaultTargetPlatformOverride` is checked by the test
/// framework's invariant pass, which runs BEFORE `addTearDown` callbacks.
/// We therefore restore it inline at the end of each test body — failing to
/// do so causes "foundation debug variable was changed by the test".
typedef _Body = Future<void> Function();

Future<void> _onDesktop(_Body body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('SupyDocumentScannerView build', () {
    testWidgets('shows noDocument hint initially', (tester) async {
      await _onDesktop(() async {
        await tester.pumpWidget(host(const SupyDocumentScannerView()));
        expect(find.text('Searching for document…'), findsOneWidget);
      });
    });

    testWidgets('hides overlay + hint when showOverlay=false', (tester) async {
      await _onDesktop(() async {
        await tester.pumpWidget(
          host(const SupyDocumentScannerView(showOverlay: false)),
        );
        expect(find.text('Searching for document…'), findsNothing);
      });
    });

    testWidgets('renders custom header and footer widgets', (tester) async {
      await _onDesktop(() async {
        await tester.pumpWidget(
          host(
            const SupyDocumentScannerView(
              header: Text('HEAD'),
              footer: Text('FOOT'),
            ),
          ),
        );
        expect(find.text('HEAD'), findsOneWidget);
        expect(find.text('FOOT'), findsOneWidget);
      });
    });

    testWidgets('falls back to placeholder on unsupported desktop platforms',
        (tester) async {
      await _onDesktop(() async {
        await tester.pumpWidget(host(const SupyDocumentScannerView()));
        expect(find.textContaining('not yet supported'), findsOneWidget);
      });
    });

    testWidgets('rebuild with new guidance replaces hint copy',
        (tester) async {
      await _onDesktop(() async {
        await tester.pumpWidget(host(const SupyDocumentScannerView()));
        expect(find.text('Searching for document…'), findsOneWidget);

        await tester.pumpWidget(
          host(
            const SupyDocumentScannerView(
              guidance: SupyDocumentGuidanceConfiguration(
                hints: SupyDocumentGuidanceHints(
                  noDocument: 'NEEDS DOC',
                ),
              ),
            ),
          ),
        );
        // Hint card uses AnimatedSwitcher — settle the cross-fade before
        // asserting the outgoing copy is gone.
        await tester.pumpAndSettle();
        expect(find.text('NEEDS DOC'), findsOneWidget);
        expect(find.text('Searching for document…'), findsNothing);
      });
    });

    testWidgets('disposes cleanly without an attached controller',
        (tester) async {
      await _onDesktop(() async {
        await tester.pumpWidget(host(const SupyDocumentScannerView()));
        await tester.pumpWidget(host(const SizedBox()));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('SupyDocumentScannerView capture-phase overlay', () {
    testWidgets('controller.setCapturePhase(capturing) overlays Capturing… hint',
        (tester) async {
      await _onDesktop(() async {
        final controller = SupyDocumentScannerController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          host(SupyDocumentScannerView(controller: controller)),
        );
        expect(find.text('Searching for document…'), findsOneWidget);

        controller.setCapturePhase(SupyDocumentCapturePhase.capturing);
        await tester.pumpAndSettle();
        expect(find.text('Capturing…'), findsOneWidget);
        expect(find.text('Searching for document…'), findsNothing);

        controller.setCapturePhase(SupyDocumentCapturePhase.captured);
        await tester.pumpAndSettle();
        expect(find.text('Captured!'), findsOneWidget);

        controller.setCapturePhase(SupyDocumentCapturePhase.idle);
        await tester.pumpAndSettle();
        expect(find.text('Searching for document…'), findsOneWidget);
      });
    });

    testWidgets('capturing/captured paint with readyColor', (tester) async {
      await _onDesktop(() async {
        const cfg = SupyDocumentGuidanceConfiguration(
          readyColor: Color(0xFF112233),
        );
        final controller = SupyDocumentScannerController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          host(SupyDocumentScannerView(
            controller: controller,
            guidance: cfg,
          )),
        );

        controller.setCapturePhase(SupyDocumentCapturePhase.capturing);
        await tester.pumpAndSettle();

        final container = tester.widget<Container>(
          find.ancestor(
            of: find.text('Capturing…'),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(
          (decoration.border! as Border).top.color.toARGB32(),
          const Color(0xFF112233).toARGB32(),
        );
      });
    });
  });

  group('SupyDocumentScannerView color routing via guidance', () {
    testWidgets('hint card border uses notReadyColor while no document',
        (tester) async {
      await _onDesktop(() async {
        const cfg = SupyDocumentGuidanceConfiguration(
          notReadyColor: Color(0xFFAABBCC),
        );
        await tester.pumpWidget(
          host(const SupyDocumentScannerView(guidance: cfg)),
        );
        final container = tester.widget<Container>(
          find.ancestor(
            of: find.text('Searching for document…'),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.border, isA<Border>());
        expect(
          (decoration.border! as Border).top.color.toARGB32(),
          const Color(0xFFAABBCC).toARGB32(),
        );
      });
    });
  });
}
