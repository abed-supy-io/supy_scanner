import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import 'barcode_item.dart';

/// Retailer-facing controller. Mirrors the local `BarcodeScannerController`
/// defined alongside the old Scanbot view — `pause` / `resume` / `toggle`,
/// plus the `bind` hook the original used to wire its internal pause notifier.
///
/// Internally drives a [SupyBarcodeScannerController]; the [bind] callback is
/// kept as a no-op-friendly shim so retailer test doubles still work.
class BarcodeScannerController {
  /// Creates a new controller. The underlying Supy controller is constructed
  /// eagerly so callers can read [supyController] before mounting a view.
  BarcodeScannerController();

  final SupyBarcodeScannerController _inner = SupyBarcodeScannerController();

  ValueNotifier<bool>? _pausedNotifier;

  /// Wired by `BarcodeScanbotView` during `initState`. Not part of the public
  /// retailer-visible API; exposed only so the view can share its notifier.
  // ignore: use_setters_to_change_properties
  void bindInternal(ValueNotifier<bool> pausedNotifier) {
    _pausedNotifier = pausedNotifier;
  }

  /// Legacy hook from the Scanbot-era controller. Kept as a no-op so any
  /// retailer code that called `bind(...)` directly still compiles.
  void bind({
    required ValueNotifier<bool> pausedNotifier,
    void Function()? pause,
    void Function()? resume,
  }) {
    _pausedNotifier = pausedNotifier;
  }

  /// Underlying Supy controller. Exposed for advanced callers and for
  /// `BarcodeScanbotView` to drive the embedded preview.
  SupyBarcodeScannerController get supyController => _inner;

  /// True when scanning is currently suspended.
  bool get isPaused => _pausedNotifier?.value ?? _inner.paused;

  /// Suspends barcode detection without tearing down the camera session.
  Future<void> pause() async {
    await _inner.pause();
    _pausedNotifier?.value = true;
  }

  /// Resumes barcode detection after a prior [pause].
  Future<void> resume() async {
    await _inner.resume();
    _pausedNotifier?.value = false;
  }

  /// Flips between [pause] and [resume] based on [isPaused].
  Future<void> toggle() async => isPaused ? resume() : pause();
}

/// Drop-in replacement for the retailer's `BarcodeScanbotView`.
///
/// API surface preserved verbatim — same constructor parameters, same
/// `onBarcodeDetected(List<BarcodeItem>)` callback, same cooldown semantics.
/// `scannerBoxBuilder` and `scanWindow` are accepted for source-compat but
/// the underlying Supy view renders its own finder overlay (controlled by
/// [useScanWindow]).
class BarcodeScanbotView extends StatefulWidget {
  /// See class docs.
  const BarcodeScanbotView({
    required this.onBarcodeDetected,
    super.key,
    this.header,
    this.footer,
    this.useScanWindow = true,
    this.findBarcodeAtCenter = true,
    this.scannerBoxBuilder,
    this.controller,
    this.scanWindow,
  });

  /// Called every time a barcode is detected. The list contains exactly one
  /// item under the Supy backend; it's a list purely for Scanbot-shape
  /// compatibility.
  final Future<void> Function(List<BarcodeItem> barcodes) onBarcodeDetected;

  /// Optional widget overlaid above the camera preview.
  final Widget? header;

  /// Optional widget overlaid below the camera preview.
  final Widget? footer;

  /// Whether to render and use the centered scan window.
  final bool useScanWindow;

  /// Builder for a custom finder box. Currently informational only — the
  /// underlying Supy view supplies its own finder.
  final Widget Function(bool isActive)? scannerBoxBuilder;

  /// Optional external controller. If null, the view manages its own.
  final BarcodeScannerController? controller;

  /// Whether to bias detection toward the centered scan window.
  final bool findBarcodeAtCenter;

  /// Custom scan window rect. Currently accepted for source-compat but the
  /// underlying view computes its own bounds from [useScanWindow].
  final Rect? scanWindow;

  @override
  State<BarcodeScanbotView> createState() => _BarcodeScanbotViewState();
}

class _BarcodeScanbotViewState extends State<BarcodeScanbotView> {
  final ValueNotifier<bool> _paused = ValueNotifier(false);
  late final SupyBarcodeScannerController _ownedController;

  SupyBarcodeScannerController get _controller =>
      widget.controller?.supyController ?? _ownedController;

  @override
  void initState() {
    super.initState();
    _ownedController = SupyBarcodeScannerController();
    widget.controller?.bindInternal(_paused);
  }

  @override
  void dispose() {
    _ownedController.dispose();
    _paused.dispose();
    super.dispose();
  }

  Future<void> _onBarcode(SupyBarcode b) async {
    if (_paused.value) return;
    _paused.value = true;
    try {
      await widget.onBarcodeDetected([BarcodeItem.fromSupy(b)]);
    } finally {
      if (mounted) _paused.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar here: the host app wraps this view in its own Scaffold and
    // passes the title chrome via [header]. Mirrors the original Scanbot
    // surface and keeps the library string-free for localization.
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: SupyBarcodeScannerView(
              controller: _controller,
              options: SupyBarcodeScanOptions(
                useScanWindow: widget.useScanWindow,
                findBarcodeAtCenter: widget.findBarcodeAtCenter,
              ),
              showFinder: widget.useScanWindow,
              onBarcodeDetected: _onBarcode,
            ),
          ),
          if (widget.header != null) widget.header!,
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
  }
}
