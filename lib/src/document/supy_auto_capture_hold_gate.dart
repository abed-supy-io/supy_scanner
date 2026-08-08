/// The transition a [SupyAutoCaptureHoldGate] reports for one frame.
enum SupyAutoCaptureHoldEdge {
  /// No change this frame — either still idle, or still holding within grace.
  none,

  /// The framed-steady signal was just acquired — start the countdown.
  acquired,

  /// The framed-steady signal was genuinely lost — cancel the countdown.
  lost,
}

/// Debounces auto-capture's "framed and steady" signal so a brief flicker out
/// of `ready` doesn't abort and restart the countdown.
///
/// The document view feeds one `ready` boolean per native frame. Both platforms
/// reach `ready` through the same Dart path — the Android embedded view
/// classifies in the Dart `SupyDocumentStateMachine`, while the iOS
/// native-classified `state` is trusted verbatim — so placing this debounce on
/// that shared boolean makes auto-capture hold **identically** on iOS and
/// Android: a one- or two-frame hand-held jitter (a momentary `handShake` /
/// `holdSteady` demotion) rides through instead of tearing down and restarting
/// the countdown sweep. Once [graceFrames] consecutive non-ready frames elapse
/// the hold breaks, so a document that genuinely leaves the frame still cancels
/// well inside the countdown window.
///
/// Pure and I/O-free — safe to drive from a test or the widget's event handler.
class SupyAutoCaptureHoldGate {
  /// Creates a gate tolerating [graceFrames] consecutive non-ready frames
  /// before an active hold breaks. The default (3 frames ≈ 100 ms at 30 fps)
  /// rides out typical hand-held jitter yet aborts far inside a 600 ms sweep.
  SupyAutoCaptureHoldGate({this.graceFrames = 3})
    : assert(graceFrames >= 0, 'graceFrames must be non-negative');

  /// Consecutive non-ready frames tolerated before the hold breaks.
  final int graceFrames;

  int _lossStreak = 0;
  bool _held = false;

  /// Whether the framed-steady signal is currently held (countdown sweeping).
  bool get isHeld => _held;

  /// Feeds one frame's readiness and returns the resulting [SupyAutoCaptureHoldEdge].
  SupyAutoCaptureHoldEdge update({required bool isReady}) {
    if (isReady) {
      _lossStreak = 0;
      if (_held) return SupyAutoCaptureHoldEdge.none;
      _held = true;
      return SupyAutoCaptureHoldEdge.acquired;
    }
    if (!_held) return SupyAutoCaptureHoldEdge.none;
    _lossStreak += 1;
    if (_lossStreak > graceFrames) {
      reset();
      return SupyAutoCaptureHoldEdge.lost;
    }
    // Within grace — keep holding through the blip.
    return SupyAutoCaptureHoldEdge.none;
  }

  /// Clears all hold state. Call when the preview is torn down or paused.
  void reset() {
    _held = false;
    _lossStreak = 0;
  }
}
