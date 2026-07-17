import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/ui/supy_view_finder_configuration.dart';
import 'package:supy_scanner/src/widgets/supy_finder_painter.dart';

/// A Canvas stand-in that records the path/paint pairs handed to [drawPath]
/// and ignores everything else. Lets us assert paint behavior without
/// committing a flaky image-golden baseline.
class _RecordingCanvas implements Canvas {
  final List<Path> drawnPaths = <Path>[];
  final List<Paint> paints = <Paint>[];

  @override
  void drawPath(Path path, Paint paint) {
    drawnPaths.add(path);
    paints.add(paint);
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() {
  const visibleConfig = SupyViewFinderConfiguration();

  group('SupyFinderPainter.paint', () {
    test('invisible config draws nothing', () {
      const config = SupyViewFinderConfiguration(visible: false);
      final canvas = _RecordingCanvas();
      SupyFinderPainter(config: config).paint(canvas, const Size(400, 300));
      expect(canvas.drawnPaths, isEmpty);
    });

    test('default cornered style draws exactly 4 paths (one per corner)', () {
      final canvas = _RecordingCanvas();
      SupyFinderPainter(
        config: visibleConfig,
      ).paint(canvas, const Size(400, 300));
      expect(canvas.drawnPaths, hasLength(4));
    });

    test('every drawn path uses stroke style with the configured color', () {
      const style = SupyFinderCorneredStyle(
        strokeColor: Color(0xFFAB12CD),
        strokeWidth: 5.0,
      );
      const config = SupyViewFinderConfiguration(style: style);
      final canvas = _RecordingCanvas();
      SupyFinderPainter(config: config).paint(canvas, const Size(400, 300));
      expect(canvas.paints, hasLength(4));
      for (final p in canvas.paints) {
        expect(p.style, PaintingStyle.stroke);
        expect(p.color.toARGB32(), const Color(0xFFAB12CD).toARGB32());
        expect(p.strokeWidth, 5.0);
      }
    });

    test('finder rect is centered and ≤85% of the canvas', () {
      final canvas = _RecordingCanvas();
      const size = Size(400, 200);
      SupyFinderPainter(config: visibleConfig).paint(canvas, size);

      final unioned = canvas.drawnPaths
          .map((p) => p.getBounds())
          .reduce((a, b) => a.expandToInclude(b));

      // Fit rect for 16:9 inside 400x200 with 0.85 margin:
      // maxW=340, maxH=170 → height-limited → w=170*16/9 ≈ 302.22, h=170.
      // Centered: left ≈ 48.89, top=15.
      // The path bounds include corner arms (length 24), so the unioned
      // rect should be exactly the fit rect — corners sit ON the fit rect.
      expect(unioned.center.dx, closeTo(size.width / 2, 0.5));
      expect(unioned.center.dy, closeTo(size.height / 2, 0.5));
      expect(unioned.width, lessThanOrEqualTo(size.width * 0.85 + 0.5));
      expect(unioned.height, lessThanOrEqualTo(size.height * 0.85 + 0.5));
    });

    test('finder rect honors the configured aspect ratio', () {
      final canvas = _RecordingCanvas();
      const config = SupyViewFinderConfiguration(
        aspectRatio: SupyAspectRatio(1, 1),
      );
      const size = Size(400, 400);
      SupyFinderPainter(config: config).paint(canvas, size);

      final unioned = canvas.drawnPaths
          .map((p) => p.getBounds())
          .reduce((a, b) => a.expandToInclude(b));
      // 1:1 ratio → unioned bounds are square (within rounding).
      expect(unioned.width, closeTo(unioned.height, 0.5));
    });
  });

  group('SupyFinderPainter.shouldRepaint', () {
    test('returns false when config is identical', () {
      final a = SupyFinderPainter(config: visibleConfig);
      final b = SupyFinderPainter(config: visibleConfig);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('returns true when visibility flips', () {
      final a = SupyFinderPainter(config: visibleConfig);
      final b = SupyFinderPainter(
        config: const SupyViewFinderConfiguration(visible: false),
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    test('returns true when stroke color changes', () {
      final a = SupyFinderPainter(config: visibleConfig);
      final b = SupyFinderPainter(
        config: const SupyViewFinderConfiguration(
          style: SupyFinderCorneredStyle(strokeColor: Color(0xFFFF0000)),
        ),
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    test('returns true when aspect ratio changes', () {
      final a = SupyFinderPainter(config: visibleConfig);
      final b = SupyFinderPainter(
        config: const SupyViewFinderConfiguration(
          aspectRatio: SupyAspectRatio(1, 1),
        ),
      );
      expect(a.shouldRepaint(b), isTrue);
    });
  });
}
