import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/ui/supy_user_guidance_configuration.dart';
import 'package:supy_scanner/src/widgets/supy_user_guidance_card.dart';

void main() {
  Widget host(SupyUserGuidanceConfiguration config) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SupyUserGuidanceCard(config: config)),
    );
  }

  testWidgets('renders nothing when invisible', (tester) async {
    await tester.pumpWidget(
      host(const SupyUserGuidanceConfiguration(visible: false)),
    );
    expect(find.byType(Container), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders nothing when titleText is empty', (tester) async {
    await tester.pumpWidget(
      host(const SupyUserGuidanceConfiguration(titleText: '')),
    );
    expect(find.byType(Container), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders configured title text', (tester) async {
    await tester.pumpWidget(
      host(const SupyUserGuidanceConfiguration(titleText: 'Align the barcode')),
    );
    expect(find.text('Align the barcode'), findsOneWidget);
  });

  testWidgets('text style honors color and fontSize', (tester) async {
    await tester.pumpWidget(
      host(
        const SupyUserGuidanceConfiguration(
          titleText: 'Hello',
          titleColor: Color(0xFF112233),
          fontSize: 19,
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Hello'));
    expect(text.style?.color, const Color(0xFF112233));
    expect(text.style?.fontSize, 19);
    expect(text.textAlign, TextAlign.center);
  });

  testWidgets('container uses fill color and pill-shaped border radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SupyUserGuidanceConfiguration(
          titleText: 'Hi',
          backgroundFillColor: Color(0xCC123456),
        ),
      ),
    );
    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xCC123456));
    expect(decoration.borderRadius, BorderRadius.circular(24));
  });
}
