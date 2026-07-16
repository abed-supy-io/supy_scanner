// ignore_for_file: experimental_member_use, implementation_imports

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/experimental/supy_invoice_parser.dart';

/// Wire-shape tests for the experimental [SupyInvoiceParser] — Phase IXP.
///
/// These exercise the Dart side only via a mock [MethodChannel]; the iOS
/// pipeline is covered separately in `ios/Tests/invoice/InvoiceParserTests.swift`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final parser = SupyInvoiceParser(channel: channel);

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('parseInvoice decodes a full result map', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'parseInvoice');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['imagePath'], '/tmp/page.jpg');
      return <Object?, Object?>{
        'vendor': 'ACME COFFEE',
        'date': '2026-06-17',
        'invoiceNumber': 'INV-2026-0042',
        'currency': 'USD',
        'total': 12.5,
        'tax': 0.5,
        'lineItems': <Object?>[
          <Object?, Object?>{
            'description': 'Espresso',
            'amount': 3.5,
            'quantity': 1,
          },
          <Object?, Object?>{
            'description': 'Croissant',
            'amount': 2.75,
          },
        ],
        'rawText': 'ACME COFFEE\nTotal 12.50',
      };
    });

    final result = await parser.parse('/tmp/page.jpg');
    expect(result.vendor, 'ACME COFFEE');
    expect(result.date, '2026-06-17');
    expect(result.invoiceNumber, 'INV-2026-0042');
    expect(result.currency, 'USD');
    expect(result.total, 12.5);
    expect(result.tax, 0.5);
    expect(result.lineItems, hasLength(2));
    expect(result.lineItems[0].description, 'Espresso');
    expect(result.lineItems[0].amount, 3.5);
    expect(result.lineItems[0].quantity, 1);
    expect(result.lineItems[1].quantity, isNull);
    expect(result.rawText, contains('ACME COFFEE'));
  });

  test('parseInvoice tolerates partial result maps', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <Object?, Object?>{
        'rawText': 'just some text',
        'lineItems': <Object?>[],
      };
    });

    final result = await parser.parse('/tmp/page.jpg');
    expect(result.vendor, isNull);
    expect(result.total, isNull);
    expect(result.lineItems, isEmpty);
    expect(result.rawText, 'just some text');
  });

  test('unimplemented PlatformException becomes typed unsupported error',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'unimplemented',
        message: 'parseInvoice is iOS-only in v1.2 (Phase IXP)',
      );
    });

    await expectLater(
      parser.parse('/tmp/page.jpg'),
      throwsA(
        isA<SupyInvoiceParserUnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('iOS-only'),
        ),
      ),
    );
  });

  test('other PlatformExceptions propagate', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unknown', message: 'load failed');
    });

    await expectLater(
      parser.parse('/tmp/page.jpg'),
      throwsA(isA<PlatformException>()),
    );
  });
}
