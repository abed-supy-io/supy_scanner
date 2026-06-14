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
    return SupyDocumentFrameMetrics(
      quad: points.length == 4 ? List.unmodifiable(points) : const [],
      coverageRatio: (map['coverageRatio'] as num?)?.toDouble() ?? 0.0,
      tiltDegrees: (map['tiltDegrees'] as num?)?.toDouble() ?? 0.0,
      meanLuma: (map['meanLuma'] as num?)?.toDouble() ?? 0.0,
      blurScore: (map['blurScore'] as num?)?.toDouble() ?? 0.0,
      clipsEdge: (map['clipsEdge'] as bool?) ?? false,
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

  /// `true` when the frame contains a usable document quad.
  bool get hasDocument => quad.length == 4;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentFrameMetrics &&
          _listEquals(other.quad, quad) &&
          other.coverageRatio == coverageRatio &&
          other.tiltDegrees == tiltDegrees &&
          other.meanLuma == meanLuma &&
          other.blurScore == blurScore &&
          other.clipsEdge == clipsEdge;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(quad),
        coverageRatio,
        tiltDegrees,
        meanLuma,
        blurScore,
        clipsEdge,
      );

  @override
  String toString() =>
      'SupyDocumentFrameMetrics(quad: ${quad.length} pts, '
      'coverage: ${coverageRatio.toStringAsFixed(2)}, '
      'tilt: ${tiltDegrees.toStringAsFixed(1)}°, '
      'luma: ${meanLuma.toStringAsFixed(0)}, '
      'blur: ${blurScore.toStringAsFixed(0)}, '
      'clipsEdge: $clipsEdge)';
}

bool _listEquals(List<Offset> a, List<Offset> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
