import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/widgets/supy_text_pattern_scanner_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupyTextPatternScannerController', () {
    late SupyTextPatternScannerController controller;
    late MethodChannel channel;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      controller = SupyTextPatternScannerController();
      channel = const MethodChannel('io.supy.scanner/v1/datacapture/7');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('is not attached before the view mounts', () {
      expect(controller.isAttached, isFalse);
    });

    test('no-ops silently when unattached', () async {
      await controller.setTorch(on: true);
      expect(calls, isEmpty);
      expect(controller.torchOn, isFalse);
    });

    test('channel name matches the versioned per-view convention', () {
      expect(
        supyDataCaptureMethodChannelName(7),
        'io.supy.scanner/v1/datacapture/7',
      );
    });

    test('setTorch invokes the native method and caches state', () async {
      controller.attach(channel);
      expect(controller.isAttached, isTrue);
      await controller.setTorch(on: true);
      expect(calls.single.method, 'setTorch');
      expect(calls.single.arguments, <String, Object?>{'on': true});
      expect(controller.torchOn, isTrue);
    });

    test('pause and resume drive the paused flag', () async {
      controller.attach(channel);
      await controller.pause();
      expect(controller.paused, isTrue);
      await controller.resume();
      expect(controller.paused, isFalse);
      expect(calls.map((c) => c.method), ['pause', 'resume']);
    });

    test('detach severs the channel', () async {
      controller.attach(channel);
      controller.detach();
      expect(controller.isAttached, isFalse);
      await controller.pause();
      expect(calls, isEmpty);
    });
  });
}
