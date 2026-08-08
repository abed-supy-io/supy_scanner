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
    // Live-preview lock gates below are tuned for *hand-held* capture: the
    // whole production invoice flow routes through this generic default (the
    // retailer calls startMultiPage with no intent), and the pre-tuning values
    // (blur≥80, stability≥0.75, velocity≤0.020, perCorner≥0.55) were strict
    // enough that a phone held by hand under indoor light never reached
    // `ready`. These gate the *preview* only — the still is re-shot at full
    // resolution on capture — so relaxing them trades nothing in output
    // quality for the ability to actually lock. See docs/QA.md doc-scan cases.
    this.minBlurScore = 55.0,
    this.readyStableFrames = 5,
    this.lostDocumentGraceFrames = 3,
    this.exitMargin = 0.10,
    this.minDwellFrames = 4,
    this.smoothingAlpha = 0.35,
    this.readyStabilityFloor = 0.60,
    this.interiorVarianceFloor = 3.0,
    this.holdSteadyFrames = 6,
    this.maxGlareRatio = 0.04,
    this.glareExitMargin = 0.50,
    this.maxCornerVelocity = 0.035,
    this.minPerCornerStability = 0.42,
    this.edgeClipBlocking = false,
    this.centerGuidanceEnabled = true,
    this.maxCenterOffset = 0.12,
    this.autoCapture = false,
    this.autoCaptureDelay = const Duration(milliseconds: 600),
    this.allowUnrectifiedFallback = true,
    this.warningColor,
    this.notReadyColor,
    this.readyColor,
    this.scrimColor,
    this.hints,
  });

  /// Preset that pairs with [SupyDocumentScanIntent.invoice]. Tightens the
  /// live-preview gates so a truncated footer / glare across a receipt can't
  /// reach `ready`:
  ///
  /// - [maxCoverageRatio] = 0.85 — leave headroom for slight tilt without
  ///   clipping the footer.
  /// - [edgeClipBlocking] = `true` — clipped vertices block capture instead
  ///   of being folded into `tooClose`.
  /// - [interiorVarianceFloor] = 8.0 — discourage capturing a phone screen
  ///   showing an invoice (low-texture surface).
  /// - [readyStableFrames] / [holdSteadyFrames] one frame longer than the
  ///   generic defaults — invoices are harder to hold steady.
  static const SupyDocumentGuidanceConfiguration invoice =
      SupyDocumentGuidanceConfiguration(
        maxCoverageRatio: 0.85,
        interiorVarianceFloor: 8.0,
        edgeClipBlocking: true,
        readyStableFrames: 6,
        holdSteadyFrames: 7,
      );

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

  /// Minimum `quadStability` required to leave `holdSteady` for `ready`.
  final double readyStabilityFloor;

  /// Minimum variance-of-Laplacian inside the quad before we trust it's a real
  /// document. Screens showing a single image fail this; printed paper passes.
  final double interiorVarianceFloor;

  /// Consecutive frames `quadStability >= readyStabilityFloor` required to
  /// promote `holdSteady` → `ready`.
  final int holdSteadyFrames;

  /// Maximum fraction of pixels inside the quad allowed to exceed the
  /// specular-highlight luma threshold before [SupyDocumentFrameState.glare]
  /// fires. Defaults to `0.04` (~4% of the page) — enough headroom for a
  /// printed sticker / coupon but not a lamp reflection across the whole bill.
  final double maxGlareRatio;

  /// Additional fractional headroom applied to `maxGlareRatio` while already
  /// in `glare` — glare is bursty (a phone shifts a degree and the highlight
  /// disappears), so we use a wider exit margin than the global [exitMargin].
  /// Defaults to `0.50` → must drop below `maxGlareRatio * 1.50` to exit.
  final double glareExitMargin;

  /// Maximum L2 corner displacement (normalized to preview diagonal at 30fps)
  /// allowed before [SupyDocumentFrameState.handShake] fires. Distinct from
  /// [minBlurScore] — captures *movement* blur a static-sharpness check can
  /// miss. Defaults to `0.020` (~2% of the diagonal per frame).
  final double maxCornerVelocity;

  /// Minimum per-corner stability (each corner's EMA distance from its
  /// smoothed position, in `[0..1]`) before [SupyDocumentFrameState.occluded]
  /// fires. A finger over one corner drags only that corner's score below the
  /// floor; the others stay stable — so this catches occlusion in a way that
  /// `quadStability` (an aggregate) misses. Defaults to `0.55`.
  final double minPerCornerStability;

  /// When `true`, a quad whose vertices touch the preview edge surfaces as
  /// [SupyDocumentFrameState.edgeClipped] (a blocking state) instead of
  /// being folded into [SupyDocumentFrameState.tooClose]. Defaults to `false`
  /// for drop-in safety; the invoice preset flips this to `true` so a
  /// truncated footer can't reach `ready`.
  final bool edgeClipBlocking;

  /// When `true`, once framing checks pass (distance / skew / glare / focus)
  /// the C++ classifier emits [SupyDocumentFrameState.offCenter] for a document
  /// sitting off to one side, before promoting to `ready`; the overlay pairs it
  /// with a directional arrow derived from the native centroid offset. This
  /// flag is encoded into [toConfigFloatArray] as a sentinel: when `false`,
  /// [maxCenterOffset] is sent as `-1.0`, which disables off-center detection
  /// natively (the classifier gates on `maxCenterOffset > 0`). Defaults to
  /// `true`.
  final bool centerGuidanceEnabled;

  /// Maximum allowed distance of the quad centroid from the preview center,
  /// as a fraction of the preview's half-extent on each axis, before
  /// [SupyDocumentFrameState.offCenter] fires. `0.12` ≈ the document may sit
  /// up to 12% off-center on either axis and still be considered centered.
  /// Sent to the C++ classifier (sentinel `-1.0` when [centerGuidanceEnabled]
  /// is `false`); paired with [exitMargin]-style hysteresis natively.
  final double maxCenterOffset;

  /// Whether the widget should auto-fire `captureAndRectify` after a brief
  /// countdown when `ready` first lands. Defaults to `false` — the scanner
  /// waits for a manual shutter tap unless a consumer opts into auto-snap.
  final bool autoCapture;

  /// Countdown duration before auto-capture fires.
  final Duration autoCaptureDelay;

  /// When `captureAndRectify` returns UNIMPLEMENTED (Android pre-Sprint 4),
  /// silently retry via `captureFullFrame` so the user always gets a picture.
  /// Set `false` for "rectified or nothing" flows.
  final bool allowUnrectifiedFallback;

  /// Color for failure-state corner brackets. Resolves to the palette
  /// `warning` when null.
  final Color? warningColor;

  /// Color used for the outline + hint card when not capture-ready. Resolves to
  /// the palette `negative` when null.
  final Color? notReadyColor;

  /// Color used for the outline + hint card when capture-ready. Resolves to the
  /// palette `positive` when null.
  final Color? readyColor;

  /// Background scrim color for the hint card. Resolves to the palette
  /// `modalOverlay` when null.
  final Color? scrimColor;

  /// Per-state hint copy. Resolves to the ambient-locale hints from the string
  /// bundle (`SupyScannerStrings.documentHints`) at the point of use when null;
  /// pass an explicit bundle to override individual strings.
  final SupyDocumentGuidanceHints? hints;

  /// Returns a copy with the given fields replaced. Nullable palette / hints
  /// fields cannot be reset to null through this API (passing null keeps the
  /// current value); that matches how the scanner UI reuses a base config and
  /// only ever *sets* overrides.
  SupyDocumentGuidanceConfiguration copyWith({
    double? minCoverageRatio,
    double? maxCoverageRatio,
    double? maxTiltDegrees,
    double? minMeanLuma,
    double? minBlurScore,
    int? readyStableFrames,
    int? lostDocumentGraceFrames,
    double? exitMargin,
    int? minDwellFrames,
    double? smoothingAlpha,
    double? readyStabilityFloor,
    double? interiorVarianceFloor,
    int? holdSteadyFrames,
    double? maxGlareRatio,
    double? glareExitMargin,
    double? maxCornerVelocity,
    double? minPerCornerStability,
    bool? edgeClipBlocking,
    bool? centerGuidanceEnabled,
    double? maxCenterOffset,
    bool? autoCapture,
    Duration? autoCaptureDelay,
    bool? allowUnrectifiedFallback,
    Color? warningColor,
    Color? notReadyColor,
    Color? readyColor,
    Color? scrimColor,
    SupyDocumentGuidanceHints? hints,
  }) => SupyDocumentGuidanceConfiguration(
    minCoverageRatio: minCoverageRatio ?? this.minCoverageRatio,
    maxCoverageRatio: maxCoverageRatio ?? this.maxCoverageRatio,
    maxTiltDegrees: maxTiltDegrees ?? this.maxTiltDegrees,
    minMeanLuma: minMeanLuma ?? this.minMeanLuma,
    minBlurScore: minBlurScore ?? this.minBlurScore,
    readyStableFrames: readyStableFrames ?? this.readyStableFrames,
    lostDocumentGraceFrames:
        lostDocumentGraceFrames ?? this.lostDocumentGraceFrames,
    exitMargin: exitMargin ?? this.exitMargin,
    minDwellFrames: minDwellFrames ?? this.minDwellFrames,
    smoothingAlpha: smoothingAlpha ?? this.smoothingAlpha,
    readyStabilityFloor: readyStabilityFloor ?? this.readyStabilityFloor,
    interiorVarianceFloor: interiorVarianceFloor ?? this.interiorVarianceFloor,
    holdSteadyFrames: holdSteadyFrames ?? this.holdSteadyFrames,
    maxGlareRatio: maxGlareRatio ?? this.maxGlareRatio,
    glareExitMargin: glareExitMargin ?? this.glareExitMargin,
    maxCornerVelocity: maxCornerVelocity ?? this.maxCornerVelocity,
    minPerCornerStability: minPerCornerStability ?? this.minPerCornerStability,
    edgeClipBlocking: edgeClipBlocking ?? this.edgeClipBlocking,
    centerGuidanceEnabled: centerGuidanceEnabled ?? this.centerGuidanceEnabled,
    maxCenterOffset: maxCenterOffset ?? this.maxCenterOffset,
    autoCapture: autoCapture ?? this.autoCapture,
    autoCaptureDelay: autoCaptureDelay ?? this.autoCaptureDelay,
    allowUnrectifiedFallback:
        allowUnrectifiedFallback ?? this.allowUnrectifiedFallback,
    warningColor: warningColor ?? this.warningColor,
    notReadyColor: notReadyColor ?? this.notReadyColor,
    readyColor: readyColor ?? this.readyColor,
    scrimColor: scrimColor ?? this.scrimColor,
    hints: hints ?? this.hints,
  );

  /// Packs the 19 native-classifier thresholds in the wire-coupled order the
  /// C++ bridge unpacks by index. MUST stay byte-for-byte aligned with
  /// `GuidanceConfig.toFloatArray()` in `SupyNativeCore.kt` and
  /// `GuidanceConfig.toNumberArray()` in `SupyNativeCore.swift` — the C++
  /// JNI / Obj-C++ shims unpack by position. UI-only fields (colors, hints,
  /// autoCapture) are intentionally excluded; they never reach native.
  ///
  /// The 19th entry encodes both [centerGuidanceEnabled] and [maxCenterOffset]:
  /// `maxCenterOffset` when enabled, sentinel `-1.0` when disabled. The C++
  /// classifier gates off-center detection on `maxCenterOffset > 0`, so a
  /// negative value cleanly turns the feature off without a 20th float.
  List<double> toConfigFloatArray() => <double>[
    minCoverageRatio,
    maxCoverageRatio,
    maxTiltDegrees,
    minMeanLuma,
    minBlurScore,
    readyStabilityFloor,
    interiorVarianceFloor,
    exitMargin,
    smoothingAlpha,
    readyStableFrames.toDouble(),
    holdSteadyFrames.toDouble(),
    lostDocumentGraceFrames.toDouble(),
    minDwellFrames.toDouble(),
    maxGlareRatio,
    glareExitMargin,
    maxCornerVelocity,
    minPerCornerStability,
    edgeClipBlocking ? 1.0 : 0.0,
    centerGuidanceEnabled ? maxCenterOffset : -1.0,
  ];

  /// Returns the hint text to show for [state], falling back to the English
  /// default bundle when [hints] is null. Locale-aware resolution happens at
  /// the point of use in the document view (via the string bundle); this
  /// convenience is English-only.
  String hintFor(SupyDocumentFrameState state) =>
      (hints ?? const SupyDocumentGuidanceHints()).textFor(state);

  /// Returns the outline color appropriate for [state].
  ///
  /// `ready`, `capturing`, and `captured` all paint with [readyColor] — the
  /// outline stays green through the whole capture lifecycle, the hint copy
  /// is what tells the user what's happening. Returns the raw (nullable) field;
  /// palette resolution happens at the point of use in the document view.
  Color? colorFor(SupyDocumentFrameState state) {
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
      case SupyDocumentFrameState.glare:
      case SupyDocumentFrameState.occluded:
      case SupyDocumentFrameState.handShake:
      case SupyDocumentFrameState.edgeClipped:
      case SupyDocumentFrameState.holdSteady:
      case SupyDocumentFrameState.offCenter:
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
          other.readyStabilityFloor == readyStabilityFloor &&
          other.interiorVarianceFloor == interiorVarianceFloor &&
          other.holdSteadyFrames == holdSteadyFrames &&
          other.maxGlareRatio == maxGlareRatio &&
          other.glareExitMargin == glareExitMargin &&
          other.maxCornerVelocity == maxCornerVelocity &&
          other.minPerCornerStability == minPerCornerStability &&
          other.edgeClipBlocking == edgeClipBlocking &&
          other.centerGuidanceEnabled == centerGuidanceEnabled &&
          other.maxCenterOffset == maxCenterOffset &&
          other.autoCapture == autoCapture &&
          other.autoCaptureDelay == autoCaptureDelay &&
          other.allowUnrectifiedFallback == allowUnrectifiedFallback &&
          other.warningColor == warningColor &&
          other.notReadyColor == notReadyColor &&
          other.readyColor == readyColor &&
          other.scrimColor == scrimColor &&
          other.hints == hints;

  @override
  int get hashCode => Object.hashAll([
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
    readyStabilityFloor,
    interiorVarianceFloor,
    holdSteadyFrames,
    maxGlareRatio,
    glareExitMargin,
    maxCornerVelocity,
    minPerCornerStability,
    edgeClipBlocking,
    centerGuidanceEnabled,
    maxCenterOffset,
    autoCapture,
    autoCaptureDelay,
    allowUnrectifiedFallback,
    warningColor,
    notReadyColor,
    readyColor,
    scrimColor,
    hints,
  ]);

  @override
  String toString() =>
      'SupyDocumentGuidanceConfiguration('
      'coverage: $minCoverageRatio..$maxCoverageRatio, '
      'tilt≤$maxTiltDegrees°, luma≥$minMeanLuma, '
      'blur≥$minBlurScore, stable=$readyStableFrames, '
      'holdSteady=$holdSteadyFrames@$readyStabilityFloor, '
      'centerGuidance=$centerGuidanceEnabled@$maxCenterOffset, '
      'autoCapture=$autoCapture)';
}

/// Per-state hint text bundle. Override individual strings for localization.
@immutable
class SupyDocumentGuidanceHints {
  /// Creates a hints bundle with English defaults.
  const SupyDocumentGuidanceHints({
    this.noDocument = 'Searching for document…',
    this.tooDark = 'Move to a brighter spot',
    this.tooClose = 'Move farther back',
    this.tooFar = 'Move closer',
    this.tooSkewed = 'Hold the camera flat',
    this.blurry = 'Hold steady',
    this.glare = 'Reduce glare — tilt the page',
    this.occluded = 'Move fingers off the page',
    this.handShake = 'Steady your hands',
    this.edgeClipped = 'Fit the whole page in frame',
    this.holdSteady = 'Hold steady…',
    this.ready = "Don't move",
    this.capturing = 'Capturing…',
    this.captured = 'Captured!',
    this.centerDocument = 'Center the document',
    this.moveLeft = 'Move left',
    this.moveRight = 'Move right',
    this.moveUp = 'Move up',
    this.moveDown = 'Move down',
  });

  /// Arabic preset. Companion to the default (English) constructor; supplied by
  /// [SupyScannerStrings.ar] so the document overlay speaks the ambient locale
  /// when the guidance config leaves `hints` null.
  const SupyDocumentGuidanceHints.ar()
    : noDocument = 'جارٍ البحث عن مستند…',
      tooDark = 'انتقل إلى مكان أكثر إضاءة',
      tooClose = 'ابتعد قليلاً',
      tooFar = 'اقترب أكثر',
      tooSkewed = 'أمسك الكاميرا بشكل مستوٍ',
      blurry = 'ثبّت يدك',
      glare = 'قلّل الوهج — أمِل الصفحة',
      occluded = 'أبعد أصابعك عن الصفحة',
      handShake = 'ثبّت يديك',
      edgeClipped = 'أدخِل الصفحة كاملة في الإطار',
      holdSteady = 'ثبّت…',
      ready = 'لا تحرّك',
      capturing = 'جارٍ الالتقاط…',
      captured = 'تم الالتقاط!',
      centerDocument = 'وسّط المستند',
      moveLeft = 'حرّك لليسار',
      moveRight = 'حرّك لليمين',
      moveUp = 'حرّك للأعلى',
      moveDown = 'حرّك للأسفل';

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

  /// Hint shown for [SupyDocumentFrameState.glare].
  final String glare;

  /// Hint shown for [SupyDocumentFrameState.occluded].
  final String occluded;

  /// Hint shown for [SupyDocumentFrameState.handShake].
  final String handShake;

  /// Hint shown for [SupyDocumentFrameState.edgeClipped].
  final String edgeClipped;

  /// Hint shown for [SupyDocumentFrameState.holdSteady].
  final String holdSteady;

  /// Hint shown for [SupyDocumentFrameState.ready].
  final String ready;

  /// Hint shown for [SupyDocumentFrameState.capturing].
  final String capturing;

  /// Hint shown for [SupyDocumentFrameState.captured].
  final String captured;

  /// Generic hint shown for [SupyDocumentFrameState.offCenter] when no single
  /// dominant direction applies. Directional variants ([moveLeft], [moveRight],
  /// [moveUp], [moveDown]) are preferred via [nudgeText] when the overlay has
  /// resolved a [SupyDocumentNudge].
  final String centerDocument;

  /// Directional hint for [SupyDocumentNudge.left].
  final String moveLeft;

  /// Directional hint for [SupyDocumentNudge.right].
  final String moveRight;

  /// Directional hint for [SupyDocumentNudge.up].
  final String moveUp;

  /// Directional hint for [SupyDocumentNudge.down].
  final String moveDown;

  /// Returns the directional recenter hint for [nudge], or [centerDocument]
  /// when [nudge] is `null`.
  String nudgeText(SupyDocumentNudge? nudge) {
    switch (nudge) {
      case SupyDocumentNudge.left:
        return moveLeft;
      case SupyDocumentNudge.right:
        return moveRight;
      case SupyDocumentNudge.up:
        return moveUp;
      case SupyDocumentNudge.down:
        return moveDown;
      case null:
        return centerDocument;
    }
  }

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
      case SupyDocumentFrameState.glare:
        return glare;
      case SupyDocumentFrameState.occluded:
        return occluded;
      case SupyDocumentFrameState.handShake:
        return handShake;
      case SupyDocumentFrameState.edgeClipped:
        return edgeClipped;
      case SupyDocumentFrameState.holdSteady:
        return holdSteady;
      case SupyDocumentFrameState.ready:
        return ready;
      case SupyDocumentFrameState.capturing:
        return capturing;
      case SupyDocumentFrameState.captured:
        return captured;
      case SupyDocumentFrameState.offCenter:
        return centerDocument;
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
          other.glare == glare &&
          other.occluded == occluded &&
          other.handShake == handShake &&
          other.edgeClipped == edgeClipped &&
          other.holdSteady == holdSteady &&
          other.ready == ready &&
          other.capturing == capturing &&
          other.captured == captured &&
          other.centerDocument == centerDocument &&
          other.moveLeft == moveLeft &&
          other.moveRight == moveRight &&
          other.moveUp == moveUp &&
          other.moveDown == moveDown;

  @override
  int get hashCode => Object.hashAll([
    noDocument,
    tooDark,
    tooClose,
    tooFar,
    tooSkewed,
    blurry,
    glare,
    occluded,
    handShake,
    edgeClipped,
    holdSteady,
    ready,
    capturing,
    captured,
    centerDocument,
    moveLeft,
    moveRight,
    moveUp,
    moveDown,
  ]);
}
