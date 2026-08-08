import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channel/supy_datacapture_event_channel.dart';
import '../datacapture/supy_text_pattern_matcher.dart';
import '../models/datacapture/supy_text_pattern.dart';
import '../models/datacapture/supy_text_pattern_match.dart';
import '../models/supy_scan_error.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import 'supy_text_pattern_scanner_controller.dart';

/// View-type identifier registered by the native PlatformView factories.
const String _kDataCaptureViewTypeId = 'io.supy.scanner/v1/datacapture_view';

/// Default debounce, keyed by matched value, between two consecutive matches of
/// the same text delivered to [SupyTextPatternScannerView.onMatch].
const Duration kDefaultTextPatternCooldown = Duration(seconds: 2);

/// Embedded live text-pattern (generic data-capture) scanner.
///
/// The native side runs OCR per frame and streams the recognized-text geometry;
/// [SupyTextPatternMatcher] runs [patterns] over it on-device (pure Dart) and
/// [onMatch] fires for each hit, debounced per matched value by [cooldown].
class SupyTextPatternScannerView extends StatefulWidget {
  /// Creates an embedded text-pattern scanner view.
  const SupyTextPatternScannerView({
    required this.patterns,
    super.key,
    this.onMatch,
    this.onError,
    this.onPreviewStarted,
    this.controller,
    this.languages,
    this.cooldown = kDefaultTextPatternCooldown,
    this.showFinder = true,
    this.header,
    this.footer,
    this.palette = const SupyScannerPalette.supyDark(),
    this.strings = const SupyScannerStrings.en(),
  });

  /// The patterns to detect in the OCR stream.
  final List<SupyTextPattern> patterns;

  /// Fired for each match, debounced per matched value by [cooldown].
  final ValueChanged<SupyTextPatternMatch>? onMatch;

  /// Fired when the native side reports an error.
  final ValueChanged<SupyScanError>? onError;

  /// Fired once the first camera frame has rendered.
  final ValueChanged<SupyDataCapturePreviewStartedEvent>? onPreviewStarted;

  /// Optional controller for torch / pause / resume.
  final SupyTextPatternScannerController? controller;

  /// Optional BCP-47 language hints for the native OCR engine (e.g. `['en']`).
  /// `null` lets the platform pick its default (device locale).
  final List<String>? languages;

  /// Minimum interval between two [onMatch] callbacks for the same matched
  /// value. Defaults to 2s.
  final Duration cooldown;

  /// Whether to render the central viewfinder overlay. Default `true`.
  final bool showFinder;

  /// Optional widget placed above the camera (e.g., title bar).
  final Widget? header;

  /// Optional widget placed below the camera (e.g., instructions).
  final Widget? footer;

  /// Palette used to resolve the finder overlay and placeholder colors.
  final SupyScannerPalette palette;

  /// String bundle used to resolve the unsupported-platform placeholder text.
  final SupyScannerStrings strings;

  @override
  State<SupyTextPatternScannerView> createState() =>
      _SupyTextPatternScannerViewState();
}

class _SupyTextPatternScannerViewState
    extends State<SupyTextPatternScannerView> {
  StreamSubscription<SupyDataCaptureEvent>? _eventSub;
  final Map<String, DateTime> _lastEmitted = <String, DateTime>{};

  @override
  void dispose() {
    unawaited(_eventSub?.cancel());
    widget.controller?.detach();
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    widget.controller?.attach(
      MethodChannel(supyDataCaptureMethodChannelName(id)),
    );
    _eventSub = supyDataCaptureEventStream(id).listen(_handleEvent);
  }

  void _handleEvent(SupyDataCaptureEvent event) {
    switch (event) {
      case SupyDataCaptureFrameEvent(:final text):
        final matches = SupyTextPatternMatcher.match(text, widget.patterns);
        if (matches.isEmpty) return;
        final now = DateTime.now();
        for (final match in matches) {
          final last = _lastEmitted[match.value];
          if (last != null && now.difference(last) < widget.cooldown) continue;
          _lastEmitted[match.value] = now;
          widget.onMatch?.call(match);
        }
      case SupyDataCapturePreviewStartedEvent():
        widget.onPreviewStarted?.call(event);
      case SupyDataCaptureErrorEvent(:final error):
        widget.onError?.call(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _buildPreview();

    return Stack(
      fit: StackFit.expand,
      children: [
        preview,
        if (widget.showFinder)
          Positioned.fill(
            child: IgnorePointer(
              child: _FinderOverlay(palette: widget.palette),
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
    final creationParams = <String, Object?>{
      if (widget.languages != null) 'languages': widget.languages,
    };

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: _kDataCaptureViewTypeId,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: _kDataCaptureViewTypeId,
          creationParams: creationParams,
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

class _FinderOverlay extends StatelessWidget {
  const _FinderOverlay({required this.palette});

  final SupyScannerPalette palette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FinderPainter(palette: palette),
      child: const SizedBox.expand(),
    );
  }
}

class _FinderPainter extends CustomPainter {
  _FinderPainter({required this.palette});

  final SupyScannerPalette palette;

  static const double _cornerRadius = 16;
  static const double _strokeWidth = 3;
  static const double _widthRatio = 0.82;
  static const double _aspect = 0.34;

  @override
  void paint(Canvas canvas, Size size) {
    final boxWidth = size.width * _widthRatio;
    final boxHeight = boxWidth * _aspect;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: boxWidth,
      height: boxHeight,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_cornerRadius),
    );

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.modalOverlay);
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = palette.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _FinderPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

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
