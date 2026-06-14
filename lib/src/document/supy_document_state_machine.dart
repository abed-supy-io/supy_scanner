import '../models/supy_document_frame_metrics.dart';
import '../models/supy_document_frame_state.dart';
import '../models/ui/supy_document_guidance_configuration.dart';
import 'supy_document_metrics_smoother.dart';

/// Pure-Dart state machine that turns per-frame [SupyDocumentFrameMetrics]
/// into a [SupyDocumentGuidanceFrame].
///
/// Pipeline (per tick):
///   raw metrics → EMA smoother → classify → hysteresis bands → min-dwell.
///
/// Responsibilities:
/// 1. Temporally smooth raw metrics so the overlay glides instead of jitters.
/// 2. Classify each frame against the thresholds in
///    [SupyDocumentGuidanceConfiguration], applying *exit-margin* hysteresis
///    so the hint doesn't bounce when a metric hovers at a threshold.
/// 3. Require `readyStableFrames` consecutive good frames before `ready`.
/// 4. Suppress lower-or-equal-priority transitions until the current state
///    has dwelled at least `minDwellFrames` — higher-priority issues
///    preempt unconditionally.
/// 5. Tolerate `lostDocumentGraceFrames` of missing detection.
///
/// Owns no I/O. Safe to drive from a test or a real stream.
class SupyDocumentStateMachine {
  /// Creates a state machine bound to [configuration].
  SupyDocumentStateMachine({
    SupyDocumentGuidanceConfiguration configuration =
        const SupyDocumentGuidanceConfiguration(),
  })  : _configuration = configuration,
        _smoother = SupyDocumentMetricsSmoother(
          alpha: configuration.smoothingAlpha,
        );

  SupyDocumentGuidanceConfiguration _configuration;
  SupyDocumentMetricsSmoother _smoother;

  /// Active configuration (thresholds + copy + palette).
  SupyDocumentGuidanceConfiguration get configuration => _configuration;

  /// Replaces the active configuration. If the smoothing alpha changed, the
  /// smoother is rebuilt — but existing streaks / state are preserved so a
  /// runtime threshold tweak doesn't snap the overlay.
  set configuration(SupyDocumentGuidanceConfiguration next) {
    if (next.smoothingAlpha != _configuration.smoothingAlpha) {
      _smoother = SupyDocumentMetricsSmoother(alpha: next.smoothingAlpha);
    }
    _configuration = next;
  }

  SupyDocumentFrameState _state = SupyDocumentFrameState.noDocument;
  SupyDocumentFrameMetrics _lastSmoothed = const SupyDocumentFrameMetrics();
  int _framesAtState = 0;
  int _goodStreak = 0;
  int _missingStreak = 0;

  /// The most recent classification.
  SupyDocumentFrameState get state => _state;

  /// Feeds one raw frame's metrics in, returns the resulting guidance frame.
  ///
  /// The frame returned carries the **smoothed** metrics — UI overlays should
  /// render from these so the quad outline tweens between detections.
  SupyDocumentGuidanceFrame tick(SupyDocumentFrameMetrics rawMetrics) {
    final smoothed = _smoother.add(rawMetrics);
    _lastSmoothed = smoothed;

    final next = _classify(smoothed);
    _commit(next);

    return SupyDocumentGuidanceFrame(
      state: _state,
      metrics: smoothed,
      framesAtState: _framesAtState,
    );
  }

  void _commit(SupyDocumentFrameState next) {
    if (next == _state) {
      _framesAtState += 1;
      return;
    }
    // Dwell exists to keep failure-hint copy on-screen long enough to read.
    // It should NEVER block terminal transitions: acquiring/losing the doc
    // and promotion to / demotion from `ready` are user-visible events the
    // overlay must reflect immediately.
    final isTerminalTransition =
        next == SupyDocumentFrameState.noDocument ||
            _state == SupyDocumentFrameState.noDocument ||
            next == SupyDocumentFrameState.ready ||
            _state == SupyDocumentFrameState.ready;
    // Higher priority (lower index) preempts immediately; otherwise hold
    // until min-dwell satisfied so we don't ping-pong out of a hint the user
    // hasn't had time to read.
    if (isTerminalTransition ||
        _priority(next) < _priority(_state) ||
        _framesAtState >= _configuration.minDwellFrames) {
      _state = next;
      _framesAtState = 1;
    } else {
      _framesAtState += 1;
    }
  }

  /// Resets all hysteresis / smoothing state. Call when the preview is paused
  /// or the underlying camera session is torn down.
  void reset() {
    _state = SupyDocumentFrameState.noDocument;
    _lastSmoothed = const SupyDocumentFrameMetrics();
    _framesAtState = 0;
    _goodStreak = 0;
    _missingStreak = 0;
    _smoother.reset();
  }

  /// Snapshot of the most recently processed (smoothed) metrics.
  SupyDocumentFrameMetrics get lastMetrics => _lastSmoothed;

  SupyDocumentFrameState _classify(SupyDocumentFrameMetrics m) {
    final c = _configuration;
    // A quad with too-low interior variance (e.g. a phone screen showing a
    // single flat image) is not a usable document — fold it into the
    // missing-doc branch so the FSM degrades to `noDocument` rather than
    // surfacing `holdSteady` on a non-document surface.
    final hasUsableDoc =
        m.hasDocument && m.interiorVariance >= c.interiorVarianceFloor;
    if (!hasUsableDoc) {
      _goodStreak = 0;
      _missingStreak += 1;
      if (_missingStreak <= c.lostDocumentGraceFrames &&
          _state != SupyDocumentFrameState.noDocument) {
        return _state;
      }
      return SupyDocumentFrameState.noDocument;
    }
    _missingStreak = 0;

    final failing = _firstFailure(m);
    if (failing != null) {
      _goodStreak = 0;
      return failing;
    }

    // All hard failures pass — but require quad stability before promoting
    // to `ready`. While holding in `holdSteady`, relax the floor by
    // `exitMargin` so we don't bounce out on a micro-jitter.
    final stabilityFloor = _state == SupyDocumentFrameState.holdSteady
        ? c.readyStabilityFloor * (1.0 - c.exitMargin)
        : c.readyStabilityFloor;
    if (m.quadStability < stabilityFloor) {
      _goodStreak = 0;
      return SupyDocumentFrameState.holdSteady;
    }

    _goodStreak += 1;
    final framesNeeded = _state == SupyDocumentFrameState.holdSteady
        ? c.holdSteadyFrames
        : c.readyStableFrames;
    if (_goodStreak >= framesNeeded) {
      return SupyDocumentFrameState.ready;
    }
    return _holdingState();
  }

  SupyDocumentFrameState _holdingState() {
    // While accumulating good frames toward `ready`, keep the overlay on the
    // last non-ready failure if there was one, otherwise show `blurry` as a
    // safe "hold steady" hint.
    if (_state == SupyDocumentFrameState.ready) {
      return SupyDocumentFrameState.ready;
    }
    if (_state == SupyDocumentFrameState.noDocument) {
      return SupyDocumentFrameState.blurry;
    }
    return _state;
  }

  /// Returns the first failing condition in priority order, or `null` when
  /// every check passes. Each comparison uses a *state-aware* threshold:
  /// if we are currently failing on this dimension, the threshold is relaxed
  /// by `exitMargin` so the state holds through small jitter at the band.
  SupyDocumentFrameState? _firstFailure(SupyDocumentFrameMetrics m) {
    final c = _configuration;
    final loose = 1.0 + c.exitMargin; // for "must be above" floors
    final tight = 1.0 - c.exitMargin; // for "must be below" ceilings

    final minLuma = _state == SupyDocumentFrameState.tooDark
        ? c.minMeanLuma * loose
        : c.minMeanLuma;
    if (m.meanLuma < minLuma) return SupyDocumentFrameState.tooDark;

    if (m.clipsEdge) return SupyDocumentFrameState.tooClose;
    final maxCov = _state == SupyDocumentFrameState.tooClose
        ? c.maxCoverageRatio * tight
        : c.maxCoverageRatio;
    if (m.coverageRatio > maxCov) return SupyDocumentFrameState.tooClose;

    final minCov = _state == SupyDocumentFrameState.tooFar
        ? c.minCoverageRatio * loose
        : c.minCoverageRatio;
    if (m.coverageRatio < minCov) return SupyDocumentFrameState.tooFar;

    final maxTilt = _state == SupyDocumentFrameState.tooSkewed
        ? c.maxTiltDegrees * tight
        : c.maxTiltDegrees;
    if (m.tiltDegrees > maxTilt) return SupyDocumentFrameState.tooSkewed;

    final minBlur = _state == SupyDocumentFrameState.blurry
        ? c.minBlurScore * loose
        : c.minBlurScore;
    if (m.blurScore < minBlur) return SupyDocumentFrameState.blurry;
    return null;
  }

  /// Priority ordering for min-dwell preemption: smaller = more urgent.
  /// Matches the order in which [_firstFailure] surfaces issues.
  static int _priority(SupyDocumentFrameState s) {
    switch (s) {
      case SupyDocumentFrameState.noDocument:
        return 0;
      case SupyDocumentFrameState.tooDark:
        return 1;
      case SupyDocumentFrameState.tooClose:
        return 2;
      case SupyDocumentFrameState.tooFar:
        return 3;
      case SupyDocumentFrameState.tooSkewed:
        return 4;
      case SupyDocumentFrameState.blurry:
        return 5;
      case SupyDocumentFrameState.holdSteady:
        // Sits between `blurry` and `ready`: all hard quality checks pass,
        // but the quad still needs to settle before we promote.
        return 6;
      case SupyDocumentFrameState.ready:
        return 7;
      case SupyDocumentFrameState.capturing:
      case SupyDocumentFrameState.captured:
        // UI-only terminal states — the FSM never classifies into them so
        // this branch is unreachable. Treated as least-urgent for the sake of
        // the exhaustive switch.
        return 8;
    }
  }
}
