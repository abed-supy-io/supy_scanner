import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1/document/7');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late SupyDocumentScannerController controller;
  late List<MethodCall> calls;

  setUp(() {
    controller = SupyDocumentScannerController();
    controller.attach(channel);
    calls = <MethodCall>[];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    controller.dispose();
  });

  group('SupyDocumentScannerController.capture', () {
    test('drives capturePhase capturing → captured on success', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return <String, Object?>{
          'uri': 'file:///tmp/page1.jpg',
          'width': 1200,
          'height': 1600,
        };
      });

      final phases = <SupyDocumentCapturePhase>[];
      controller.addListener(() => phases.add(controller.capturePhase));

      final page = await controller.capture();

      expect(calls.single.method, 'captureAndRectify');
      expect(page, isNotNull);
      expect(page!.uri, 'file:///tmp/page1.jpg');
      expect(page.width, 1200);
      expect(page.height, 1600);
      expect(
        phases,
        [SupyDocumentCapturePhase.capturing, SupyDocumentCapturePhase.captured],
      );
    });

    test('resets to idle and rethrows on native error', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'capture_failed');
      });

      await expectLater(
        controller.capture(),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.capturePhase, SupyDocumentCapturePhase.idle);
    });

    test('ignores re-entrant calls while a capture is in flight', () async {
      var pending = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        pending++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return <String, Object?>{
          'uri': 'file:///tmp/p.jpg',
          'width': 1,
          'height': 1,
        };
      });

      final first = controller.capture();
      final secondImmediate = controller.capture();
      await first;
      await secondImmediate;

      expect(pending, 1, reason: 'only the first capture reached the channel');
    });

    test('returns null and stays idle when not attached', () async {
      final detached = SupyDocumentScannerController();
      addTearDown(detached.dispose);
      expect(await detached.capture(), isNull);
      expect(detached.capturePhase, SupyDocumentCapturePhase.idle);
    });

    test('clearCapturePhase returns to idle after a captured flash', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return <String, Object?>{
          'uri': 'file:///tmp/p.jpg',
          'width': 10,
          'height': 10,
        };
      });
      await controller.capture();
      expect(controller.capturePhase, SupyDocumentCapturePhase.captured);
      controller.clearCapturePhase();
      expect(controller.capturePhase, SupyDocumentCapturePhase.idle);
    });
  });

  group('SupyDocumentScanOptions auto-capture', () {
    test('defaults autoCaptureDelayMs to 800ms', () {
      const opts = SupyDocumentScanOptions();
      expect(opts.autoCaptureDelayMs, 800);
      expect(opts.toWire()['autoCaptureDelayMs'], 800);
    });

    test('autoCaptureDelayMs = 0 disables auto-capture', () {
      const opts = SupyDocumentScanOptions(autoCaptureDelayMs: 0);
      expect(opts.toWire()['autoCaptureDelayMs'], 0);
    });
  });

  group('SupyDocumentCapture.quadSource', () {
    test('parses quadSource when present', () {
      final capture = SupyDocumentCapture.fromMap(const <Object?, Object?>{
        'path': '/tmp/a.jpg',
        'widthPx': 100,
        'heightPx': 200,
        'quadSource': 'refined',
      });
      expect(capture.quadSource, 'refined');
    });

    test('quadSource is null when absent (Android / full-frame)', () {
      final capture = SupyDocumentCapture.fromMap(const <Object?, Object?>{
        'path': '/tmp/a.jpg',
        'widthPx': 100,
        'heightPx': 200,
      });
      expect(capture.quadSource, isNull);
    });

    test('quadSource participates in equality', () {
      const a = SupyDocumentCapture(
        path: '/tmp/a.jpg',
        widthPx: 1,
        heightPx: 1,
        quadSource: 'refined',
      );
      const b = SupyDocumentCapture(
        path: '/tmp/a.jpg',
        widthPx: 1,
        heightPx: 1,
        quadSource: 'preview',
      );
      const c = SupyDocumentCapture(
        path: '/tmp/a.jpg',
        widthPx: 1,
        heightPx: 1,
        quadSource: 'refined',
      );
      expect(a, isNot(equals(b)));
      expect(a, equals(c));
      expect(a.hashCode, c.hashCode);
    });
  });
}
