import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/document/supy_document_metrics_smoother.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// D3-2 — live-overlay smoothing parity across platforms.
///
/// The two embedded-view code paths smooth the rendered metrics differently:
///
/// - **Android** ships raw metrics only; `SupyDocumentScannerView` runs the Dart
///   `SupyDocumentStateMachine`, which smooths inside `tick()` and returns the
///   smoothed metrics on the frame.
/// - **iOS** ships a native-classified `state` plus a *raw* per-frame quad +
///   scalars; the view trusts the state but routes the raw metrics through a
///   standalone `SupyDocumentMetricsSmoother` (same `guidance.smoothingAlpha`)
///   before painting.
///
/// For the overlay to look identical on both platforms, those two smoothers must
/// produce byte-identical output for the same raw sequence and alpha. This test
/// locks that: if the iOS render path drops smoothing, uses a different alpha,
/// or the smoother diverges from the FSM's embedded one, this fails.
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

// A jittery hand-held sequence: the quad and scalars wobble frame to frame,
// exactly the input smoothing exists to stabilize.
final List<SupyDocumentFrameMetrics> _jitterySequence =
    <SupyDocumentFrameMetrics>[
      _doc(coverage: 0.60, tilt: 4.0, luma: 118.0, blur: 190.0),
      _doc(
        coverage: 0.66,
        tilt: 7.5,
        luma: 131.0,
        blur: 240.0,
        quad: const [
          Offset(0.12, 0.09),
          Offset(0.91, 0.11),
          Offset(0.88, 0.92),
          Offset(0.09, 0.88),
        ],
      ),
      _doc(
        coverage: 0.58,
        tilt: 2.5,
        luma: 122.0,
        blur: 205.0,
        quad: const [
          Offset(0.08, 0.12),
          Offset(0.93, 0.08),
          Offset(0.90, 0.89),
          Offset(0.11, 0.91),
        ],
      ),
      _doc(coverage: 0.71, tilt: 6.0, luma: 145.0, blur: 260.0),
    ];

void main() {
  group('render-smoothing parity (iOS render path vs Android FSM)', () {
    for (final alpha in const <double>[0.35, 0.2, 0.8]) {
      test('alpha=$alpha: smoothed metrics match frame-for-frame', () {
        final render = SupyDocumentMetricsSmoother(alpha: alpha);
        final fsm = SupyDocumentStateMachine(
          configuration: SupyDocumentGuidanceConfiguration(
            smoothingAlpha: alpha,
          ),
        );

        for (final raw in _jitterySequence) {
          final iosRendered = render.add(raw);
          final androidRendered = fsm.tick(raw).metrics;
          expect(
            iosRendered,
            equals(androidRendered),
            reason:
                'iOS render smoother diverged from the Android FSM smoother',
          );
        }
      });
    }

    test('a lost-document frame resets both paths identically', () {
      // Both default to the same alpha (0.35), so they stay in lockstep.
      final render = SupyDocumentMetricsSmoother();
      final fsm = SupyDocumentStateMachine();

      // Prime with present frames.
      for (final raw in _jitterySequence) {
        render.add(raw);
        fsm.tick(raw);
      }

      // Document leaves the frame → both smoothers pass through + reset.
      const gap = SupyDocumentFrameMetrics();
      expect(render.add(gap), equals(fsm.tick(gap).metrics));

      // Re-acquisition after the gap must start fresh on both paths (first
      // present sample passes through, so they stay in lockstep).
      final reacquired = _doc();
      expect(render.add(reacquired), equals(fsm.tick(reacquired).metrics));
    });
  });
}
