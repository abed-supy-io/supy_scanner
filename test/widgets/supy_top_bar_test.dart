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
