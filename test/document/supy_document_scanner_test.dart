import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<BuildContext> pumpContext(
    WidgetTester tester, {
    Locale? locale,
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      Localizations(
        locale: locale ?? const Locale('en'),
        delegates: const <LocalizationsDelegate<Object?>>[
          DefaultWidgetsLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
        ],
        child: Builder(
          builder: (c) {
            captured = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('startMultiPage calls scanDocument with Scanbot-parity defaults '
      'and maps pages', (tester) async {
    Map<Object?, Object?>? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scanDocument');
      sent = call.arguments as Map<Object?, Object?>;
      return <Object?, Object?>{
        'pages': <Object?>[
          <Object?, Object?>{
            'uri': 'file:///inv.jpg',
            'width': 100,
            'height': 200,
          },
        ],
      };
    });

    final ctx = await pumpContext(tester);
    final result = await SupyDocumentScanner.startMultiPage(ctx);

    expect(result, isNotNull);
    expect(result!.pages.single.uri, 'file:///inv.jpg');
    expect(sent!['maxPages'], 0);
    expect(sent!['ocrLanguages'], <String>['en', 'ar']);
    expect(sent!['palettePrimary'], '#6448C3');
    expect(sent!['paletteOnPrimary'], '#FFFFFF');
    // Default intent keeps per-page images (not the PDF invoice preset).
    expect(sent!['intent'], 'generic');
    // No ambient locale => defaults to 'en'.
    expect(sent!['locale'], 'en');
  });

  testWidgets('startMultiPage derives ar locale from ambient Localizations', (
    tester,
  ) async {
    Map<Object?, Object?>? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call.arguments as Map<Object?, Object?>;
      return null;
    });

    final ctx = await pumpContext(tester, locale: const Locale('ar'));
    final result = await SupyDocumentScanner.startMultiPage(ctx);

    expect(result, isNull); // user cancelled
    expect(sent!['locale'], 'ar');
  });

  testWidgets('explicit locale wins over the ambient one', (tester) async {
    Map<Object?, Object?>? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call.arguments as Map<Object?, Object?>;
      return null;
    });

    final ctx = await pumpContext(tester, locale: const Locale('ar'));
    await SupyDocumentScanner.startMultiPage(ctx, locale: 'en');

    expect(sent!['locale'], 'en');
  });
}
