import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/ui/supy_top_bar_configuration.dart';
import 'package:supy_scanner/src/widgets/supy_top_bar.dart';

void main() {
  Widget host(SupyTopBarConfiguration config, {VoidCallback? onCancel}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 400,
        height: 200,
        child: SupyTopBar(config: config, onCancel: onCancel ?? () {}),
      ),
    );
  }

  testWidgets('renders cancel text from config', (tester) async {
    const config = SupyTopBarConfiguration(
      cancelButton: SupyTextStyleSpec(
        text: 'Dismiss',
        color: Color(0xFFFFFFFF),
      ),
    );
    await tester.pumpWidget(host(config));
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('omits cancel control when text is empty', (tester) async {
    const config = SupyTopBarConfiguration(
      cancelButton: SupyTextStyleSpec(text: '', color: Color(0xFFFFFFFF)),
    );
    await tester.pumpWidget(host(config));
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('cancel tap fires the callback exactly once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(const SupyTopBarConfiguration(), onCancel: () => taps++),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('cancel control exposes a semantics button with its label', (
    tester,
  ) async {
    await tester.pumpWidget(host(const SupyTopBarConfiguration()));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Cancel')),
      isSemantics(isButton: true, label: 'Cancel'),
    );
  });

  testWidgets('solid mode uses a solid background color', (tester) async {
    const config = SupyTopBarConfiguration(
      mode: SupyTopBarMode.solid,
      backgroundColor: Color(0xFF112233),
    );
    await tester.pumpWidget(host(config));
    final container =
        tester.widgetList<Container>(find.byType(Container)).first;
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF112233));
    expect(decoration.gradient, isNull);
  });

  testWidgets('gradient mode renders a top-to-bottom LinearGradient', (
    tester,
  ) async {
    const config = SupyTopBarConfiguration(backgroundColor: Color(0xFF445566));
    await tester.pumpWidget(host(config));
    final container =
        tester.widgetList<Container>(find.byType(Container)).first;
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    expect(gradient.colors.first, const Color(0xFF445566));
    expect(gradient.colors.last.a, 0);
  });

  group('statusBarMode', () {
    List<MethodCall> captureSystemChrome(WidgetTester tester) {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return calls;
    }

    testWidgets('default (hidden) hides the status-bar overlay, no style '
        'AnnotatedRegion', (tester) async {
      final calls = captureSystemChrome(tester);
      await tester.pumpWidget(host(const SupyTopBarConfiguration()));
      final overlays = calls.firstWhere(
        (c) => c.method == 'SystemChrome.setEnabledSystemUIOverlays',
      );
      expect(overlays.arguments, isNot(contains('SystemUiOverlay.top')));
      expect(overlays.arguments, contains('SystemUiOverlay.bottom'));
      expect(find.byType(AnnotatedRegion<SystemUiOverlayStyle>), findsNothing);
    });

    testWidgets('light mode applies a light overlay style + shows both bars', (
      tester,
    ) async {
      final calls = captureSystemChrome(tester);
      await tester.pumpWidget(
        host(
          const SupyTopBarConfiguration(statusBarMode: SupyStatusBarMode.light),
        ),
      );
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(region.value, SystemUiOverlayStyle.light);
      final overlays = calls.firstWhere(
        (c) => c.method == 'SystemChrome.setEnabledSystemUIOverlays',
      );
      expect(overlays.arguments, contains('SystemUiOverlay.top'));
    });

    testWidgets('dark mode applies a dark overlay style', (tester) async {
      captureSystemChrome(tester);
      await tester.pumpWidget(
        host(
          const SupyTopBarConfiguration(statusBarMode: SupyStatusBarMode.dark),
        ),
      );
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(region.value, SystemUiOverlayStyle.dark);
    });

    testWidgets('restores both bars on dispose when it had hidden them', (
      tester,
    ) async {
      final calls = captureSystemChrome(tester);
      await tester.pumpWidget(host(const SupyTopBarConfiguration()));
      calls.clear();
      await tester.pumpWidget(const SizedBox());
      final overlays = calls.firstWhere(
        (c) => c.method == 'SystemChrome.setEnabledSystemUIOverlays',
      );
      expect(overlays.arguments, contains('SystemUiOverlay.top'));
      expect(overlays.arguments, contains('SystemUiOverlay.bottom'));
    });
  });

  testWidgets('cancel text honors color/fontSize/fontWeight from spec', (
    tester,
  ) async {
    const config = SupyTopBarConfiguration(
      cancelButton: SupyTextStyleSpec(
        text: 'Cancel',
        color: Color(0xFFAABBCC),
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    );
    await tester.pumpWidget(host(config));
    final text = tester.widget<Text>(find.text('Cancel'));
    expect(text.style?.color, const Color(0xFFAABBCC));
    expect(text.style?.fontSize, 22);
    expect(text.style?.fontWeight, FontWeight.w800);
  });
}
