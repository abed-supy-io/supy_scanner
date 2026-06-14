import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/ui/supy_action_bar_configuration.dart';
import 'package:supy_scanner/src/widgets/supy_action_bar.dart';
import 'package:supy_scanner/src/widgets/supy_barcode_scanner_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host({
    required SupyActionBarConfiguration config,
    required SupyBarcodeScannerController controller,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SupyActionBar(config: config, controller: controller),
      ),
    );
  }

  testWidgets('renders nothing when visible is false', (tester) async {
    final controller = SupyBarcodeScannerController();
    await tester.pumpWidget(
      host(
        config: const SupyActionBarConfiguration(visible: false),
        controller: controller,
      ),
    );
    expect(find.byType(Row), findsNothing);
    expect(find.byIcon(Icons.flash_off), findsNothing);
  });

  testWidgets('default config renders all four buttons', (tester) async {
    final controller = SupyBarcodeScannerController();
    await tester.pumpWidget(
      host(
        config: const SupyActionBarConfiguration(),
        controller: controller,
      ),
    );
    expect(find.byIcon(Icons.flash_off), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    expect(find.byIcon(Icons.flip_camera_ios), findsOneWidget);
    expect(find.byIcon(Icons.center_focus_strong), findsOneWidget);
  });

  testWidgets('hidden per-button specs omit individual buttons',
      (tester) async {
    final controller = SupyBarcodeScannerController();
    await tester.pumpWidget(
      host(
        config: const SupyActionBarConfiguration(
          flashButton: SupyActionButtonSpec(visible: false),
          zoomButton: SupyActionButtonSpec(visible: false),
          flipCameraButton: SupyActionButtonSpec(visible: false),
        ),
        controller: controller,
      ),
    );
    expect(find.byIcon(Icons.flash_off), findsNothing);
    expect(find.byIcon(Icons.zoom_in), findsNothing);
    expect(find.byIcon(Icons.flip_camera_ios), findsNothing);
    expect(find.byIcon(Icons.center_focus_strong), findsOneWidget);
  });

  testWidgets('renders nothing when every button is individually hidden',
      (tester) async {
    final controller = SupyBarcodeScannerController();
    await tester.pumpWidget(
      host(
        config: const SupyActionBarConfiguration(
          flashButton: SupyActionButtonSpec(visible: false),
          zoomButton: SupyActionButtonSpec(visible: false),
          flipCameraButton: SupyActionButtonSpec(visible: false),
          closeFocusButton: SupyActionButtonSpec(visible: false),
        ),
        controller: controller,
      ),
    );
    expect(find.byType(Row), findsNothing);
  });

  testWidgets('inactive flash button uses the inactive background color',
      (tester) async {
    final controller = SupyBarcodeScannerController();
    await tester.pumpWidget(
      host(
        config: const SupyActionBarConfiguration(
          zoomButton: SupyActionButtonSpec(visible: false),
          flipCameraButton: SupyActionButtonSpec(visible: false),
          closeFocusButton: SupyActionButtonSpec(visible: false),
          flashButton: SupyActionButtonSpec(
            backgroundColor: Color(0xFF111111),
            foregroundColor: Color(0xFF222222),
            activeBackgroundColor: Color(0xFF333333),
            activeForegroundColor: Color(0xFF444444),
          ),
        ),
        controller: controller,
      ),
    );
    final container = tester.widget<Container>(
      find.ancestor(
        of: find.byIcon(Icons.flash_off),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF111111));
    expect(decoration.shape, BoxShape.circle);
    final icon = tester.widget<Icon>(find.byIcon(Icons.flash_off));
    expect(icon.color, const Color(0xFF222222));
  });

  testWidgets('flash tap invokes setTorch on the controller channel',
      (tester) async {
    final controller = SupyBarcodeScannerController();
    const channel = MethodChannel('test/action_bar_flash');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    controller.attach(channel);
    addTearDown(() {
      controller.detach();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      host(
        config: const SupyActionBarConfiguration(
          zoomButton: SupyActionButtonSpec(visible: false),
          flipCameraButton: SupyActionButtonSpec(visible: false),
          closeFocusButton: SupyActionButtonSpec(visible: false),
        ),
        controller: controller,
      ),
    );
    await tester.tap(find.byIcon(Icons.flash_off));
    await tester.pump();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'setTorch');
    expect(calls.single.arguments, <String, Object?>{'on': true});
  });

  testWidgets('zoom button rerenders icon after controller notifies',
      (tester) async {
    final controller = SupyBarcodeScannerController();
    const channel = MethodChannel('test/action_bar_zoom');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setZoom') {
        return <String, Object?>{'zoom': 2.0};
      }
      return null;
    });
    controller.attach(channel);
    addTearDown(() {
      controller.detach();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      host(
        config: const SupyActionBarConfiguration(
          flashButton: SupyActionButtonSpec(visible: false),
          flipCameraButton: SupyActionButtonSpec(visible: false),
          closeFocusButton: SupyActionButtonSpec(visible: false),
        ),
        controller: controller,
      ),
    );
    // Pre-tap: zoom=1.0 → no label rendered, icon shown.
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    expect(find.text('2x'), findsNothing);

    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pumpAndSettle();
    // Post-tap: controller.zoom=2.0 → label '2x' replaces icon.
    expect(find.text('2x'), findsOneWidget);
  });
}
