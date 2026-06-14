import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channel/supy_document_event_channel.dart';
import '../document/supy_document_state_machine.dart';
import '../models/supy_document_frame_metrics.dart';
import '../models/supy_document_frame_state.dart';
import '../models/supy_scan_error.dart';
import '../models/ui/supy_document_guidance_configuration.dart';
import 'supy_document_scanner_controller.dart';

/// View-type identifier registered by the native PlatformView factories.
const String _kDocumentViewTypeId = 'io.supy.scanner/v1/document_view';

/// Embedded native document scanner with live edge-guidance overlay.
///
/// The widget mounts a PlatformView (UiKitView on iOS, AndroidView on Android),
/// subscribes to its per-view EventChannel, feeds each `frame_metrics` payload
/// into a [SupyDocumentStateMachine], and paints a scrim + quad outline +
/// hint text driven by the resulting [SupyDocumentGuidanceFrame].
///
/// The outline turns green when the state machine reports
/// [SupyDocumentFrameState.ready]; everything else paints it red with a
/// per-state hint ("Move closer", "Hold steady", etc.).
class SupyDocumentScannerView extends StatefulWidget {
  /// Creates an embedded document scanner view.
  const SupyDocumentScannerView({
    super.key,
    this.guidance = const SupyDocumentGuidanceConfiguration(),
    this.controller,
    this.onGuidance,
    this.onReady,
    this.onError,
    this.onPreviewStarted,
    this.showOverlay = true,
    this.header,
    this.footer,
  });

  /// Thresholds + palette + hint copy.
  final SupyDocumentGuidanceConfiguration guidance;

  /// Optional controller for `pause`/`resume`/`setTorch`.
  final SupyDocumentScannerController? controller;

  /// Fires on every frame after the state machine ticks. Useful for analytics
  /// or driving consumer-side UI.
  final ValueChanged<SupyDocumentGuidanceFrame>? onGuidance;

  /// Fires the **first** time the state machine reports `ready`. Designed as
  /// the auto-snap trigger for the consuming feature (capture/OCR is wired
  /// downstream of this prototype).
  final ValueChanged<SupyDocumentGuidanceFrame>? onReady;

  /// Fires when the native side reports an error.
  final ValueChanged<SupyScanError>? onError;

  /// Fires once the first camera frame has rendered.
  final ValueChanged<bool>? onPreviewStarted;

  /// Whether to paint the guidance overlay on top of the preview. Default
  /// `true`. Disable when embedding the view inside a custom overlay stack.
  final bool showOverlay;

  /// Optional widget placed above the camera.
  final Widget? header;

  /// Optional widget placed below the camera.
  final Widget? footer;

  @override
  State<SupyDocumentScannerView> createState() =>
      _SupyDocumentScannerViewState();
}

class _SupyDocumentScannerViewState extends State<SupyDocumentScannerView> {
  late final SupyDocumentStateMachine _stateMachine =
      SupyDocumentStateMachine(configuration: widget.guidance);

  StreamSubscription<SupyDocumentEvent>? _eventSub;
  SupyDocumentGuidanceFrame _frame = const SupyDocumentGuidanceFrame(
    state: SupyDocumentFrameState.noDocument,
    metrics: SupyDocumentFrameMetrics(),
    framesAtState: 0,
  );
  bool _readyAnnounced = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SupyDocumentScannerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guidance != widget.guidance) {
      _stateMachine.configuration = widget.guidance;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    unawaited(_eventSub?.cancel());
    widget.controller?.removeListener(_onControllerChanged);
    widget.controller?.detach();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// FSM-emitted state, with the controller's capture phase overlaid on top.
  /// `capturing`/`captured` are UI-only and only ever come from the controller.
  SupyDocumentFrameState get _effectiveState =>
      widget.controller?.capturePhaseAsFrameState ?? _frame.state;

  void _onPlatformViewCreated(int id) {
    widget.controller?.attach(MethodChannel(supyDocumentMethodChannelName(id)));
    _eventSub = supyDocumentEventStream(id).listen(_handleEvent);
  }

  void _handleEvent(SupyDocumentEvent event) {
    switch (event) {
      case SupyDocumentFrameMetricsEvent(:final metrics):
        final next = _stateMachine.tick(metrics);
        setState(() => _frame = next);
        widget.onGuidance?.call(next);
        if (next.state == SupyDocumentFrameState.ready && !_readyAnnounced) {
          _readyAnnounced = true;
          widget.onReady?.call(next);
        } else if (next.state != SupyDocumentFrameState.ready) {
          _readyAnnounced = false;
        }
      case SupyDocumentPreviewStartedEvent(:final flashAvailable):
        widget.onPreviewStarted?.call(flashAvailable);
      case SupyDocumentErrorEvent(:final error):
        widget.onError?.call(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPreview(),
        if (widget.showOverlay)
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  end: widget.guidance.colorFor(_effectiveState) ==
                          widget.guidance.readyColor
                      ? 1.0
                      : 0.0,
                ),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                builder: (context, readyT, _) {
                  final color = Color.lerp(
                    widget.guidance.notReadyColor,
                    widget.guidance.readyColor,
                    readyT,
                  )!;
                  return CustomPaint(
                    painter: _DocumentGuidancePainter(
                      frame: _frame,
                      scrimColor: widget.guidance.scrimColor,
                      strokeColor: color,
                      fillAlpha: 0.15 * readyT,
                    ),
                  );
                },
              ),
            ),
          ),
        if (widget.showOverlay)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: IgnorePointer(
              child: _HintCard(
                text: widget.guidance.hintFor(_effectiveState),
                color: widget.guidance.colorFor(_effectiveState),
                scrim: widget.guidance.scrimColor,
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
        return UiKitView(
          viewType: _kDocumentViewTypeId,
          creationParams: const <String, Object?>{},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return const _UnsupportedPlatformPlaceholder();
    }
  }
}

class _DocumentGuidancePainter extends CustomPainter {
  _DocumentGuidancePainter({
    required this.frame,
    required this.scrimColor,
    required this.strokeColor,
    required this.fillAlpha,
  });

  final SupyDocumentGuidanceFrame frame;
  final Color scrimColor;
  final Color strokeColor;
  final double fillAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final quad = frame.metrics.quad;
    if (quad.length != 4) return;

    final points = quad
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList(growable: false);

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();

    final scrim = Path()..addRect(Offset.zero & size);
    final cutout = Path.combine(PathOperation.difference, scrim, path);
    canvas.drawPath(cutout, Paint()..color = scrimColor);

    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );

    if (fillAlpha > 0.0) {
      canvas.drawPath(
        path,
        Paint()..color = strokeColor.withValues(alpha: fillAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DocumentGuidancePainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.scrimColor != scrimColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillAlpha != fillAlpha;
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.text,
    required this.color,
    required this.scrim,
  });

  final String text;
  final Color color;
  final Color scrim;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, borderColor, child) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: scrim,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor ?? color, width: 2),
            ),
            child: child,
          );
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            text,
            key: ValueKey<String>(text),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnsupportedPlatformPlaceholder extends StatelessWidget {
  const _UnsupportedPlatformPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'SupyDocumentScannerView is not yet supported on '
            '${defaultTargetPlatform.name}.',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
