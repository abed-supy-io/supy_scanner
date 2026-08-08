import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/document/supy_document_metrics_smoother.dart';
import 'package:supy_scanner/supy_scanner.dart';

SupyDocumentFrameMetrics _doc({
  double coverage = 0.5,
  double tilt = 5.0,
  double luma = 120.0,
  double blur = 200.0,
  bool clipsEdge = false,
  List<Offset>? quad,
}) {
  return SupyDocumentFrameMetrics(
    quad:
        quad ??
        const [
          Offset(0.1, 0.1),
          Offset(0.9, 0.1),
          Offset(0.9, 0.9),
          Offset(0.1, 0.9),
        ],
    coverageRatio: coverage,
    tiltDegrees: tilt,
    meanLuma: luma,
    blurScore: blur,
    clipsEdge: clipsEdge,
  );
}

const _empty = SupyDocumentFrameMetrics();

void main() {
  group('SupyDocumentMetricsSmoother — construction', () {
    test('rejects alpha outside (0, 1]', () {
      expect(
        () => SupyDocumentMetricsSmoother(alpha: 0.0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => SupyDocumentMetricsSmoother(alpha: 1.5),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => SupyDocumentMetricsSmoother(alpha: -0.1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('hasSamples is false before any add()', () {
      final s = SupyDocumentMetricsSmoother();
      expect(s.hasSamples, isFalse);
      expect(s.current, equals(_empty));
    });
  });

  group('SupyDocumentMetricsSmoother — first frame', () {
    test('first frame passes through unchanged', () {
      final s = SupyDocumentMetricsSmoother();
      final raw = _doc(coverage: 0.7, tilt: 8.0, luma: 140.0, blur: 250.0);
      final out = s.add(raw);

      expect(out.coverageRatio, 0.7);
      expect(out.tiltDegrees, 8.0);
      expect(out.meanLuma, 140.0);
      expect(out.blurScore, 250.0);
      expect(out.quad, raw.quad);
      expect(out.hasDocument, isTrue);
      expect(s.hasSamples, isTrue);
    });
  });

  group('SupyDocumentMetricsSmoother — EMA behavior', () {
    test('converges toward a constant input', () {
      final s = SupyDocumentMetricsSmoother();
      // Seed with one frame, then push 50 frames at a different value.
      s.add(_doc(coverage: 0.2));
      for (var i = 0; i < 50; i++) {
        s.add(_doc(coverage: 0.8));
      }
      expect(s.current.coverageRatio, closeTo(0.8, 1e-6));
    });

    test('alpha=1.0 means no smoothing (passthrough)', () {
      final s = SupyDocumentMetricsSmoother(alpha: 1.0);
      s.add(_doc(coverage: 0.1));
      final out = s.add(_doc(coverage: 0.9));
      expect(out.coverageRatio, 0.9);
    });

    test('one EMA step matches the formula prev + alpha*(sample-prev)', () {
      const alpha = 0.4;
      final s = SupyDocumentMetricsSmoother(alpha: alpha);
      s.add(_doc(coverage: 0.2));
      final out = s.add(_doc(coverage: 1.0));
      expect(out.coverageRatio, closeTo(0.2 + alpha * (1.0 - 0.2), 1e-9));
    });

    test('quad vertices are EMA-blended independently', () {
      const alpha = 0.5;
      final s = SupyDocumentMetricsSmoother(alpha: alpha);
      s.add(
        _doc(
          quad: const [
            Offset(0.0, 0.0),
            Offset(1.0, 0.0),
            Offset(1.0, 1.0),
            Offset(0.0, 1.0),
          ],
        ),
      );
      final out = s.add(
        _doc(
          quad: const [
            Offset(0.2, 0.2),
            Offset(0.8, 0.2),
            Offset(0.8, 0.8),
            Offset(0.2, 0.8),
          ],
        ),
      );
      expect(out.quad[0], const Offset(0.1, 0.1));
      expect(out.quad[1], const Offset(0.9, 0.1));
      expect(out.quad[2], const Offset(0.9, 0.9));
      expect(out.quad[3], const Offset(0.1, 0.9));
    });

    test('smoothed quad is immutable', () {
      final s = SupyDocumentMetricsSmoother();
      final out = s.add(_doc());
      expect(() => out.quad.add(const Offset(0, 0)), throwsUnsupportedError);
    });
  });

  group('SupyDocumentMetricsSmoother — gap behavior', () {
    test('missing sample resets accumulators and passes through verbatim', () {
      final s = SupyDocumentMetricsSmoother(alpha: 0.5);
      s.add(_doc(coverage: 0.7));
      expect(s.hasSamples, isTrue);

      final passthrough = s.add(_empty);
      expect(passthrough, equals(_empty));
      expect(s.hasSamples, isFalse);

      // Next real detection seeds fresh (no lerp from pre-gap state).
      final out = s.add(_doc(coverage: 0.2));
      expect(out.coverageRatio, 0.2);
    });

    test('clipsEdge reflects the latest present sample (not smoothed)', () {
      final s = SupyDocumentMetricsSmoother();
      s.add(_doc());
      expect(s.current.clipsEdge, isFalse);
      s.add(_doc(clipsEdge: true));
      expect(s.current.clipsEdge, isTrue);
    });
  });

  group('SupyDocumentMetricsSmoother — reset()', () {
    test('reset() clears all accumulators', () {
      final s = SupyDocumentMetricsSmoother();
      s.add(_doc(coverage: 0.7));
      expect(s.hasSamples, isTrue);

      s.reset();
      expect(s.hasSamples, isFalse);
      expect(s.current, equals(_empty));

      // Next sample seeds fresh (no lerp from pre-reset values).
      final out = s.add(_doc(coverage: 0.3));
      expect(out.coverageRatio, 0.3);
    });
  });
}
