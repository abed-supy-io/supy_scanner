import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channelUnderTest = SupyScannerChannel.test(channel);

  tearDown(() {
    SupyScanner.deactivate();
    messenger.setMockMethodCallHandler(channel, null);
  });

  SupyLicense license({DateTime? expiresAt}) => SupyLicense.forTesting(
    id: 'lic-1',
    product: 'supy_scanner',
    tier: SupyLicenseTier.growth,
    seats: 3,
    issuedAt: DateTime.utc(2024),
    expiresAt: expiresAt ?? DateTime.utc(2099),
  );

  group('activation state', () {
    test('starts deactivated', () {
      expect(SupyScanner.isActivated, isFalse);
      expect(SupyScanner.license, isNull);
    });

    test('debugSetLicense marks activated', () {
      SupyScanner.debugSetLicense(license());
      expect(SupyScanner.isActivated, isTrue);
      expect(SupyScanner.license?.id, 'lic-1');
    });

    test('an expired license reads as not activated', () {
      SupyScanner.debugSetLicense(license(expiresAt: DateTime.utc(2000)));
      expect(SupyScanner.isActivated, isFalse);
    });
  });

  group('gate blocks scanning without a license', () {
    test(
      'scanDocument throws notActivated before touching the channel',
      () async {
        var invoked = false;
        messenger.setMockMethodCallHandler(channel, (call) async {
          invoked = true;
          return null;
        });

        await expectLater(
          channelUnderTest.scanDocument(const SupyDocumentScanOptions()),
          throwsA(
            isA<SupyLicenseException>().having(
              (e) => e.code,
              'code',
              SupyLicenseErrorCode.notActivated,
            ),
          ),
        );
        expect(invoked, isFalse, reason: 'gate must short-circuit the channel');
      },
    );

    test(
      'scanBarcodesBatch throws expired when the license is stale',
      () async {
        SupyScanner.debugSetLicense(license(expiresAt: DateTime.utc(2000)));
        messenger.setMockMethodCallHandler(channel, (call) async => null);

        await expectLater(
          channelUnderTest.scanBarcodesBatch(
            const SupyBatchBarcodeScanOptions(),
          ),
          throwsA(
            isA<SupyLicenseException>().having(
              (e) => e.code,
              'code',
              SupyLicenseErrorCode.expired,
            ),
          ),
        );
      },
    );
  });

  group('gate lets scanning through with a valid license', () {
    test('scanDocument reaches the channel once activated', () async {
      SupyScanner.debugSetLicense(license());
      var invoked = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        invoked = true;
        expect(call.method, 'scanDocument');
        return null;
      });

      final result = await channelUnderTest.scanDocument(
        const SupyDocumentScanOptions(),
      );
      expect(invoked, isTrue);
      expect(result, isNull);
    });
  });

  group('verifier rejects malformed tokens', () {
    const verifier = SupyLicenseVerifier();

    test('missing prefix -> malformed', () async {
      await expectLater(
        verifier.verify('not-a-token'),
        throwsA(
          isA<SupyLicenseException>().having(
            (e) => e.code,
            'code',
            SupyLicenseErrorCode.malformed,
          ),
        ),
      );
    });

    test('wrong segment count -> malformed', () async {
      await expectLater(
        verifier.verify('supy-lic.v1.onlythree'),
        throwsA(
          isA<SupyLicenseException>().having(
            (e) => e.code,
            'code',
            SupyLicenseErrorCode.malformed,
          ),
        ),
      );
    });
  });
}
