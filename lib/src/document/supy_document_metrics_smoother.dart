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
/// Algorithm: per-scalar exponential moving average (EMA). For the quad, each
/// vertex is EMA'd independently.
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
    _perCornerStability =
        _smoothPerCorner(_perCornerStability, sample.perCornerStability);
    // liveQualityScore is opaque — pass the latest through without EMA so the
    // C++-computed value isn't re-filtered on Dart. The classifier already
    // smooths inputs on the C++ side; double-smoothing would just lag the
    // surfaced score.
    _liveQualityScore = sample.liveQualityScore ?? _liveQualityScore;
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

  List<Offset> _smoothQuad(List<Offset>? previous, List<Offset> sample) {
    if (previous == null || previous.length != sample.length) {
      return List<Offset>.unmodifiable(sample);
    }
    final smoothed = List<Offset>.generate(
      sample.length,
      (i) => Offset(
        previous[i].dx + alpha * (sample[i].dx - previous[i].dx),
        previous[i].dy + alpha * (sample[i].dy - previous[i].dy),
      ),
      growable: false,
    );
    return List<Offset>.unmodifiable(smoothed);
  }
}
