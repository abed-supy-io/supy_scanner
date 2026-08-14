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

    test(
      'quad vertices are EMA-blended independently at the still baseline',
      () {
        // A tiny per-corner move keeps the quad in the "at rest" regime, where
        // the adaptive weight collapses to the baseline alpha and each vertex is
        // blended independently by that alpha.
        const alpha = 0.5;
        const d =
            0.002; // mean corner motion ~0.0028 < _quadStillMotion (0.004)
        final s = SupyDocumentMetricsSmoother(alpha: alpha);
        s.add(
          _doc(
            quad: const [
              Offset(0.10, 0.10),
              Offset(0.90, 0.10),
              Offset(0.90, 0.90),
              Offset(0.10, 0.90),
            ],
          ),
        );
        final out = s.add(
          _doc(
            quad: const [
              Offset(0.10 + d, 0.10 + d),
              Offset(0.90 + d, 0.10 + d),
              Offset(0.90 + d, 0.90 + d),
              Offset(0.10 + d, 0.90 + d),
            ],
          ),
        );
        expect(out.quad[0].dx, closeTo(0.10 + alpha * d, 1e-9));
        expect(out.quad[0].dy, closeTo(0.10 + alpha * d, 1e-9));
        expect(out.quad[2].dx, closeTo(0.90 + alpha * d, 1e-9));
        expect(out.quad[2].dy, closeTo(0.90 + alpha * d, 1e-9));
      },
    );

    test('a large reposition tracks at the fast alpha, not the baseline', () {
      // A big per-corner jump is a deliberate reposition: the adaptive weight
      // ramps to ~0.9 so the outline follows without rubber-banding, well past
      // what the 0.5 baseline would produce.
      const alpha = 0.5;
      final s = SupyDocumentMetricsSmoother(alpha: alpha);
      s.add(
        _doc(
          quad: const [
            Offset(0.10, 0.10),
            Offset(0.90, 0.10),
            Offset(0.90, 0.90),
            Offset(0.10, 0.90),
          ],
        ),
      );
      final out = s.add(
        _doc(
          quad: const [
            Offset(0.30, 0.30),
            Offset(1.10, 0.30),
            Offset(1.10, 1.10),
            Offset(0.30, 1.10),
          ],
        ),
      );
      // Fast alpha is max(alpha, 0.9) = 0.9 → 0.10 + 0.9 * 0.20 = 0.28.
      expect(out.quad[0].dx, closeTo(0.28, 1e-9));
      // Strictly past the baseline result (0.20), proving adaptivity kicked in.
      expect(out.quad[0].dx, greaterThan(0.10 + alpha * 0.20));
    });

    test(
      'a corner relabel is matched back instead of blended across corners',
      () {
        // Vision can rotate which physical corner it calls "top-left" between
        // frames. A blind index-wise EMA would then average two different
        // corners and the outline would spin. Correspondence must reindex the
        // relabeled sample back onto the stable quad, leaving it essentially
        // unchanged (zero motion → baseline alpha → no drift).
        final s = SupyDocumentMetricsSmoother(alpha: 0.5);
        const stable = [
          Offset(0.10, 0.10),
          Offset(0.90, 0.10),
          Offset(0.90, 0.90),
          Offset(0.10, 0.90),
        ];
        s.add(_doc(quad: stable));
        // Same physical quad, cyclically relabeled by one corner.
        final relabeled = [stable[1], stable[2], stable[3], stable[0]];
        final out = s.add(_doc(quad: relabeled));
        for (var i = 0; i < 4; i++) {
          expect(out.quad[i].dx, closeTo(stable[i].dx, 1e-9));
          expect(out.quad[i].dy, closeTo(stable[i].dy, 1e-9));
        }
      },
    );

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
