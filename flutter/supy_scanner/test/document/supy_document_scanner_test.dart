import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../support/license_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(activateTestLicense);
  tearDown(() {
    clearTestLicense();
    messenger.setMockMethodCallHandler(channel, null);
  });

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

  // The native full-screen scanner still owns the invoice preset (OCR + PDF)
  // and any non-mobile platform. See `TODO.md` (2026-08-07) + `docs/UI-PARITY.md`.
  group('startMultiPage — native routing (scanDocument)', () {
    testWidgets('invoice intent scans natively with parity defaults + maps '
        'pages', (tester) async {
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
      final result = await SupyDocumentScanner.startMultiPage(
        ctx,
        intent: SupyDocumentScanIntent.invoice,
      );

      expect(result, isNotNull);
      expect(result!.pages.single.uri, 'file:///inv.jpg');
      expect(sent!['maxPages'], 0);
      expect(sent!['ocrLanguages'], <String>['en', 'ar']);
      expect(sent!['palettePrimary'], '#6448C3');
      expect(sent!['paletteOnPrimary'], '#FFFFFF');
      expect(sent!['intent'], 'invoice');
      // No ambient locale => defaults to 'en'.
      expect(sent!['locale'], 'en');
    });

    testWidgets('derives ar locale from ambient Localizations (native path)', (
      tester,
    ) async {
      Map<Object?, Object?>? sent;
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent = call.arguments as Map<Object?, Object?>;
        return null;
      });

      final ctx = await pumpContext(tester, locale: const Locale('ar'));
      final result = await SupyDocumentScanner.startMultiPage(
        ctx,
        intent: SupyDocumentScanIntent.invoice,
      );

      expect(result, isNull); // user cancelled
      expect(sent!['locale'], 'ar');
    });

    testWidgets('explicit locale wins over the ambient one (native path)', (
      tester,
    ) async {
      Map<Object?, Object?>? sent;
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent = call.arguments as Map<Object?, Object?>;
        return null;
      });

      final ctx = await pumpContext(tester, locale: const Locale('ar'));
      await SupyDocumentScanner.startMultiPage(
        ctx,
        intent: SupyDocumentScanIntent.invoice,
        locale: 'en',
      );

      expect(sent!['locale'], 'en');
    });

    testWidgets('generic intent on desktop falls back to native scanDocument', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        var scanned = false;
        messenger.setMockMethodCallHandler(channel, (call) async {
          scanned = call.method == 'scanDocument';
          return null;
        });

        final ctx = await pumpContext(tester);
        await SupyDocumentScanner.startMultiPage(ctx); // generic (default)

        expect(scanned, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // Generic capture on the two mobile targets is drawn by the branded Flutter
  // session — the channel is never touched; the whole loop lives in Dart.
  group('startMultiPage — branded routing (Flutter session)', () {
    testWidgets('generic intent on mobile pushes SupyDocumentScannerScreen '
        'without touching the channel', (tester) async {
      // Default test target platform is android => branded path.
      var channelTouched = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        channelTouched = true;
        return null;
      });

      late BuildContext navContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              navContext = c;
              return const Scaffold();
            },
          ),
        ),
      );

      final pending = SupyDocumentScanner.startMultiPage(navContext);
      await tester.pump(); // kick off the route transition
      await tester.pump(const Duration(milliseconds: 350)); // settle it in

      expect(find.byType(SupyDocumentScannerScreen), findsOneWidget);
      expect(channelTouched, isFalse);

      // Cancel pops the route and resolves the pending future to null,
      // mirroring the native "user cancelled" outcome.
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(await pending, isNull);
    });
  });
}
