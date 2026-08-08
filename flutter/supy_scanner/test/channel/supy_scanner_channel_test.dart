import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../support/license_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channelUnderTest = SupyScannerChannel.test(channel);

  setUp(activateTestLicense);
  tearDown(() {
    clearTestLicense();
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

  test('importDocumentImage decodes a page map', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'importDocumentImage');
      expect(call.arguments, isNull);
      return <Object?, Object?>{
        'uri': 'file:///import.jpg',
        'width': 1240,
        'height': 1754,
        'quality': 'good',
        'qualityScore': 0.82,
      };
    });

    final page = await channelUnderTest.importDocumentImage();
    expect(page, isNotNull);
    expect(page!.uri, 'file:///import.jpg');
    expect(page.width, 1240);
    expect(page.height, 1754);
    expect(page.quality, SupyDocumentPageQuality.good);
    expect(page.qualityScore, 0.82);
  });

  test('importDocumentImage forwards scan options to the wire', () async {
    Object? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'importDocumentImage');
      captured = call.arguments;
      return <Object?, Object?>{
        'uri': 'file:///import.jpg',
        'width': 1240,
        'height': 1754,
      };
    });

    await channelUnderTest.importDocumentImage(
      const SupyDocumentScanOptions(
        filter: SupyDocumentFilter.grayscale,
        enhanceMode: SupyDocumentEnhanceMode.balanced,
      ),
    );

    expect(captured, isA<Map<Object?, Object?>>());
    final args = captured! as Map<Object?, Object?>;
    expect(args['filter'], 'grayscale');
    expect(args['enhanceMode'], 'balanced');
  });

  test(
    'importDocumentImage returns null when the picker is dismissed',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await channelUnderTest.importDocumentImage(), isNull);
    },
  );

  test(
    'importDocumentImage wraps PlatformException as SupyScanError',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unknown', message: 'no picker');
      });
      expect(
        channelUnderTest.importDocumentImage(),
        throwsA(
          isA<SupyScanError>()
              .having((e) => e.code, 'code', SupyScanErrorCode.unknown)
              .having((e) => e.message, 'message', 'no picker'),
        ),
      );
    },
  );

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

  test('recognizeText forwards args and decodes the block tree', () async {
    late MethodCall captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return <Object?, Object?>{
        'fullText': 'HELLO\nWORLD',
        'blocks': <Object?>[
          <Object?, Object?>{
            'text': 'HELLO\nWORLD',
            'boundingBox': <Object?, Object?>{
              'left': 0.1,
              'top': 0.2,
              'width': 0.5,
              'height': 0.3,
            },
            'lines': <Object?>[
              <Object?, Object?>{
                'text': 'HELLO',
                'boundingBox': <Object?, Object?>{
                  'left': 0.1,
                  'top': 0.2,
                  'width': 0.5,
                  'height': 0.15,
                },
                'elements': <Object?>[
                  <Object?, Object?>{
                    'text': 'HELLO',
                    'boundingBox': <Object?, Object?>{
                      'left': 0.1,
                      'top': 0.2,
                      'width': 0.5,
                      'height': 0.15,
                    },
                  },
                ],
              },
              <Object?, Object?>{
                'text': 'WORLD',
                'boundingBox': <Object?, Object?>{
                  'left': 0.1,
                  'top': 0.35,
                  'width': 0.5,
                  'height': 0.15,
                },
                'elements': <Object?>[],
              },
            ],
          },
        ],
      };
    });

    final result = await channelUnderTest.recognizeText(
      const SupyRecognizeTextOptions(
        imagePath: '/tmp/doc.jpg',
        languages: <String>['en', 'ar'],
      ),
    );

    expect(captured.method, 'recognizeText');
    final args = captured.arguments as Map<Object?, Object?>;
    expect(args['imagePath'], '/tmp/doc.jpg');
    expect(args['languages'], <String>['en', 'ar']);
    expect(args['includeElements'], isTrue);

    expect(result.fullText, 'HELLO\nWORLD');
    expect(result.blocks, hasLength(1));
    final block = result.blocks.single;
    expect(block.boundingBox, const Rect.fromLTWH(0.1, 0.2, 0.5, 0.3));
    expect(block.lines, hasLength(2));
    expect(block.lines.first.text, 'HELLO');
    expect(block.lines.first.elements, hasLength(1));
    expect(block.lines.first.elements.single.text, 'HELLO');
    expect(block.lines.last.elements, isEmpty);
  });

  test('recognizeText throws SupyScanError when native returns null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(
      channelUnderTest.recognizeText(
        const SupyRecognizeTextOptions(imagePath: '/tmp/doc.jpg'),
      ),
      throwsA(isA<SupyScanError>()),
    );
  });

  test('recognizeText wraps PlatformException as SupyScanError', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'model_unavailable', message: 'no ocr');
    });
    expect(
      channelUnderTest.recognizeText(
        const SupyRecognizeTextOptions(imagePath: '/tmp/doc.jpg'),
      ),
      throwsA(
        isA<SupyScanError>().having(
          (e) => e.code,
          'code',
          SupyScanErrorCode.modelUnavailable,
        ),
      ),
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

  test('decodeImage forwards args and decodes the barcode list', () async {
    late MethodCall captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return <Object?>[
        <Object?, Object?>{
          'rawValue': '5901234123457',
          'format': 'ean13',
          'boundingBox': <Object?, Object?>{
            'left': 12.0,
            'top': 34.0,
            'width': 120.0,
            'height': 60.0,
          },
        },
        // Second detection omits boundingBox — must decode to a null Rect.
        <Object?, Object?>{'rawValue': 'https://supy.io', 'format': 'qr'},
      ];
    });

    final result = await channelUnderTest.decodeImage(
      const SupyDecodeImageOptions(
        imagePath: '/tmp/fixture.png',
        formats: <SupyBarcodeFormat>[
          SupyBarcodeFormat.ean13,
          SupyBarcodeFormat.qr,
        ],
        useNativeCore: true,
      ),
    );

    expect(captured.method, 'decodeImage');
    final args = captured.arguments as Map<Object?, Object?>;
    expect(args['imagePath'], '/tmp/fixture.png');
    expect(args['formats'], <String>['ean13', 'qr']);
    expect(args['useNativeCore'], isTrue);

    expect(result, hasLength(2));
    expect(result.first.rawValue, '5901234123457');
    expect(result.first.format, SupyBarcodeFormat.ean13);
    expect(result.first.boundingBox, const Rect.fromLTWH(12, 34, 120, 60));
    expect(result.last.format, SupyBarcodeFormat.qr);
    expect(result.last.boundingBox, isNull);
  });

  test('decodeImage returns empty list when native returns null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final result = await channelUnderTest.decodeImage(
      const SupyDecodeImageOptions(imagePath: '/tmp/fixture.png'),
    );
    expect(result, isEmpty);
  });

  test(
    'decodeImage defaults formats to [all] and useNativeCore false',
    () async {
      late MethodCall captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return <Object?>[];
      });
      await channelUnderTest.decodeImage(
        const SupyDecodeImageOptions(imagePath: '/tmp/fixture.png'),
      );
      final args = captured.arguments as Map<Object?, Object?>;
      expect(args['formats'], <String>['all']);
      expect(args['useNativeCore'], isFalse);
    },
  );

  test('decodeImage wraps PlatformException as SupyScanError', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unknown', message: 'bad image');
    });
    expect(
      channelUnderTest.decodeImage(
        const SupyDecodeImageOptions(imagePath: '/tmp/fixture.png'),
      ),
      throwsA(isA<SupyScanError>()),
    );
  });
}
