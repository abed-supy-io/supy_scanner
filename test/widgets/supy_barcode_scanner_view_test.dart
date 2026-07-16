import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  // Route the PlatformView selector to an unsupported target so the Stack
  // composition is exercisable without a real AndroidView/UiKitView host.
  // `debugDefaultTargetPlatformOverride` is a foundation debug var — the
  // framework asserts it's unset at the end of each test body, so it must
  // be reset inside the body (before pumpWidget settles), not in tearDown.
  Future<T> withPlatform<T>(TargetPlatform p, Future<T> Function() body) async {
    final prior = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = p;
    try {
      return await body();
    } finally {
      debugDefaultTargetPlatformOverride = prior;
    }
  }

  // The scanner's own Stack is the FIRST Stack in the tree (MaterialApp adds
  // its own further down). Counting its direct children isolates the
  // finder/header/footer composition from framework-injected siblings.
  int scannerStackChildren(WidgetTester tester) {
    return tester.widget<Stack>(find.byType(Stack).first).children.length;
  }

  testWidgets('default config: stack contains preview + finder', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.linux, () async {
      await tester.pumpWidget(host(const SupyBarcodeScannerView()));
      expect(scannerStackChildren(tester), 2);
    });
  });

  testWidgets('showFinder=false: stack contains only the preview', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.linux, () async {
      await tester.pumpWidget(
        host(const SupyBarcodeScannerView(showFinder: false)),
      );
      expect(scannerStackChildren(tester), 1);
    });
  });

  testWidgets('header is positioned at the top of the stack', (tester) async {
    await withPlatform(TargetPlatform.linux, () async {
      await tester.pumpWidget(
        host(
          const SupyBarcodeScannerView(
            showFinder: false,
            header: SizedBox(
              key: ValueKey('hdr'),
              height: 40,
              child: Text('HEADER'),
            ),
          ),
        ),
      );
      expect(find.text('HEADER'), findsOneWidget);
      final stackBox = tester.getRect(find.byType(Stack).first);
      final hdrBox = tester.getRect(find.byKey(const ValueKey('hdr')));
      expect(hdrBox.top, stackBox.top);
    });
  });

  testWidgets('footer is positioned at the bottom of the stack', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.linux, () async {
      await tester.pumpWidget(
        host(
          const SupyBarcodeScannerView(
            showFinder: false,
            footer: SizedBox(
              key: ValueKey('ftr'),
              height: 40,
              child: Text('FOOTER'),
            ),
          ),
        ),
      );
      expect(find.text('FOOTER'), findsOneWidget);
      final stackBox = tester.getRect(find.byType(Stack).first);
      final ftrBox = tester.getRect(find.byKey(const ValueKey('ftr')));
      expect(ftrBox.bottom, stackBox.bottom);
    });
  });

  testWidgets(
    'extreme config: header + footer + no finder all stack together',
    (tester) async {
      await withPlatform(TargetPlatform.linux, () async {
        await tester.pumpWidget(
          host(
            const SupyBarcodeScannerView(
              showFinder: false,
              header: SizedBox(height: 32, child: Text('H')),
              footer: SizedBox(height: 32, child: Text('F')),
            ),
          ),
        );
        expect(find.text('H'), findsOneWidget);
        expect(find.text('F'), findsOneWidget);
        // preview + header + footer (no finder)
        expect(scannerStackChildren(tester), 3);
      });
    },
  );

  testWidgets('unsupported platforms render the placeholder text', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.macOS, () async {
      await tester.pumpWidget(host(const SupyBarcodeScannerView()));
      expect(
        find.textContaining('SupyBarcodeScannerView is not yet supported'),
        findsOneWidget,
      );
      expect(find.textContaining('macOS'), findsOneWidget);
    });
  });

  testWidgets('dispose detaches the provided controller without throwing', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.linux, () async {
      final controller = SupyBarcodeScannerController();
      await tester.pumpWidget(
        host(SupyBarcodeScannerView(controller: controller)),
      );
      // Replacing the tree triggers State.dispose() on the scanner view.
      await tester.pumpWidget(host(const SizedBox.shrink()));
      expect(tester.takeException(), isNull);
    });
  });
}
