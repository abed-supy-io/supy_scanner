import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/supy_document_frame_metrics.dart';

/// Low-pass filter that turns the noisy per-frame [SupyDocumentFrameMetrics]
/// stream into a temporally-stable signal the state machine can reason about.
///
/// Why this exists: raw native metrics jitter — coverage shifts a few percent
/// frame-to-frame, the detected quad vertices wobble by 1–2px, blur scores
/// spike when a finger crosses the lens. Without smoothing, the state machine
/// flips between `tooFar` / `ready` / `blurry` faster than the human eye can
/// read the hint card.
///
/// Algorithm: per-scalar exponential moving average (EMA). The quad gets a
/// smarter treatment than the scalars — see [_smoothQuad]:
///  1. **Corner correspondence.** The incoming four corners are reindexed to
///     the cyclic rotation that best lines up with the previous smoothed quad
///     before blending. Vision re-labels which physical corner is "top-left"
///     when the page rotates even slightly, so a blind vertex-by-index EMA
///     would average two *different* physical corners and the outline would
///     visibly rotate/tear. Matching first makes the overlay stick.
///  2. **Velocity-adaptive alpha (One-Euro-lite).** A single fixed alpha forces
///     a bad tradeoff: low = steady when still but laggy/rubber-banding when the
///     user repositions; high = responsive but jittery at rest. Instead the
///     quad's blend weight ramps from [alpha] (barely moving → smooth hard) up
///     toward [_quadFastAlpha] (deliberate reposition → track without lag).
///
/// The scalars keep the plain fixed-alpha EMA: they feed the Android state
/// machine's gating thresholds, so their temporal response is deliberately left
/// unchanged. Only the *rendered quad* gets the adaptive treatment.
///
/// Detection-presence boundary: when the raw sample reports no document
/// (`hasDocument == false`), the smoother **resets** and returns the empty
/// sample verbatim. This intentionally hands the "should I tolerate a brief
/// gap?" decision to the state-machine layer (which already has
/// `lostDocumentGraceFrames`) instead of duplicating it here. As a side
/// effect, when detection returns, the smoother seeds cleanly from the new
/// quad — no lerping from a stale, off-screen position.
class SupyDocumentMetricsSmoother {
  /// Creates a smoother. `alpha` is the new-sample weight in `(0, 1]`:
  /// `1.0` = no smoothing (passthrough), small = very smooth (laggy).
  /// Default `0.35` reaches ~90% of a step input in ~6 frames at 30fps.
  SupyDocumentMetricsSmoother({this.alpha = 0.35})
    : assert(alpha > 0 && alpha <= 1.0, 'alpha must be in (0, 1]');

  /// EMA weight on the new sample. Higher = more responsive, lower = smoother.
  final double alpha;

  // Smoothed scalars + quad. `null` means "no sample yet — seed on next frame".
  double? _coverage;
  double? _tilt;
  double? _luma;
  double? _blur;
  double? _stability;
  double? _interior;
  double? _glare;
  double? _cornerVelocity;
  double? _centerOffsetX;
  double? _centerOffsetY;
  List<double>? _perCornerStability;
  double? _liveQualityScore;
  double? _sourceAspectRatio;
  List<Offset>? _quad;
  bool _lastClipsEdge = false;

  /// `true` once at least one frame has been ingested since the last reset.
  bool get hasSamples =>
      _coverage != null ||
      _tilt != null ||
      _luma != null ||
      _blur != null ||
      _stability != null ||
      _interior != null ||
      _glare != null ||
      _cornerVelocity != null ||
      _perCornerStability != null ||
      _liveQualityScore != null ||
      _quad != null;

  /// Smoothed metrics derived from the stream so far. Returns the zero-default
  /// metrics until [add] is called with a present sample.
  SupyDocumentFrameMetrics get current {
    if (_quad == null) return const SupyDocumentFrameMetrics();
    return SupyDocumentFrameMetrics(
      quad: _quad!,
      coverageRatio: _coverage ?? 0.0,
      tiltDegrees: _tilt ?? 0.0,
      meanLuma: _luma ?? 0.0,
      blurScore: _blur ?? 0.0,
      clipsEdge: _lastClipsEdge,
      quadStability: _stability ?? 0.0,
      interiorVariance: _interior ?? 0.0,
      glareRatio: _glare ?? 0.0,
      cornerVelocity: _cornerVelocity ?? 0.0,
      centerOffsetX: _centerOffsetX ?? 0.0,
      centerOffsetY: _centerOffsetY ?? 0.0,
      perCornerStability: _perCornerStability ?? const <double>[],
      liveQualityScore: _liveQualityScore,
      sourceAspectRatio: _sourceAspectRatio,
    );
  }

  /// Feeds one raw sample. Returns the smoothed view after applying it.
  /// A missing-document sample passes through verbatim and resets the
  /// internal accumulators so the next detection seeds cleanly.
  SupyDocumentFrameMetrics add(SupyDocumentFrameMetrics sample) {
    if (!sample.hasDocument) {
      reset();
      return sample;
    }
    _lastClipsEdge = sample.clipsEdge;
    _coverage = _ema(_coverage, sample.coverageRatio);
    _tilt = _ema(_tilt, sample.tiltDegrees);
    _luma = _ema(_luma, sample.meanLuma);
    _blur = _ema(_blur, sample.blurScore);
    _stability = _ema(_stability, sample.quadStability);
    _interior = _ema(_interior, sample.interiorVariance);
    _glare = _ema(_glare, sample.glareRatio);
    _cornerVelocity = _ema(_cornerVelocity, sample.cornerVelocity);
    _centerOffsetX = _ema(_centerOffsetX, sample.centerOffsetX);
    _centerOffsetY = _ema(_centerOffsetY, sample.centerOffsetY);
    _perCornerStability = _smoothPerCorner(
      _perCornerStability,
      sample.perCornerStability,
    );
    // liveQualityScore is opaque — pass the latest through without EMA so the
    // C++-computed value isn't re-filtered on Dart. The classifier already
    // smooths inputs on the C++ side; double-smoothing would just lag the
    // surfaced score.
    _liveQualityScore = sample.liveQualityScore ?? _liveQualityScore;
    // Source aspect is a per-session constant (camera format doesn't change
    // mid-stream). Hold the latest non-null so an occasional frame that omits
    // it doesn't drop the overlay's crop correction back to identity.
    _sourceAspectRatio = sample.sourceAspectRatio ?? _sourceAspectRatio;
    _quad = _smoothQuad(_quad, sample.quad);
    return current;
  }

  /// Clears all accumulated state. Call when the camera session is torn down
  /// or the user manually retries.
  void reset() {
    _coverage = null;
    _tilt = null;
    _luma = null;
    _blur = null;
    _stability = null;
    _interior = null;
    _glare = null;
    _cornerVelocity = null;
    _centerOffsetX = null;
    _centerOffsetY = null;
    _perCornerStability = null;
    _liveQualityScore = null;
    _sourceAspectRatio = null;
    _quad = null;
    _lastClipsEdge = false;
  }

  double _ema(double? previous, double sample) {
    if (previous == null) return sample;
    return previous + alpha * (sample - previous);
  }

  /// Per-corner EMA. If the incoming sample doesn't carry four corner values
  /// (which the native sides only emit when a quad is present), treat this as
  /// "no signal this frame" and hold whatever we already had — that way one
  /// dropped detection doesn't reset the corner stability history.
  List<double>? _smoothPerCorner(List<double>? previous, List<double> sample) {
    if (sample.length != 4) return previous;
    if (previous == null || previous.length != 4) {
      return List<double>.unmodifiable(sample);
    }
    final smoothed = List<double>.generate(
      4,
      (i) => previous[i] + alpha * (sample[i] - previous[i]),
      growable: false,
    );
    return List<double>.unmodifiable(smoothed);
  }

  /// Upper bound on the quad's adaptive blend weight. Reached when the matched
  /// corners move by [_quadFastMotion] or more between frames — a deliberate
  /// reposition, where tracking beats smoothing. Near-1.0 so the outline snaps
  /// to a fast-moving page without a visible trail.
  static const double _quadFastAlpha = 0.9;

  /// Mean per-corner motion (normalized preview units) at or below which the
  /// quad is treated as "at rest" and smoothed at the baseline [alpha]. ~0.4%
  /// of the frame — sensor/detector wobble on a held-still page lives here.
  static const double _quadStillMotion = 0.004;

  /// Mean per-corner motion at or above which the quad is treated as a
  /// deliberate reposition and smoothed at [_quadFastAlpha]. ~3% of the frame.
  static const double _quadFastMotion = 0.03;

  /// Smooths the rendered quad with corner correspondence + a velocity-adaptive
  /// blend weight. See the class doc for the why.
  List<Offset> _smoothQuad(List<Offset>? previous, List<Offset> sample) {
    if (previous == null || previous.length != sample.length) {
      return List<Offset>.unmodifiable(sample);
    }
    // 1. Reindex the sample to the corner ordering that best matches `previous`,
    //    so the EMA blends the same physical corner frame-to-frame.
    final matched =
        sample.length == 4 ? _matchCorners(previous, sample) : sample;
    // 2. Adapt the blend weight to how far the (matched) corners moved.
    final a = _adaptiveQuadAlpha(previous, matched);
    final smoothed = List<Offset>.generate(
      matched.length,
      (i) => Offset(
        previous[i].dx + a * (matched[i].dx - previous[i].dx),
        previous[i].dy + a * (matched[i].dy - previous[i].dy),
      ),
      growable: false,
    );
    return List<Offset>.unmodifiable(smoothed);
  }

  /// Returns [sample] reindexed by the cyclic rotation (0..3) that minimizes the
  /// summed squared distance to [previous]. Only cyclic rotations are tried:
  /// Vision preserves quad winding, so a corner relabel manifests as the
  /// TL→TR→BR→BL sequence rotating, never reflecting. When the corners already
  /// correspond, rotation 0 wins and the sample is returned unchanged.
  static List<Offset> _matchCorners(
    List<Offset> previous,
    List<Offset> sample,
  ) {
    var bestRotation = 0;
    var bestCost = double.infinity;
    for (var r = 0; r < 4; r++) {
      var cost = 0.0;
      for (var i = 0; i < 4; i++) {
        final s = sample[(i + r) % 4];
        final dx = s.dx - previous[i].dx;
        final dy = s.dy - previous[i].dy;
        cost += dx * dx + dy * dy;
      }
      if (cost < bestCost) {
        bestCost = cost;
        bestRotation = r;
      }
    }
    if (bestRotation == 0) return sample;
    return List<Offset>.generate(
      4,
      (i) => sample[(i + bestRotation) % 4],
      growable: false,
    );
  }

  /// Maps the mean per-corner motion between [previous] and [matched] onto a
  /// blend weight in `[alpha, _quadFastAlpha]` via a smoothstep between the
  /// still/fast motion thresholds. Barely-moving → [alpha] (smooth); deliberate
  /// reposition → [_quadFastAlpha] (track).
  double _adaptiveQuadAlpha(List<Offset> previous, List<Offset> matched) {
    final n = matched.length;
    if (n == 0) return alpha;
    var sumDist = 0.0;
    for (var i = 0; i < n; i++) {
      sumDist += (matched[i] - previous[i]).distance;
    }
    final motion = sumDist / n;
    // Never fall below the caller's baseline: a very smooth config (tiny alpha)
    // still smooths at rest, but adaptivity can only ever speed tracking up.
    final fast = math.max(alpha, _quadFastAlpha);
    if (motion <= _quadStillMotion) return alpha;
    if (motion >= _quadFastMotion) return fast;
    final t =
        (motion - _quadStillMotion) / (_quadFastMotion - _quadStillMotion);
    final eased = t * t * (3 - 2 * t); // smoothstep
    return alpha + (fast - alpha) * eased;
  }
}
