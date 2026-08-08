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

  /// Sharpness is below the blur threshold — defocus / static unsharpness.
  /// Distinct from [handShake]: this state is driven by `blurScore` alone.
  blurry,

  /// Specular highlight burns across the quad — bright reflection on glossy
  /// paper / lamination. User needs to change angle or move the light source.
  glare,

  /// Finger / hand intrudes on the quad — one or more corners are visually
  /// unstable in a way that doesn't correspond to camera shake. Driven by
  /// per-corner stability falling below the floor.
  occluded,

  /// Camera shake — corner velocity (frame-to-frame displacement of the quad
  /// vertices) is above the threshold. Distinct from [blurry] which captures
  /// static defocus. Hint copy asks the user to brace their hands.
  handShake,

  /// One or more quad vertices touch / cross the preview edge. Surfaced as
  /// a distinct state from [tooClose] so the hint can specifically prompt
  /// the user to pan rather than zoom out. Whether this blocks capture is
  /// controlled by the intent preset (`edgeClipBlocking`).
  edgeClipped,

  /// All failure checks pass but the quad isn't stable enough yet — we're
  /// waiting for the user to stop moving before promoting to `ready`.
  holdSteady,

  /// All checks pass for enough consecutive frames — safe to capture.
  ready,

  /// A capture has been triggered (either auto-capture delay elapsed or
  /// `controller.capture()` was called) and the native side is rectifying.
  /// UI-only — never produced by the state machine classifier.
  capturing,

  /// Capture finished; the rectified page is in hand. UI-only — terminal,
  /// the view returns to `noDocument` / `ready` on the next frame tick.
  captured,

  /// Framing is otherwise acceptable (distance, skew, glare, focus all pass)
  /// but the document is sitting off to one side of the preview. Produced by
  /// the C++ classifier (priority 10, between [handShake] and [holdSteady])
  /// and sent over the wire at index 12; gated on `maxCenterOffset > 0`. The
  /// overlay pairs it with a [SupyDocumentNudge] arrow — derived from the
  /// signed centroid offset — so the user can recenter before capture.
  /// Suppresses ready/countdown until the page is centered.
  offCenter,
}

/// Directional recentering hint paired with [SupyDocumentFrameState.offCenter].
///
/// Indicates which way the user should move the camera (or the page) to bring
/// the document back to the center of the preview. Derived in the UI from the
/// native-computed signed centroid offset (`centerOffsetX`/`centerOffsetY`).
enum SupyDocumentNudge {
  /// Document centroid sits right of center — pan left to recenter.
  left,

  /// Document centroid sits left of center — pan right to recenter.
  right,

  /// Document centroid sits below center — pan up to recenter.
  up,

  /// Document centroid sits above center — pan down to recenter.
  down,
}

/// Wire indices that mirror the C++ `FrameState` enum 1:1.
///
/// The C++ classifier uses raw `uint8_t` values for `FrameState`; the native
/// event-channel payload sends those same indices on the `state` key. Dart
/// receivers MUST map by this list rather than by `SupyDocumentFrameState.values`
/// so that adding a UI-only state (`capturing`, `captured`) on the Dart side
/// cannot accidentally shift the wire numbering. Order MUST match the C++
/// `FrameState` declaration in `native/document/document_guidance_classifier.h`.
const List<SupyDocumentFrameState> kSupyDocumentFrameStateWireIndex = [
  SupyDocumentFrameState.noDocument,
  SupyDocumentFrameState.tooDark,
  SupyDocumentFrameState.tooClose,
  SupyDocumentFrameState.tooFar,
  SupyDocumentFrameState.tooSkewed,
  SupyDocumentFrameState.blurry,
  SupyDocumentFrameState.holdSteady,
  SupyDocumentFrameState.ready,
  SupyDocumentFrameState.glare,
  SupyDocumentFrameState.occluded,
  SupyDocumentFrameState.handShake,
  SupyDocumentFrameState.edgeClipped,
  SupyDocumentFrameState.offCenter,
];

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
