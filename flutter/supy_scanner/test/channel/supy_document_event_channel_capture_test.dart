import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/widgets/supy_document_scanner_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captureAndRectify returns parsed result', () async {
    final ctrl = SupyDocumentScannerController();
    const channel = MethodChannel('io.supy.scanner/v1/document/0');
    ctrl.attach(channel);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'captureAndRectify') {
            return <String, Object?>{
              'path': '/tmp/page.jpg',
              'widthPx': 2480,
              'heightPx': 3508,
              'quad': <Map<String, Object?>>[
                {'x': 0.1, 'y': 0.1},
                {'x': 0.9, 'y': 0.1},
                {'x': 0.9, 'y': 0.9},
                {'x': 0.1, 'y': 0.9},
              ],
            };
          }
          return null;
        });

    final result = await ctrl.captureAndRectify();
    expect(result.path, '/tmp/page.jpg');
    expect(result.widthPx, 2480);
    expect(result.quad.length, 4);
  });

  test(
    'captureAndRectify UNIMPLEMENTED throws captureUnsupported error',
    () async {
      final ctrl = SupyDocumentScannerController();
      const channel = MethodChannel('io.supy.scanner/v1/document/1');
      ctrl.attach(channel);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'UNIMPLEMENTED');
          });
      await expectLater(
        ctrl.captureAndRectify(),
        throwsA(
          predicate(
            (e) => e is StateError && e.message.contains('captureUnsupported'),
          ),
        ),
      );
    },
  );

  test(
    'captureFullFrame UNIMPLEMENTED throws captureUnsupported error',
    () async {
      final ctrl = SupyDocumentScannerController();
      const channel = MethodChannel('io.supy.scanner/v1/document/3');
      ctrl.attach(channel);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'UNIMPLEMENTED');
          });
      await expectLater(
        ctrl.captureFullFrame(),
        throwsA(
          predicate(
            (e) => e is StateError && e.message.contains('captureUnsupported'),
          ),
        ),
      );
    },
  );

  test('captureFullFrame returns parsed result', () async {
    final ctrl = SupyDocumentScannerController();
    const channel = MethodChannel('io.supy.scanner/v1/document/2');
    ctrl.attach(channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'captureFullFrame') {
            return <String, Object?>{
              'path': '/tmp/raw.jpg',
              'widthPx': 3024,
              'heightPx': 4032,
            };
          }
          return null;
        });
    final r = await ctrl.captureFullFrame();
    expect(r.path, '/tmp/raw.jpg');
  });
}
