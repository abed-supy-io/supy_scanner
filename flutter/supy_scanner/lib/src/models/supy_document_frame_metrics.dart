import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

/// Raw per-frame measurements emitted by the native document scanner.
///
/// The native side is responsible only for *measurement* — quad detection,
/// luma, sharpness. The classification into a [SupyDocumentFrameState] lives
/// in pure Dart so thresholds can be tuned without a native rebuild.
@immutable
class SupyDocumentFrameMetrics {
  /// Creates a metrics snapshot for a single camera frame.
  const SupyDocumentFrameMetrics({
    this.quad = const [],
    this.coverageRatio = 0.0,
    this.tiltDegrees = 0.0,
    this.meanLuma = 0.0,
    this.blurScore = 0.0,
    this.clipsEdge = false,
    this.quadStability = 0.0,
    this.interiorVariance = 0.0,
    this.glareRatio = 0.0,
    this.cornerVelocity = 0.0,
    this.centerOffsetX = 0.0,
    this.centerOffsetY = 0.0,
    this.perCornerStability = const <double>[],
    this.liveQualityScore,
    this.sourceAspectRatio,
  });

  /// Parses a raw map from the native event channel.
  factory SupyDocumentFrameMetrics.fromMap(Map<Object?, Object?> map) {
    final rawQuad = (map['quad'] as List<Object?>?) ?? const [];
    final points = <Offset>[];
    for (final entry in rawQuad) {
      if (entry is Map) {
        final dx = (entry['x'] as num?)?.toDouble();
        final dy = (entry['y'] as num?)?.toDouble();
        if (dx != null && dy != null) points.add(Offset(dx, dy));
      }
    }
    final rawPerCorner =
        (map['perCornerStability'] as List<Object?>?) ?? const [];
    final perCorner = <double>[];
    for (final entry in rawPerCorner) {
      final value = (entry as num?)?.toDouble();
      if (value != null) perCorner.add(value);
    }
    return SupyDocumentFrameMetrics(
      quad: points.length == 4 ? List.unmodifiable(points) : const [],
      coverageRatio: (map['coverageRatio'] as num?)?.toDouble() ?? 0.0,
      tiltDegrees: (map['tiltDegrees'] as num?)?.toDouble() ?? 0.0,
      meanLuma: (map['meanLuma'] as num?)?.toDouble() ?? 0.0,
      blurScore: (map['blurScore'] as num?)?.toDouble() ?? 0.0,
      clipsEdge: (map['clipsEdge'] as bool?) ?? false,
      quadStability: (map['quadStability'] as num?)?.toDouble() ?? 0.0,
      interiorVariance: (map['interiorVariance'] as num?)?.toDouble() ?? 0.0,
      glareRatio: (map['glareRatio'] as num?)?.toDouble() ?? 0.0,
      cornerVelocity: (map['cornerVelocity'] as num?)?.toDouble() ?? 0.0,
      centerOffsetX: (map['centerOffsetX'] as num?)?.toDouble() ?? 0.0,
      centerOffsetY: (map['centerOffsetY'] as num?)?.toDouble() ?? 0.0,
      perCornerStability:
          perCorner.length == 4
              ? List<double>.unmodifiable(perCorner)
              : const <double>[],
      liveQualityScore: (map['liveQualityScore'] as num?)?.toDouble(),
      sourceAspectRatio: _positiveOrNull(
        (map['sourceAspectRatio'] as num?)?.toDouble(),
      ),
    );
  }

  /// Document outline in normalized preview coordinates (`0.0`–`1.0`).
  ///
  /// Either empty (no document detected this frame) or exactly four points
  /// ordered top-left, top-right, bottom-right, bottom-left.
  final List<Offset> quad;

  /// Detected quad area divided by full preview area. `0.0` when [quad] is
  /// empty.
  final double coverageRatio;

  /// Absolute tilt in degrees from a head-on rectangle. `0.0` is perfect.
  final double tiltDegrees;

  /// Average luma of the detected quad region (`0`–`255`).
  final double meanLuma;

  /// Variance-of-Laplacian over the quad — higher means sharper.
  final double blurScore;

  /// `true` when the quad touches the preview edge (likely too close /
  /// partially out of frame).
  final bool clipsEdge;

  /// Stability of the detected quad across the last few frames (0–1).
  /// 1 = no centroid/corner drift. 0.0 when [quad] is empty.
  final double quadStability;

  /// Variance-of-Laplacian *inside* the detected quad. Used to reject low-
  /// texture surfaces (laptop screens showing a single image). 0.0 when [quad]
  /// is empty.
  final double interiorVariance;

  /// Fraction of pixels inside the quad whose luma exceeds the specular-
  /// highlight threshold (~`245/255`). Range `[0..1]`. 0.0 when [quad] is
  /// empty. Drives [SupyDocumentFrameState.glare].
  final double glareRatio;

  /// L2 displacement of the quad vertices between this frame and the previous
  /// one, normalized by the preview diagonal at 30fps. Drives
  /// [SupyDocumentFrameState.handShake]. 0.0 when [quad] is empty or when no
  /// prior frame exists.
  final double cornerVelocity;

  /// Signed horizontal offset of the quad centroid from preview center, in
  /// half-extent fractions: `(centroidX - 0.5) * 2`, range ~`[-1..1]`.
  /// Positive = quad sits right of center. `0.0` when [quad] is empty. Computed
  /// natively from the detected quad and shipped on the wire so both the
  /// classifier and the UI arrow read one source of truth. Drives
  /// [SupyDocumentFrameState.offCenter].
  final double centerOffsetX;

  /// Signed vertical offset of the quad centroid from preview center, in
  /// half-extent fractions: `(centroidY - 0.5) * 2`, range ~`[-1..1]`.
  /// Positive = quad sits below center. `0.0` when [quad] is empty. Drives
  /// [SupyDocumentFrameState.offCenter].
  final double centerOffsetY;

  /// Per-corner stability score (EMA distance from the smoothed corner), in
  /// `[0..1]` — 1 = rock-solid, 0 = wildly moving. Index order matches [quad]
  /// (TL/TR/BR/BL). Empty when [quad] is empty. Drives
  /// [SupyDocumentFrameState.occluded].
  final List<double> perCornerStability;

  /// Aggregate quality score in `[0..1]` produced by the C++ classifier and
  /// surfaced opaquely on each frame. Computed **only** in C++ — Dart never
  /// recomputes it — so PlatformView consumers can preview the per-page
  /// quality bucket before the user fires capture. `null` when the native
  /// side hasn't populated it.
  final double? liveQualityScore;

  /// Aspect ratio (width / height) of the camera frame the [quad] was measured
  /// against, in the same orientation the preview renders. `null` when the
  /// native side didn't report it (older payloads, Android — which maps 1:1).
  ///
  /// The preview layer fills its container with `BoxFit.cover` semantics, so
  /// when this differs from the view's own aspect ratio the frame is cropped.
  /// Overlays use this to reproduce the crop and keep the drawn quad glued to
  /// the real document edges. See `SupyDocumentScannerView`'s guidance painter.
  final double? sourceAspectRatio;

  /// `true` when the frame contains a usable document quad.
  bool get hasDocument => quad.length == 4;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentFrameMetrics &&
          _quadEquals(other.quad, quad) &&
          other.coverageRatio == coverageRatio &&
          other.tiltDegrees == tiltDegrees &&
          other.meanLuma == meanLuma &&
          other.blurScore == blurScore &&
          other.clipsEdge == clipsEdge &&
          other.quadStability == quadStability &&
          other.interiorVariance == interiorVariance &&
          other.glareRatio == glareRatio &&
          other.cornerVelocity == cornerVelocity &&
          other.centerOffsetX == centerOffsetX &&
          other.centerOffsetY == centerOffsetY &&
          _doubleListEquals(other.perCornerStability, perCornerStability) &&
          other.liveQualityScore == liveQualityScore &&
          other.sourceAspectRatio == sourceAspectRatio;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(quad),
    coverageRatio,
    tiltDegrees,
    meanLuma,
    blurScore,
    clipsEdge,
    quadStability,
    interiorVariance,
    glareRatio,
    cornerVelocity,
    centerOffsetX,
    centerOffsetY,
    Object.hashAll(perCornerStability),
    liveQualityScore,
    sourceAspectRatio,
  );

  @override
  String toString() =>
      'SupyDocumentFrameMetrics(quad: ${quad.length} pts, '
      'coverage: ${coverageRatio.toStringAsFixed(2)}, '
      'tilt: ${tiltDegrees.toStringAsFixed(1)}°, '
      'luma: ${meanLuma.toStringAsFixed(0)}, '
      'blur: ${blurScore.toStringAsFixed(0)}, '
      'clipsEdge: $clipsEdge, '
      'stability: ${quadStability.toStringAsFixed(2)}, '
      'interior: ${interiorVariance.toStringAsFixed(0)}, '
      'glare: ${glareRatio.toStringAsFixed(3)}, '
      'cornerVel: ${cornerVelocity.toStringAsFixed(4)}, '
      'centerOff: (${centerOffsetX.toStringAsFixed(2)}, '
      '${centerOffsetY.toStringAsFixed(2)}), '
      'perCorner: ${perCornerStability.length}, '
      'liveQ: ${liveQualityScore?.toStringAsFixed(2) ?? '-'}, '
      'srcAspect: ${sourceAspectRatio?.toStringAsFixed(3) ?? '-'})';
}

/// Returns [value] when it is a usable positive, finite ratio; `null`
/// otherwise. A `0` or negative aspect (the native "unknown" sentinel) means
/// "no crop correction available" — collapse it to `null` so overlays fall
/// back to identity mapping.
double? _positiveOrNull(double? value) {
  if (value == null || !value.isFinite || value <= 0.0) return null;
  return value;
}

bool _quadEquals(List<Offset> a, List<Offset> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _doubleListEquals(List<double> a, List<double> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
