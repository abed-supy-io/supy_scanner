import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/widgets/supy_barcode_scanner_controller.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.supy.scanner/v1/barcode/42');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late SupyBarcodeScannerController controller;
  late List<MethodCall> calls;

  setUp(() {
    controller = SupyBarcodeScannerController();
    controller.attach(channel);
    calls = <MethodCall>[];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    controller.dispose();
  });

  test('setZoom forwards factor and updates state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    await controller.setZoom(2.5);

    expect(calls.single.method, 'setZoom');
    expect(calls.single.arguments, <String, Object?>{'factor': 2.5});
    expect(controller.zoom, 2.5);
  });

  test('flipCamera reads position from native and updates state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, Object?>{'position': 'front'};
    });

    final position = await controller.flipCamera();

    expect(calls.single.method, 'flipCamera');
    expect(position, SupyCameraPosition.front);
    expect(controller.cameraPosition, SupyCameraPosition.front);
  });

  test('setMinFocusDistanceLock forwards flag and updates state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    await controller.setMinFocusDistanceLock(on: true);

    expect(calls.single.method, 'setMinFocusDistanceLock');
    expect(calls.single.arguments, <String, Object?>{'on': true});
    expect(controller.minFocusDistanceLock, isTrue);
  });

  test('methods are no-ops when controller is detached', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    controller.detach();

    await controller.setZoom(3.0);
    await controller.flipCamera();
    await controller.setMinFocusDistanceLock(on: true);

    expect(calls, isEmpty);
  });
}
