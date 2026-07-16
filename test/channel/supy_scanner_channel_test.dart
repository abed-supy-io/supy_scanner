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
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('scanDocument decodes a result map', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scanDocument');
      expect(call.arguments, isA<Map<Object?, Object?>>());
      return <Object?, Object?>{
        'pages': <Object?>[
          <Object?, Object?>{
            'uri': 'file:///out.jpg',
            'width': 100,
            'height': 200,
          },
        ],
        'ocrText': 'invoice total 42',
      };
    });

    final result = await channelUnderTest.scanDocument(
      const SupyDocumentScanOptions(),
    );
    expect(result, isNotNull);
    expect(result!.pages, hasLength(1));
    expect(result.ocrText, 'invoice total 42');
  });

  test('scanDocument returns null when native returns null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final result = await channelUnderTest.scanDocument(
      const SupyDocumentScanOptions(),
    );
    expect(result, isNull);
  });

  test('PlatformException becomes SupyScanError with mapped code', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'permission_denied', message: 'nope');
    });

    expect(
      () => channelUnderTest.scanDocument(const SupyDocumentScanOptions()),
      throwsA(
        isA<SupyScanError>()
            .having((e) => e.code, 'code', SupyScanErrorCode.permissionDenied)
            .having((e) => e.message, 'message', 'nope'),
      ),
    );
  });

  test('requestCameraPermission decodes status', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestCameraPermission');
      return <String, Object?>{'status': 'granted'};
    });
    expect(
      await channelUnderTest.requestCameraPermission(),
      SupyCameraPermissionStatus.granted,
    );
  });

  test('nativeCoreProbe decodes version + abiVersion', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'nativeCoreProbe');
      return <String, Object?>{'version': '1.1.0-dev.1', 'abiVersion': 1};
    });
    final probe = await channelUnderTest.nativeCoreProbe();
    expect(probe.version, '1.1.0-dev.1');
    expect(probe.abiVersion, 1);
    expect(probe.gmsDocumentScannerAvailable, isFalse);
  });

  test('nativeCoreProbe decodes gmsDocumentScannerAvailable (v1.2)', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'version': '1.2.0',
        'abiVersion': 1,
        'gmsDocumentScannerAvailable': true,
      };
    });
    final probe = await channelUnderTest.nativeCoreProbe();
    expect(probe.gmsDocumentScannerAvailable, isTrue);
  });

  test(
    'scanDocument forwards preferredBackend and decodes resolvedBackend',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'scanDocument');
        final args = call.arguments as Map<Object?, Object?>;
        expect(args['preferredBackend'], 'cameraX');
        return <Object?, Object?>{
          'pages': <Object?>[],
          'ocrText': '',
          'resolvedBackend': 'cameraX',
        };
      });

      final result = await channelUnderTest.scanDocument(
        const SupyDocumentScanOptions(
          preferredBackend: SupyDocumentScannerBackend.cameraX,
        ),
      );
      expect(result, isNotNull);
      expect(result!.resolvedBackend, SupyDocumentScannerBackend.cameraX);
    },
  );

  test('nativeCoreProbe surfaces PlatformException as SupyScanError', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'native_core_unavailable',
        message: 'no .so',
      );
    });
    expect(channelUnderTest.nativeCoreProbe(), throwsA(isA<SupyScanError>()));
  });

  test('getDeviceTier decodes high/mid/low/unknown', () async {
    for (final entry
        in <String, SupyDeviceTier>{
          'high': SupyDeviceTier.high,
          'mid': SupyDeviceTier.mid,
          'low': SupyDeviceTier.low,
          'bogus': SupyDeviceTier.unknown,
        }.entries) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getDeviceTier');
        return <String, Object?>{'tier': entry.key};
      });
      expect(await channelUnderTest.getDeviceTier(), entry.value);
    }
  });

  test('getDeviceTier returns unknown when native returns null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await channelUnderTest.getDeviceTier(), SupyDeviceTier.unknown);
  });

  test('getDeviceTier wraps PlatformException as SupyScanError', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unknown', message: 'boom');
    });
    expect(channelUnderTest.getDeviceTier(), throwsA(isA<SupyScanError>()));
  });

  test('debugForceTier sends the wire tier in debug mode', () async {
    // The Dart wrapper is gated on `kDebugMode`, which is true under
    // `flutter test`. Each enum value should map to the documented wire form.
    for (final entry
        in <SupyDeviceTier, String?>{
          SupyDeviceTier.high: 'high',
          SupyDeviceTier.mid: 'mid',
          SupyDeviceTier.low: 'low',
          SupyDeviceTier.unknown: null,
        }.entries) {
      MethodCall? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return null;
      });
      await channelUnderTest.debugForceTier(entry.key);
      expect(captured?.method, 'debugForceTier');
      expect(
        (captured?.arguments as Map?)?['tier'],
        entry.value,
        reason: 'tier=${entry.key} should wire-encode as ${entry.value}',
      );
    }
  });

  test('debugForceTier sends null to clear', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });
    await channelUnderTest.debugForceTier(null);
    expect(captured?.method, 'debugForceTier');
    expect((captured?.arguments as Map?)?['tier'], isNull);
  });

  test('debugForceTier wraps PlatformException as SupyScanError', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unknown', message: 'boom');
    });
    expect(
      channelUnderTest.debugForceTier(SupyDeviceTier.low),
      throwsA(isA<SupyScanError>()),
    );
  });

  test('prewarm forwards through without arguments', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      expect(call.method, 'prewarm');
      expect(call.arguments, isNull);
      return null;
    });
    await channelUnderTest.prewarm();
    expect(called, isTrue);
  });
}
