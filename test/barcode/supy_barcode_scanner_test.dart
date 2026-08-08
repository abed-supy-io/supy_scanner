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

  // Web / desktop have no embedded PlatformView, so the batch session falls
  // back to the native full-screen scanner. See `TODO.md` (2026-08-07) +
  // `docs/MIGRATION.md`.
  group('startMultiple — native routing (scanBarcodesBatch)', () {
    testWidgets('desktop falls back to native scanBarcodesBatch and maps the '
        'result', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        Map<Object?, Object?>? sent;
        String? method;
        messenger.setMockMethodCallHandler(channel, (call) async {
          method = call.method;
          sent = call.arguments as Map<Object?, Object?>;
          return <Object?, Object?>{
            'items': <Object?>[
              <Object?, Object?>{'rawValue': 'A', 'format': 'qr'},
              <Object?, Object?>{'rawValue': 'B', 'format': 'ean13'},
            ],
            'duplicateCount': 3,
          };
        });

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const Scaffold();
              },
            ),
          ),
        );

        final result = await SupyBarcodeScanner.startMultiple(
          ctx,
          options: const SupyBatchBarcodeScanOptions(dedupeWindowMs: 500),
        );

        expect(method, 'scanBarcodesBatch');
        expect(sent!['dedupeWindowMs'], 500);
        expect(result, isNotNull);
        expect(result!.items.map((b) => b.rawValue), <String>['A', 'B']);
        expect(result.duplicateCount, 3);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('null from native (cancel) surfaces as null', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        messenger.setMockMethodCallHandler(channel, (call) async => null);

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const Scaffold();
              },
            ),
          ),
        );

        final result = await SupyBarcodeScanner.startMultiple(ctx);
        expect(result, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // Generic capture on the two mobile targets is drawn by the branded Flutter
  // session — the channel is never touched; the whole loop lives in Dart.
  group('startMultiple — branded routing (Flutter session)', () {
    testWidgets('mobile pushes SupyBarcodeScannerScreen without touching the '
        'channel; cancel resolves null', (tester) async {
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

      final pending = SupyBarcodeScanner.startMultiple(navContext);
      await tester.pump(); // kick off the route transition
      await tester.pump(const Duration(milliseconds: 350)); // settle it in

      expect(find.byType(SupyBarcodeScannerScreen), findsOneWidget);
      expect(channelTouched, isFalse);

      // Cancel pops the route and resolves the pending future to null,
      // mirroring the native "user cancelled" outcome. The branded top bar
      // renders its cancel affordance as a tappable 'Cancel' text control.
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(await pending, isNull);
    });
  });

  // The branded submit callback yields per-payload counts; the facade adapts
  // that to the native `{items, duplicateCount}` shape.
  group('branded → batch result adapter', () {
    const qr = SupyBarcodeFormat.qr;

    test('unique payloads with no repeats => zero duplicates', () {
      final result = SupyBarcodeScanner.debugToBatchResult(const [
        SupyMultipleScanItem(
          barcode: SupyBarcode(rawValue: 'A', format: qr),
          count: 1,
        ),
        SupyMultipleScanItem(
          barcode: SupyBarcode(rawValue: 'B', format: qr),
          count: 1,
        ),
      ]);
      expect(result.items.map((b) => b.rawValue), <String>['A', 'B']);
      expect(result.duplicateCount, 0);
    });

    test('repeat detections accrue as duplicateCount', () {
      final result = SupyBarcodeScanner.debugToBatchResult(const [
        SupyMultipleScanItem(
          barcode: SupyBarcode(rawValue: 'A', format: qr),
          count: 3,
        ),
        SupyMultipleScanItem(
          barcode: SupyBarcode(rawValue: 'B', format: qr),
          count: 1,
        ),
      ]);
      // 2 unique rows, total detections 4 => 2 duplicates.
      expect(result.items.map((b) => b.rawValue), <String>['A', 'B']);
      expect(result.duplicateCount, 2);
    });

    test('empty accumulator => empty result', () {
      final result = SupyBarcodeScanner.debugToBatchResult(const []);
      expect(result.items, isEmpty);
      expect(result.duplicateCount, 0);
    });
  });
}
