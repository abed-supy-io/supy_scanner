import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

import 'supy_document_frame_metrics.dart';

/// Classification of a single camera frame for the document scanner.
///
/// Ordering reflects priority — when multiple conditions fail, the earliest
/// variant wins. Used to drive the guidance overlay color + hint text.
enum SupyDocumentFrameState {
  /// No document detected in the frame.
  noDocument,

  /// Detected, but the scene is too dark to capture cleanly.
  tooDark,

  /// Detected quad clips the preview edge or covers too much of it.
  tooClose,

  /// Detected quad covers too little of the preview.
  tooFar,

  /// Detected quad is rotated/skewed beyond the tilt threshold.
  tooSkewed,

  /// Sharpness is below the blur threshold — likely motion or focus.
  blurry,

  /// All checks pass for enough consecutive frames — safe to capture.
  ready,

  /// A capture has been triggered (either auto-capture delay elapsed or
  /// `controller.capture()` was called) and the native side is rectifying.
  /// UI-only — never produced by the state machine classifier.
  capturing,

  /// Capture finished; the rectified page is in hand. UI-only — terminal,
  /// the view returns to `noDocument` / `ready` on the next frame tick.
  captured,
}

/// One tick of guidance output: the classified [state], the original [quad]
/// to draw, and the [metrics] it was classified from.
///
/// Emitted by `SupyDocumentStateMachine.tick` and consumed by the overlay
/// widget.
@immutable
class SupyDocumentGuidanceFrame {
  /// Creates a guidance frame.
  const SupyDocumentGuidanceFrame({
    required this.state,
    required this.metrics,
    required this.framesAtState,
  });

  /// Current classification.
  final SupyDocumentFrameState state;

  /// The metrics this classification was derived from.
  final SupyDocumentFrameMetrics metrics;

  /// Consecutive frames spent at [state]. Useful for hysteresis-aware UIs
  /// (e.g. shutter button disabled until N stable ready frames).
  final int framesAtState;

  /// Convenience: the document outline (possibly empty) to render.
  List<Offset> get quad => metrics.quad;

  /// `true` when the state machine considers the frame capture-ready.
  bool get isReady => state == SupyDocumentFrameState.ready;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentGuidanceFrame &&
          other.state == state &&
          other.metrics == metrics &&
          other.framesAtState == framesAtState;

  @override
  int get hashCode => Object.hash(state, metrics, framesAtState);

  @override
  String toString() =>
      'SupyDocumentGuidanceFrame(${state.name} × $framesAtState)';
}
