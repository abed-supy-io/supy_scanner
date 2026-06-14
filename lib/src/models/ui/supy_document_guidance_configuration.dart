import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import '../supy_document_frame_state.dart';

/// Per-state hint copy + thresholds + palette for the document scanner
/// guidance overlay.
///
/// All thresholds are tunable on a per-screen basis so consumers can adapt
/// to lighting / camera quality without a native rebuild.
@immutable
class SupyDocumentGuidanceConfiguration {
  /// Creates a guidance configuration with sensible defaults.
  const SupyDocumentGuidanceConfiguration({
    this.minCoverageRatio = 0.30,
    this.maxCoverageRatio = 0.90,
    this.maxTiltDegrees = 20.0,
    this.minMeanLuma = 60.0,
    this.minBlurScore = 80.0,
    this.readyStableFrames = 5,
    this.lostDocumentGraceFrames = 3,
    this.exitMargin = 0.10,
    this.minDwellFrames = 4,
    this.smoothingAlpha = 0.35,
    this.notReadyColor = const Color(0xFFE5484D),
    this.readyColor = const Color(0xFF30A46C),
    this.scrimColor = const Color(0x99000000),
    this.hints = const SupyDocumentGuidanceHints(),
  });

  /// Minimum quad area / preview area before a document is "close enough".
  final double minCoverageRatio;

  /// Maximum coverage before we consider the document too close / clipped.
  final double maxCoverageRatio;

  /// Maximum absolute tilt from a head-on rectangle, in degrees.
  final double maxTiltDegrees;

  /// Minimum mean luma (0–255) before the scene is considered too dark.
  final double minMeanLuma;

  /// Minimum variance-of-Laplacian before the frame is considered blurry.
  final double minBlurScore;

  /// Consecutive good frames required to transition into `ready`.
  final int readyStableFrames;

  /// How many frames of no-detection are tolerated before falling back to
  /// `noDocument`. Smooths over single-frame detector misses.
  final int lostDocumentGraceFrames;

  /// Fractional relaxation applied to thresholds while *already failing* on
  /// them. Prevents bouncing in and out of the same hint when the metric
  /// hovers right at the threshold (e.g. coverage = `minCoverageRatio ± 1%`).
  ///
  /// Example: with `minCoverageRatio = 0.30` and `exitMargin = 0.10`, the
  /// `tooFar` state holds until coverage rises past `0.33`.
  final double exitMargin;

  /// Minimum frames a state must persist before a lower-or-equal-priority
  /// state may replace it. Higher-priority issues (e.g. `tooDark`) always
  /// preempt regardless of dwell.
  final int minDwellFrames;

  /// EMA weight applied to per-frame metrics by the smoother layer. Larger =
  /// snappier reaction; smaller = smoother overlay but more lag. The default
  /// (~0.35) reaches ~90% of a step input in ~6 frames at 30fps.
  final double smoothingAlpha;

  /// Color used for the outline + hint card when not capture-ready.
  final Color notReadyColor;

  /// Color used for the outline + hint card when capture-ready.
  final Color readyColor;

  /// Background scrim color for the hint card.
  final Color scrimColor;

  /// Per-state hint copy.
  final SupyDocumentGuidanceHints hints;

  /// Returns the hint text to show for [state].
  String hintFor(SupyDocumentFrameState state) => hints.textFor(state);

  /// Returns the outline color appropriate for [state].
  ///
  /// `ready`, `capturing`, and `captured` all paint with [readyColor] — the
  /// outline stays green through the whole capture lifecycle, the hint copy
  /// is what tells the user what's happening.
  Color colorFor(SupyDocumentFrameState state) {
    switch (state) {
      case SupyDocumentFrameState.ready:
      case SupyDocumentFrameState.capturing:
      case SupyDocumentFrameState.captured:
        return readyColor;
      case SupyDocumentFrameState.noDocument:
      case SupyDocumentFrameState.tooDark:
      case SupyDocumentFrameState.tooClose:
      case SupyDocumentFrameState.tooFar:
      case SupyDocumentFrameState.tooSkewed:
      case SupyDocumentFrameState.blurry:
        return notReadyColor;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentGuidanceConfiguration &&
          other.minCoverageRatio == minCoverageRatio &&
          other.maxCoverageRatio == maxCoverageRatio &&
          other.maxTiltDegrees == maxTiltDegrees &&
          other.minMeanLuma == minMeanLuma &&
          other.minBlurScore == minBlurScore &&
          other.readyStableFrames == readyStableFrames &&
          other.lostDocumentGraceFrames == lostDocumentGraceFrames &&
          other.exitMargin == exitMargin &&
          other.minDwellFrames == minDwellFrames &&
          other.smoothingAlpha == smoothingAlpha &&
          other.notReadyColor == notReadyColor &&
          other.readyColor == readyColor &&
          other.scrimColor == scrimColor &&
          other.hints == hints;

  @override
  int get hashCode => Object.hash(
        minCoverageRatio,
        maxCoverageRatio,
        maxTiltDegrees,
        minMeanLuma,
        minBlurScore,
        readyStableFrames,
        lostDocumentGraceFrames,
        exitMargin,
        minDwellFrames,
        smoothingAlpha,
        notReadyColor,
        readyColor,
        scrimColor,
        hints,
      );

  @override
  String toString() => 'SupyDocumentGuidanceConfiguration('
      'coverage: $minCoverageRatio..$maxCoverageRatio, '
      'tilt≤$maxTiltDegrees°, luma≥$minMeanLuma, '
      'blur≥$minBlurScore, stable=$readyStableFrames)';
}

/// Per-state hint text bundle. Override individual strings for localization.
@immutable
class SupyDocumentGuidanceHints {
  /// Creates a hints bundle with English defaults.
  const SupyDocumentGuidanceHints({
    this.noDocument = 'Point the camera at a document',
    this.tooDark = 'More light needed',
    this.tooClose = 'Move back',
    this.tooFar = 'Move closer',
    this.tooSkewed = 'Hold the camera straight',
    this.blurry = 'Hold steady',
    this.ready = 'Hold still…',
    this.capturing = 'Capturing…',
    this.captured = 'Captured!',
  });

  /// Hint shown for [SupyDocumentFrameState.noDocument].
  final String noDocument;

  /// Hint shown for [SupyDocumentFrameState.tooDark].
  final String tooDark;

  /// Hint shown for [SupyDocumentFrameState.tooClose].
  final String tooClose;

  /// Hint shown for [SupyDocumentFrameState.tooFar].
  final String tooFar;

  /// Hint shown for [SupyDocumentFrameState.tooSkewed].
  final String tooSkewed;

  /// Hint shown for [SupyDocumentFrameState.blurry].
  final String blurry;

  /// Hint shown for [SupyDocumentFrameState.ready].
  final String ready;

  /// Hint shown for [SupyDocumentFrameState.capturing].
  final String capturing;

  /// Hint shown for [SupyDocumentFrameState.captured].
  final String captured;

  /// Returns the hint text for [state].
  String textFor(SupyDocumentFrameState state) {
    switch (state) {
      case SupyDocumentFrameState.noDocument:
        return noDocument;
      case SupyDocumentFrameState.tooDark:
        return tooDark;
      case SupyDocumentFrameState.tooClose:
        return tooClose;
      case SupyDocumentFrameState.tooFar:
        return tooFar;
      case SupyDocumentFrameState.tooSkewed:
        return tooSkewed;
      case SupyDocumentFrameState.blurry:
        return blurry;
      case SupyDocumentFrameState.ready:
        return ready;
      case SupyDocumentFrameState.capturing:
        return capturing;
      case SupyDocumentFrameState.captured:
        return captured;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentGuidanceHints &&
          other.noDocument == noDocument &&
          other.tooDark == tooDark &&
          other.tooClose == tooClose &&
          other.tooFar == tooFar &&
          other.tooSkewed == tooSkewed &&
          other.blurry == blurry &&
          other.ready == ready &&
          other.capturing == capturing &&
          other.captured == captured;

  @override
  int get hashCode => Object.hash(
        noDocument,
        tooDark,
        tooClose,
        tooFar,
        tooSkewed,
        blurry,
        ready,
        capturing,
        captured,
      );
}
