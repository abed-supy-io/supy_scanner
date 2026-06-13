import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channel/supy_event_channel.dart';
import '../models/supy_barcode.dart';
import '../models/supy_scan_error.dart';
import '../models/supy_scan_options.dart';
import 'supy_barcode_scanner_controller.dart';

/// View-type identifier registered by the native PlatformView factories.
const String _kBarcodeViewTypeId = 'io.supy.scanner/v1/barcode_view';

/// Default debounce between two consecutive barcode detections delivered to
/// [SupyBarcodeScannerView.onBarcodeDetected].
const Duration kDefaultBarcodeCooldown = Duration(seconds: 2);

/// Embedded native barcode scanner with finder overlay.
///
/// Android renders a CameraX preview with an ML Kit analyzer (S1-08 / S1-09).
/// iOS support lands in Sprint 2.
class SupyBarcodeScannerView extends StatefulWidget {
  /// Creates an embedded barcode scanner view.
  const SupyBarcodeScannerView({
    super.key,
    this.options = const SupyBarcodeScanOptions(),
    this.onBarcodeDetected,
    this.onError,
    this.onPreviewStarted,
    this.controller,
    this.cooldown = kDefaultBarcodeCooldown,
    this.showFinder = true,
    this.header,
    this.footer,
  });

  /// Scanner configuration (active formats, scan window, etc.).
  final SupyBarcodeScanOptions options;

  /// Fired for each detected barcode, subject to [cooldown] debouncing.
  ///
  /// When multiple barcodes are detected in the same frame, only the first is
  /// emitted (matches Scanbot single-scan behavior).
  final ValueChanged<SupyBarcode>? onBarcodeDetected;

  /// Fired when the native side reports an error.
  final ValueChanged<SupyScanError>? onError;

  /// Fired once the first camera frame has rendered.
  final ValueChanged<SupyPreviewStartedEvent>? onPreviewStarted;

  /// Optional controller for torch / pause / resume / setFormats.
  final SupyBarcodeScannerController? controller;

  /// Minimum interval between two [onBarcodeDetected] callbacks. Defaults to 2s.
  final Duration cooldown;

  /// Whether to render the central viewfinder overlay. Default `true`.
  final bool showFinder;

  /// Optional widget placed above the camera (e.g., title bar).
  final Widget? header;

  /// Optional widget placed below the camera (e.g., instructions).
  final Widget? footer;

  @override
  State<SupyBarcodeScannerView> createState() => _SupyBarcodeScannerViewState();
}

class _SupyBarcodeScannerViewState extends State<SupyBarcodeScannerView> {
  StreamSubscription<SupyScannerEvent>? _eventSub;
  DateTime _lastEmitted = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    unawaited(_eventSub?.cancel());
    widget.controller?.detach();
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    widget.controller?.attach(MethodChannel(supyBarcodeMethodChannelName(id)));
    _eventSub = supyBarcodeEventStream(id).listen(_handleEvent);
  }

  void _handleEvent(SupyScannerEvent event) {
    switch (event) {
      case SupyDetectionEvent(:final items):
        if (items.isEmpty) return;
        final now = DateTime.now();
        if (now.difference(_lastEmitted) < widget.cooldown) return;
        _lastEmitted = now;
        widget.onBarcodeDetected?.call(items.first);
      case SupyPreviewStartedEvent():
        widget.onPreviewStarted?.call(event);
      case SupyErrorEvent(:final error):
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
          const Positioned.fill(
            child: IgnorePointer(child: _FinderOverlay()),
          ),
        if (widget.header != null)
          Positioned(top: 0, left: 0, right: 0, child: widget.header!),
        if (widget.footer != null)
          Positioned(bottom: 0, left: 0, right: 0, child: widget.footer!),
      ],
    );
  }

  Widget _buildPreview() {
    final creationParams = widget.options.toWire();

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: _kBarcodeViewTypeId,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: _kBarcodeViewTypeId,
          creationParams: creationParams,
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

class _FinderOverlay extends StatelessWidget {
  const _FinderOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FinderPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _FinderPainter extends CustomPainter {
  static const Color _scrim = Color(0x99000000);
  static const Color _border = Color(0xFF6448C3);
  static const double _cornerRadius = 16;
  static const double _strokeWidth = 3;
  static const double _widthRatio = 0.78;
  static const double _aspect = 0.62;

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
    canvas.drawRect(Offset.zero & size, Paint()..color = _scrim);
    canvas.drawRRect(
      rrect,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = _border
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _FinderPainter oldDelegate) => false;
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
            'SupyBarcodeScannerView is not yet supported on '
            '${defaultTargetPlatform.name}.',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
