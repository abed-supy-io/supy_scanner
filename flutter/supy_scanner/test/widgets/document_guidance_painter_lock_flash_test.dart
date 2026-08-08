import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/widgets/supy_document_scanner_view.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// D3-3 — lock success feedback (edge flash) rendering.
///
/// The lock cue is triggered inside `_handleEvent`'s `ready` transition, which
/// can't be driven on desktop (no PlatformView), so this pins the *rendering
/// primitive* the cue drives: the guidance painter flashes the full quad
/// outline at `readyColor` while `lockFlash > 0` and draws nothing when idle.
/// Because both platforms feed the same painter off the same Dart `ready`
/// transition (see the D3-2 render-smoothing parity test), locking this
/// primitive locks the cross-platform behavior.
SupyDocumentGuidanceFrame _frameWithQuad() {
  return const SupyDocumentGuidanceFrame(
    state: SupyDocumentFrameState.ready,
    metrics: SupyDocumentFrameMetrics(
      quad: <Offset>[
        Offset(0.1, 0.1),
        Offset(0.9, 0.1),
        Offset(0.9, 0.9),
        Offset(0.1, 0.9),
      ],
    ),
    framesAtState: 5,
  );
}

Future<ui.Image> _paint(CustomPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  return picture.toImage(size.width.toInt(), size.height.toInt());
}

Future<({int r, int g, int b, int a})> _pixel(
  ui.Image image,
  int x,
  int y,
) async {
  final data = await image.toByteData();
  final bytes = Uint8List.view(data!.buffer);
  final offset = (y * image.width + x) * 4;
  return (
    r: bytes[offset],
    g: bytes[offset + 1],
    b: bytes[offset + 2],
    a: bytes[offset + 3],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = Size(200, 200);

  // Isolate the flash: everything but `readyColor` is transparent. The top edge
  // midpoint (100, 20) is only ever painted by the full-quad flash — the corner
  // brackets stop 22px in from each corner, so they never reach it.
  CustomPainter build({double lockFlash = 0.0}) {
    return makeDocumentGuidancePainter(
      frame: _frameWithQuad(),
      scrimColor: const Color(0x00000000),
      bracketColor: const Color(0x00000000),
      pulseValue: 0.0,
      warningColor: const Color(0x00000000),
      readyColor: const Color(0xFFFF0000),
      lockFlash: lockFlash,
    );
  }

  group('document guidance painter lock flash', () {
    test('paints the full quad outline at peak intensity', () async {
      final image = await _paint(build(lockFlash: 1.0), size);
      final px = await _pixel(image, 100, 20);
      expect(px.a, greaterThan(200), reason: 'edge opaque during the flash');
      expect(px.r, greaterThan(200), reason: 'edge is readyColor (red)');
    });

    test('mid-edge is untouched when idle (default lockFlash)', () async {
      // The default (untriggered) lockFlash is 0 — no outline is drawn.
      final image = await _paint(build(), size);
      final px = await _pixel(image, 100, 20);
      expect(px.a, lessThan(10), reason: 'no outline flashed while idle');
    });

    test(
      'flash alpha tracks lockFlash (half intensity is translucent)',
      () async {
        final image = await _paint(build(lockFlash: 0.5), size);
        final px = await _pixel(image, 100, 20);
        expect(px.a, greaterThan(90));
        expect(px.a, lessThan(180));
      },
    );

    test('shouldRepaint is driven by lockFlash changes', () {
      final a = build(lockFlash: 0.4);
      final b = build(lockFlash: 0.6);
      final same = build(lockFlash: 0.4);
      expect(a.shouldRepaint(b), isTrue);
      expect(a.shouldRepaint(same), isFalse);
    });
  });
}
