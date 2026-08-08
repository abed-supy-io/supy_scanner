import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channel/supy_document_event_channel.dart';
import '../document/supy_auto_capture_hold_gate.dart';
import '../document/supy_document_metrics_smoother.dart';
import '../document/supy_document_state_machine.dart';
import '../models/supy_document_frame_metrics.dart';
import '../models/supy_document_frame_state.dart';
import '../models/supy_scan_error.dart';
import '../models/ui/supy_document_guidance_configuration.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import 'supy_document_scanner_controller.dart';

/// View-type identifier registered by the native PlatformView factories.
const String _kDocumentViewTypeId = 'io.supy.scanner/v1/document_view';

/// Countdown ring that sweeps from 12 o'clock clockwise over [duration].
///
/// Calls [onComplete] once when the animation finishes.
class SupyDocumentCountdownRing extends StatefulWidget {
  /// Creates a countdown ring.
  const SupyDocumentCountdownRing({
    required this.duration,
    required this.color,
    required this.onComplete,
    super.key,
  });

  /// Total duration of the countdown sweep.
  final Duration duration;

  /// Arc and stroke color.
  final Color color;

  /// Called exactly once when the ring sweep finishes.
  final VoidCallback onComplete;

  @override
  State<SupyDocumentCountdownRing> createState() =>
      _SupyDocumentCountdownRingState();
}

class _SupyDocumentCountdownRingState extends State<SupyDocumentCountdownRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    unawaited(
      _controller.forward().whenComplete(() {
        if (mounted) widget.onComplete();
      }),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _RingPainter(value: _controller.value, color: widget.color),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    // Sweep arc: -π/2 (12 o'clock) clockwise by 2π·value
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}

// ---------------------------------------------------------------------------
// Embedded native document scanner view
// ---------------------------------------------------------------------------

/// Embedded native document scanner with live edge-guidance overlay.
///
/// The widget mounts a PlatformView (UiKitView on iOS, AndroidView on Android),
/// subscribes to its per-view EventChannel, feeds each `frame_metrics` payload
/// into a [SupyDocumentStateMachine], and paints a scrim + quad outline +
/// hint text driven by the resulting [SupyDocumentGuidanceFrame].
///
/// Corner reticles pulse while no document is detected. When a quad is
/// locked in, corner brackets replace the full outline and their color ramps
/// from warning (red) through amber to primary (green) as the state machine
/// progresses. When [SupyDocumentGuidanceConfiguration.autoCapture] is true
/// and the state reaches `ready`, a [SupyDocumentCountdownRing] sweeps for
/// [SupyDocumentGuidanceConfiguration.autoCaptureDelay] before firing
/// `captureAndRectify` (with an `allowUnrectifiedFallback` retry path).
/// Capture completion triggers an 80 ms full-screen white flash and a haptic.
class SupyDocumentScannerView extends StatefulWidget {
  /// Creates an embedded document scanner view.
  const SupyDocumentScannerView({
    super.key,
    this.guidance = const SupyDocumentGuidanceConfiguration(),
    this.controller,
    this.onGuidance,
    this.onReady,
    this.onCapture,
    this.onError,
    this.onPreviewStarted,
    this.showOverlay = true,
    this.header,
    this.footer,
    this.palette = const SupyScannerPalette.supyDark(),
    this.strings = const SupyScannerStrings.en(),
  });

  /// Thresholds + palette + hint copy.
  final SupyDocumentGuidanceConfiguration guidance;

  /// String bundle used to resolve guidance copy the [guidance] leaves null
  /// and the unsupported-platform placeholder text.
  final SupyScannerStrings strings;

  /// Palette used to resolve the capture flash, hint-card chrome, and
  /// unsupported-platform placeholder colors.
  final SupyScannerPalette palette;

  /// Optional controller for `pause`/`resume`/`setTorch`/`captureAndRectify`.
  final SupyDocumentScannerController? controller;

  /// Fires on every frame after the state machine ticks.
  final ValueChanged<SupyDocumentGuidanceFrame>? onGuidance;

  /// Fires the first time the state machine reports `ready`.
  final ValueChanged<SupyDocumentGuidanceFrame>? onReady;

  /// Fires after an auto-capture (countdown-completed) still is rectified,
  /// surfacing the [SupyDocumentCapture] to the host so it can push the page
  /// onto a multi-page review stack. When set, the host owns the post-capture
  /// lifecycle and should call `controller.clearCapturePhase()` once it has
  /// acknowledged the page; when `null`, the view re-arms itself.
  final ValueChanged<SupyDocumentCapture>? onCapture;

  /// Fires when the native side reports an error.
  final ValueChanged<SupyScanError>? onError;

  /// Fires once the first camera frame has rendered.
  final ValueChanged<bool>? onPreviewStarted;

  /// Whether to paint the guidance overlay. Default `true`.
  final bool showOverlay;

  /// Optional widget placed above the camera.
  final Widget? header;

  /// Optional widget placed below the camera.
  final Widget? footer;

  @override
  State<SupyDocumentScannerView> createState() =>
      _SupyDocumentScannerViewState();
}

class _SupyDocumentScannerViewState extends State<SupyDocumentScannerView>
    with TickerProviderStateMixin {
  late final SupyDocumentStateMachine _stateMachine = SupyDocumentStateMachine(
    configuration: widget.guidance,
  );

  // Render-smoother for the native-classified path (iOS C++ GuidanceClassifier).
  // Native ships a resolved `state` but a raw, per-frame quad + scalars, so the
  // painter would jitter without this. The Android path smooths inside the FSM
  // instead; both use the same alpha so the overlay feels identical. Kept in
  // sync with `guidance.smoothingAlpha` in [didUpdateWidget].
  late SupyDocumentMetricsSmoother _renderSmoother =
      SupyDocumentMetricsSmoother(alpha: widget.guidance.smoothingAlpha);

  StreamSubscription<SupyDocumentEvent>? _eventSub;
  SupyDocumentGuidanceFrame _frame = const SupyDocumentGuidanceFrame(
    state: SupyDocumentFrameState.noDocument,
    metrics: SupyDocumentFrameMetrics(),
    framesAtState: 0,
  );
  // Debounces the `ready` acquisition that drives the lock cue, `onReady`, and
  // the auto-capture countdown. A one- or two-frame flicker out of `ready` (a
  // momentary hand-shake/hold-steady demotion — which the FSM applies
  // immediately, with no dwell protection) rides through instead of tearing
  // down and restarting the countdown sweep. Both platforms feed the same
  // per-frame `ready` boolean, so the hold behaves identically on iOS/Android.
  final SupyAutoCaptureHoldGate _autoCaptureGate = SupyAutoCaptureHoldGate();

  // Guidance colors resolve to palette tokens when the config leaves them null.
  Color get _readyColor =>
      widget.guidance.readyColor ?? widget.palette.positive;
  Color get _warningColor =>
      widget.guidance.warningColor ?? widget.palette.warning;
  Color get _notReadyColor =>
      widget.guidance.notReadyColor ?? widget.palette.negative;
  Color get _scrimColor =>
      widget.guidance.scrimColor ?? widget.palette.modalOverlay;

  // Current recenter direction while `_frame.state == offCenter`, else null.
  // Derived from the native centroid offset by [_resolveNudge].
  SupyDocumentNudge? _nudge;

  // Reticle pulse animation (1.2 s, repeating)
  late final AnimationController _pulseController;

  // One-shot success flash on the lock (`ready`) transition: the detected quad
  // outline flashes at `readyColor` and decays to nothing. Driven off the
  // Dart-observed `ready` transition so timing is identical on iOS and Android.
  late final AnimationController _lockFlashController;
  static const Duration _lockFlashDuration = Duration(milliseconds: 280);

  // Countdown ring state
  bool _countdownActive = false;
  Key _countdownKey = UniqueKey();

  // Flash overlay
  double _flashOpacity = 0.0;
  bool _flashing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    unawaited(_pulseController.repeat(reverse: true));
    _lockFlashController = AnimationController(
      vsync: this,
      duration: _lockFlashDuration,
    );
    widget.controller?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SupyDocumentScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guidance != widget.guidance) {
      _stateMachine.configuration = widget.guidance;
      if (oldWidget.guidance.smoothingAlpha != widget.guidance.smoothingAlpha) {
        _renderSmoother = SupyDocumentMetricsSmoother(
          alpha: widget.guidance.smoothingAlpha,
        );
      }
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _lockFlashController.dispose();
    unawaited(_eventSub?.cancel());
    widget.controller?.removeListener(_onControllerChanged);
    widget.controller?.detach();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// FSM-emitted state, with the controller's capture phase overlaid on top.
  SupyDocumentFrameState get _effectiveState =>
      widget.controller?.capturePhaseAsFrameState ?? _frame.state;

  void _onPlatformViewCreated(int id) {
    widget.controller?.attach(MethodChannel(supyDocumentMethodChannelName(id)));
    _eventSub = supyDocumentEventStream(id).listen(_handleEvent);
  }

  void _handleEvent(SupyDocumentEvent event) {
    switch (event) {
      case SupyDocumentFrameMetricsEvent(:final metrics, :final nativeState):
        // When the platform classifies on-device (iOS C++ GuidanceClassifier)
        // it ships the resolved `state`; trust it and skip the Dart FSM. The
        // native payload is stateless per frame, so we count framesAtState
        // here by comparing against the last emitted frame. When `nativeState`
        // is null (Android embedded view) the Dart FSM classifies as before.
        final SupyDocumentGuidanceFrame next;
        if (nativeState != null) {
          final framesAtState =
              nativeState == _frame.state ? _frame.framesAtState + 1 : 1;
          // Native emits a resolved `state` but a raw, per-frame quad + scalars.
          // Smooth them for rendering so the overlay is stable, matching the
          // Android path (which smooths inside the FSM); trust the native state.
          next = SupyDocumentGuidanceFrame(
            state: nativeState,
            metrics: _renderSmoother.add(metrics),
            framesAtState: framesAtState,
          );
        } else {
          next = _stateMachine.tick(metrics);
        }
        // `offCenter` is classified natively (C++ on iOS, the mirrored Dart FSM
        // on Android) — derive only the directional arrow here from the
        // native-computed centroid offset; never rewrite the state in Dart.
        _resolveNudge(next);
        if (kDebugMode) {
          // Lock-gate telemetry: when a document "never locks", this shows
          // which gate is holding it back. Fires on both platforms (Android
          // FSM + iOS native-classified) and compiles out of release builds.
          final m = next.metrics;
          debugPrint(
            '[supy_scanner/doc] state=${next.state.name} '
            'frames=${next.framesAtState} hasDoc=${m.hasDocument} '
            'cover=${m.coverageRatio.toStringAsFixed(2)} '
            'tilt=${m.tiltDegrees.toStringAsFixed(1)} '
            'luma=${m.meanLuma.toStringAsFixed(0)} '
            'blur=${m.blurScore.toStringAsFixed(0)} '
            'stab=${m.quadStability.toStringAsFixed(2)} '
            'iVar=${m.interiorVariance.toStringAsFixed(1)} '
            'glare=${m.glareRatio.toStringAsFixed(2)} '
            'vel=${m.cornerVelocity.toStringAsFixed(3)}',
          );
        }
        setState(() => _frame = next);
        widget.onGuidance?.call(next);
        final isReady = next.state == SupyDocumentFrameState.ready;
        switch (_autoCaptureGate.update(isReady: isReady)) {
          case SupyAutoCaptureHoldEdge.acquired:
            _triggerLockCue();
            widget.onReady?.call(next);
            _maybeStartCountdown();
          case SupyAutoCaptureHoldEdge.lost:
            _cancelCountdown();
          case SupyAutoCaptureHoldEdge.none:
            break;
        }
      case SupyDocumentPreviewStartedEvent(:final flashAvailable):
        widget.onPreviewStarted?.call(flashAvailable);
      case SupyDocumentErrorEvent(:final error):
        widget.onError?.call(error);
    }
  }

  /// Derives the directional recenter arrow for the coaching pill.
  ///
  /// The off-center *decision* is made natively (the C++ classifier on iOS,
  /// the mirrored Dart FSM on Android) and arrives as
  /// [SupyDocumentFrameState.offCenter]; this only picks which arrow to draw,
  /// from the signed native-computed centroid offset in [frame]'s metrics.
  /// Clears [_nudge] for any non-`offCenter` state.
  void _resolveNudge(SupyDocumentGuidanceFrame frame) {
    if (frame.state != SupyDocumentFrameState.offCenter) {
      _nudge = null;
      return;
    }
    final dx = frame.metrics.centerOffsetX;
    final dy = frame.metrics.centerOffsetY;
    // Nudge along the dominant axis: a centroid right/below center means the
    // user should pan the camera left/up to recenter.
    if (dx.abs() >= dy.abs()) {
      _nudge = dx > 0 ? SupyDocumentNudge.left : SupyDocumentNudge.right;
    } else {
      _nudge = dy > 0 ? SupyDocumentNudge.up : SupyDocumentNudge.down;
    }
  }

  void _maybeStartCountdown() {
    if (!widget.guidance.autoCapture) return;
    if (_countdownActive) return;
    if (widget.controller == null) return;
    setState(() {
      _countdownActive = true;
      _countdownKey = UniqueKey();
    });
    // Transition overlay to capturing phase immediately so it reads
    // SupyDocumentFrameState.capturing while the ring sweeps.
    widget.controller!.setCapturePhase(SupyDocumentCapturePhase.capturing);
  }

  void _cancelCountdown() {
    if (!_countdownActive) return;
    setState(() => _countdownActive = false);
    widget.controller?.setCapturePhase(SupyDocumentCapturePhase.idle);
  }

  Future<void> _onCountdownComplete() async {
    if (!mounted) return;
    setState(() => _countdownActive = false);
    final ctrl = widget.controller;
    if (ctrl == null) return;
    SupyDocumentCapture capture;
    try {
      try {
        capture = await ctrl.captureAndRectify();
      } on StateError catch (e) {
        if (e.message.startsWith('captureUnsupported') &&
            widget.guidance.allowUnrectifiedFallback) {
          capture = await ctrl.captureFullFrame();
        } else {
          rethrow;
        }
      }
    } on Object catch (e) {
      // Route capture failures through the same channel as
      // SupyDocumentErrorEvent (see _handleEvent) and reset the phase so the
      // UI doesn't stay stuck in `capturing`.
      ctrl.setCapturePhase(SupyDocumentCapturePhase.idle);
      widget.onError?.call(
        SupyScanError(
          code: SupyScanErrorCode.unknown,
          message: e.toString(),
          details: e,
        ),
      );
      return;
    }
    if (!mounted) return;
    ctrl.setCapturePhase(SupyDocumentCapturePhase.captured);
    if (widget.onCapture != null) {
      // Host now owns the lifecycle: it pushes the page and clears the phase.
      widget.onCapture!(capture);
    } else {
      // No host to acknowledge the capture — re-arm ourselves so a standalone
      // view keeps working exactly as before this callback existed.
      ctrl.clearCapturePhase();
    }
    _triggerFlash();
  }

  /// Success cue at the lock (`ready`) transition: a crisp haptic tick plus a
  /// one-shot flash of the detected quad outline. Fires on the Dart-observed
  /// transition into `ready`, which both platforms reach identically, so the
  /// haptic and the flash have the same timing on iOS and Android.
  void _triggerLockCue() {
    unawaited(HapticFeedback.selectionClick());
    // Snap to full intensity, then decay to 0 over [_lockFlashDuration].
    unawaited(_lockFlashController.reverse(from: 1.0));
  }

  void _triggerFlash() {
    if (_flashing) return;
    _flashing = true;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _flashOpacity = 1.0);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        setState(() => _flashOpacity = 0.0);
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 80), () {
            if (!mounted) return;
            _flashing = false;
          }),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPreview(),
        if (widget.showOverlay) _buildOverlay(),
        if (widget.showOverlay) _buildHintCard(),
        if (_countdownActive)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: SupyDocumentCountdownRing(
                    key: _countdownKey,
                    duration: widget.guidance.autoCaptureDelay,
                    color: _readyColor,
                    onComplete: _onCountdownComplete,
                  ),
                ),
              ),
            ),
          ),
        // Flash overlay
        if (_flashOpacity > 0.0 || _flashing)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _flashOpacity,
                duration: const Duration(milliseconds: 80),
                child: ColoredBox(color: widget.palette.onSurface),
              ),
            ),
          ),
        if (widget.header != null)
          Positioned(top: 0, left: 0, right: 0, child: widget.header!),
        if (widget.footer != null)
          Positioned(bottom: 0, left: 0, right: 0, child: widget.footer!),
      ],
    );
  }

  Widget _buildOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _lockFlashController]),
          builder: (context, _) {
            // Bracket color ramp by state
            final state = _effectiveState;
            final bracketColor = _bracketColorForState(state);

            return CustomPaint(
              painter: _DocumentGuidancePainter(
                frame: _frame,
                scrimColor: _scrimColor,
                bracketColor: bracketColor,
                pulseValue: _pulseController.value,
                lockFlash: _lockFlashController.value,
                warningColor: _warningColor,
                readyColor: _readyColor,
              ),
            );
          },
        ),
      ),
    );
  }

  Color _bracketColorForState(SupyDocumentFrameState state) {
    switch (state) {
      case SupyDocumentFrameState.ready:
      case SupyDocumentFrameState.capturing:
      case SupyDocumentFrameState.captured:
        return _readyColor;
      case SupyDocumentFrameState.holdSteady:
      case SupyDocumentFrameState.offCenter:
        // Amber midpoint — framing has cleared, just settling / recentering.
        return Color.lerp(_warningColor, _readyColor, 0.5)!;
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
        return _warningColor;
    }
  }

  // Mirrors [SupyDocumentGuidanceConfiguration.colorFor] but resolves the
  // nullable config field against the palette (ready → positive, else negative).
  Color _accentColorForState(SupyDocumentFrameState state) {
    const readyStates = {
      SupyDocumentFrameState.ready,
      SupyDocumentFrameState.capturing,
      SupyDocumentFrameState.captured,
    };
    return readyStates.contains(state) ? _readyColor : _notReadyColor;
  }

  Widget _buildHintCard() {
    final state = _effectiveState;
    // Config hints win when set; otherwise fall back to the ambient-locale
    // bundle so guidance copy is localized without forcing callers to supply
    // an explicit hint set.
    final hints = widget.guidance.hints ?? widget.strings.documentHints;
    // For `offCenter` prefer the resolved directional copy over the generic
    // "Center the document" so the user knows which way to move.
    final text =
        state == SupyDocumentFrameState.offCenter
            ? hints.nudgeText(_nudge)
            : hints.textFor(state);
    return Positioned(
      left: 16,
      right: 16,
      bottom: 32,
      child: IgnorePointer(
        child: _HintCard(
          text: text,
          icon: _iconForState(state, _nudge),
          accentColor: _accentColorForState(state),
          backgroundColor: widget.palette.surfaceLow,
          shadowColor: widget.palette.outline,
          textColor: widget.palette.onSurface,
        ),
      ),
    );
  }

  /// Per-state glyph for the coaching pill. For [SupyDocumentFrameState.offCenter]
  /// the icon is the directional arrow matching [nudge].
  static IconData _iconForState(
    SupyDocumentFrameState state,
    SupyDocumentNudge? nudge,
  ) {
    switch (state) {
      case SupyDocumentFrameState.noDocument:
        return Icons.document_scanner_outlined;
      case SupyDocumentFrameState.tooDark:
        return Icons.lightbulb_outline;
      case SupyDocumentFrameState.tooClose:
        return Icons.zoom_out_map;
      case SupyDocumentFrameState.tooFar:
        return Icons.zoom_in_map;
      case SupyDocumentFrameState.tooSkewed:
        return Icons.crop_rotate;
      case SupyDocumentFrameState.blurry:
        return Icons.center_focus_weak;
      case SupyDocumentFrameState.glare:
        return Icons.flare;
      case SupyDocumentFrameState.occluded:
        return Icons.pan_tool_outlined;
      case SupyDocumentFrameState.handShake:
        return Icons.vibration;
      case SupyDocumentFrameState.edgeClipped:
        return Icons.crop_free;
      case SupyDocumentFrameState.holdSteady:
        return Icons.hourglass_top;
      case SupyDocumentFrameState.ready:
        return Icons.check_circle_outline;
      case SupyDocumentFrameState.capturing:
        return Icons.camera_alt_outlined;
      case SupyDocumentFrameState.captured:
        return Icons.check_circle;
      case SupyDocumentFrameState.offCenter:
        switch (nudge) {
          case SupyDocumentNudge.left:
            return Icons.arrow_back;
          case SupyDocumentNudge.right:
            return Icons.arrow_forward;
          case SupyDocumentNudge.up:
            return Icons.arrow_upward;
          case SupyDocumentNudge.down:
            return Icons.arrow_downward;
          case null:
            return Icons.center_focus_strong;
        }
    }
  }

  Widget _buildPreview() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: _kDocumentViewTypeId,
          creationParams: const <String, Object?>{},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.iOS:
        // iOS classifies frames on-device with the C++ GuidanceClassifier, so
        // hand it the same thresholds the Dart FSM would have used. Android's
        // embedded view still classifies in Dart this slice, hence its empty
        // params above.
        return UiKitView(
          viewType: _kDocumentViewTypeId,
          creationParams: <String, Object?>{
            'guidanceConfig': widget.guidance.toConfigFloatArray(),
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return _UnsupportedPlatformPlaceholder(
          palette: widget.palette,
          message: widget.strings.unsupportedPlatform,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Guidance painter
// ---------------------------------------------------------------------------

/// Builds the internal document-guidance painter for tests; the painter type
/// is library-private, so this is the only sanctioned construction seam.
@visibleForTesting
CustomPainter makeDocumentGuidancePainter({
  required SupyDocumentGuidanceFrame frame,
  required Color scrimColor,
  required Color bracketColor,
  required double pulseValue,
  required Color warningColor,
  required Color readyColor,
  double lockFlash = 0.0,
}) => _DocumentGuidancePainter(
  frame: frame,
  scrimColor: scrimColor,
  bracketColor: bracketColor,
  pulseValue: pulseValue,
  warningColor: warningColor,
  readyColor: readyColor,
  lockFlash: lockFlash,
);

class _DocumentGuidancePainter extends CustomPainter {
  _DocumentGuidancePainter({
    required this.frame,
    required this.scrimColor,
    required this.bracketColor,
    required this.pulseValue,
    required this.warningColor,
    required this.readyColor,
    this.lockFlash = 0.0,
  });

  final SupyDocumentGuidanceFrame frame;
  final Color scrimColor;
  final Color bracketColor;
  final double pulseValue; // 0..1 from the pulse AnimationController
  final Color warningColor;
  final Color readyColor;

  // 1→0 one-shot lock flash; 0 when idle. Draws a decaying full-quad outline.
  final double lockFlash;

  static const double _bracketLen = 22.0;
  static const double _strokeWidth = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final quad = frame.metrics.quad;

    if (quad.length != 4) {
      _paintScrimFull(canvas, size);
      _paintReticles(canvas, size);
      return;
    }

    final mapPoint = _coverMapper(size, frame.metrics.sourceAspectRatio);
    final points = quad.map(mapPoint).toList(growable: false);

    final quadPath = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      quadPath.lineTo(points[i].dx, points[i].dy);
    }
    quadPath.close();

    // Scrim with cutout inside quad
    final scrim = Path()..addRect(Offset.zero & size);
    final cutout = Path.combine(PathOperation.difference, scrim, quadPath);
    canvas.drawPath(cutout, Paint()..color = scrimColor);

    // Four corner brackets only — no full outline
    _paintCornerBrackets(canvas, points);

    // One-shot success flash: the full quad outline snaps on at `readyColor`
    // on lock and fades as [lockFlash] decays 1→0.
    if (lockFlash > 0.0) {
      _paintLockFlash(canvas, quadPath);
    }
  }

  /// Builds a normalized-quad → view-pixel mapper that reproduces the native
  /// preview's `BoxFit.cover` crop.
  ///
  /// The native preview layer fills the platform view, scaling the camera frame
  /// up until it covers the whole view and letting the overflow spill past the
  /// edges. The quad, however, is normalized against the *full* (uncropped)
  /// frame. Mapping it straight onto the view rect (`p.dx * width`) therefore
  /// drifts off the real document whenever the frame and the view disagree on
  /// aspect ratio — the bug this corrects.
  ///
  /// Given [srcAspect] (the frame's width/height in the preview's orientation)
  /// we recompute the displayed frame size the same way `cover` does, then
  /// offset every point by the cropped margin. When [srcAspect] is unknown
  /// (`null` — older payloads, or platforms whose preview fills without a crop)
  /// we fall back to the identity stretch, which is the pre-fix behavior.
  static Offset Function(Offset) _coverMapper(Size size, double? srcAspect) {
    if (srcAspect == null || srcAspect <= 0 || size.height == 0) {
      return (p) => Offset(p.dx * size.width, p.dy * size.height);
    }
    final viewAspect = size.width / size.height;
    final double displayedW;
    final double displayedH;
    if (srcAspect > viewAspect) {
      // Frame is wider than the view: height fills, width overflows the sides.
      displayedH = size.height;
      displayedW = size.height * srcAspect;
    } else {
      // Frame is taller than the view: width fills, height overflows top/bottom.
      displayedW = size.width;
      displayedH = size.width / srcAspect;
    }
    final dx = (size.width - displayedW) / 2.0;
    final dy = (size.height - displayedH) / 2.0;
    return (p) => Offset(dx + p.dx * displayedW, dy + p.dy * displayedH);
  }

  /// Full-quad outline flashed once on lock, its alpha tracking [lockFlash] 1→0.
  void _paintLockFlash(Canvas canvas, Path quadPath) {
    final alpha = lockFlash.clamp(0.0, 1.0);
    canvas.drawPath(
      quadPath,
      Paint()
        ..color = readyColor.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth + 2.0
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintScrimFull(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = scrimColor);
  }

  /// Growing L-shaped reticles at four image corners when no quad detected.
  void _paintReticles(Canvas canvas, Size size) {
    // pulseValue 0→1→0; reticle arm length pulses between 16 and 28 px
    final armLen = 16.0 + 12.0 * pulseValue;
    final alpha = 0.55 + 0.45 * pulseValue; // 0.55 .. 1.0
    final paint =
        Paint()
          ..color = warningColor.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.square;

    const margin = 28.0;
    final corners = <Offset>[
      const Offset(margin, margin), // TL
      Offset(size.width - margin, margin), // TR
      Offset(size.width - margin, size.height - margin), // BR
      Offset(margin, size.height - margin), // BL
    ]; // const not possible: size.width/height not const
    // Arm directions: [right, down], [left, down], [left, up], [right, up]
    final hDirs = [1.0, -1.0, -1.0, 1.0];
    final vDirs = [1.0, 1.0, -1.0, -1.0];

    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      canvas.drawLine(c, c.translate(armLen * hDirs[i], 0), paint);
      canvas.drawLine(c, c.translate(0, armLen * vDirs[i]), paint);
    }
  }

  /// Four L-shaped corner brackets along the detected quad edges.
  void _paintCornerBrackets(Canvas canvas, List<Offset> pts) {
    final paint =
        Paint()
          ..color = bracketColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.square;

    // pts: TL(0), TR(1), BR(2), BL(3) — or whatever winding native sends.
    // Draw brackets at each corner: two arms along the adjacent edges.
    for (var i = 0; i < 4; i++) {
      final prev = pts[(i + 3) % 4];
      final curr = pts[i];
      final next = pts[(i + 1) % 4];

      final toPrev = _clampedAlong(curr, prev, _bracketLen);
      final toNext = _clampedAlong(curr, next, _bracketLen);

      canvas.drawLine(curr, toPrev, paint);
      canvas.drawLine(curr, toNext, paint);
    }
  }

  /// Returns a point [len] pixels from [from] toward [to], clamped to the
  /// segment length.
  static Offset _clampedAlong(Offset from, Offset to, double len) {
    final delta = to - from;
    final dist = delta.distance;
    if (dist == 0) return from;
    return from + delta / dist * math.min(len, dist);
  }

  @override
  bool shouldRepaint(covariant _DocumentGuidancePainter old) =>
      old.frame != frame ||
      old.scrimColor != scrimColor ||
      old.bracketColor != bracketColor ||
      old.warningColor != warningColor ||
      old.readyColor != readyColor ||
      old.pulseValue != pulseValue ||
      old.lockFlash != lockFlash;
}

// ---------------------------------------------------------------------------
// Hint card — coaching pill with a per-state icon
// ---------------------------------------------------------------------------

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.text,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
    required this.shadowColor,
    required this.textColor,
  });

  final String text;
  final IconData icon;

  /// Pill background (scrim over the preview).
  final Color backgroundColor;

  /// Drop-shadow tint under the pill.
  final Color shadowColor;

  /// Hint copy color.
  final Color textColor;

  /// State-derived accent used to tint the icon (green when ready, the
  /// not-ready palette otherwise).
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder:
            (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                child: child,
              ),
            ),
        // Key on text+icon so the switcher animates whenever either changes
        // (e.g. the directional arrow flipping while the copy is unchanged).
        child: DecoratedBox(
          key: ValueKey<String>('${icon.codePoint}:$text'),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: accentColor, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unsupported platform placeholder
// ---------------------------------------------------------------------------

class _UnsupportedPlatformPlaceholder extends StatelessWidget {
  const _UnsupportedPlatformPlaceholder({
    required this.palette,
    required this.message,
  });

  final SupyScannerPalette palette;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            style: TextStyle(color: palette.onSurface),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
