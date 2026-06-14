import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;
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

    final result =
        await channelUnderTest.scanDocument(const SupyDocumentScanOptions());
    expect(result, isNotNull);
    expect(result!.pages, hasLength(1));
    expect(result.ocrText, 'invoice total 42');
  });

  test('scanDocument returns null when native returns null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final result =
        await channelUnderTest.scanDocument(const SupyDocumentScanOptions());
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
      return <String, Object?>{
        'version': '1.1.0-dev.1',
        'abiVersion': 1,
      };
    });
    final probe = await channelUnderTest.nativeCoreProbe();
    expect(probe.version, '1.1.0-dev.1');
    expect(probe.abiVersion, 1);
  });

  test('nativeCoreProbe surfaces PlatformException as SupyScanError', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'native_core_unavailable', message: 'no .so');
    });
    expect(
      channelUnderTest.nativeCoreProbe(),
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
