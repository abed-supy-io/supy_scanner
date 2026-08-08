import 'dart:async';

import 'package:flutter/material.dart';

import '../models/supy_barcode.dart';
import '../models/supy_scan_options.dart';
import '../models/ui/supy_action_bar_configuration.dart';
import '../models/ui/supy_ar_overlay_configuration.dart';
import '../models/ui/supy_scan_use_case.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import '../models/ui/supy_top_bar_configuration.dart';
import '../models/ui/supy_user_guidance_configuration.dart';
import '../models/ui/supy_view_finder_configuration.dart';
import 'supy_action_bar.dart';
import 'supy_ar_overlay.dart';
import 'supy_barcode_scanner_controller.dart';
import 'supy_barcode_scanner_view.dart';
import 'supy_find_and_pick_accumulator.dart';
import 'supy_find_and_pick_sheet.dart';
import 'supy_finder_painter.dart';
import 'supy_multiple_scan_accumulator.dart';
import 'supy_multiple_scan_sheet.dart';
import 'supy_single_scan_confirmation_sheet.dart';
import 'supy_top_bar.dart';
import 'supy_user_guidance_card.dart';

/// Full-screen composite Scanbot-parity scanner screen.
///
/// Picks a bottom sheet and result-routing strategy based on the
/// [SupyScanUseCase] variant: single → confirmation sheet (or immediate
/// submit when [SupySingleScanUseCaseConfiguration.confirmationSheetEnabled]
/// is false), multiple → counting/unique accumulator sheet, find-and-pick →
/// expected-list sheet (submit gated on completion).
///
/// Composes [SupyBarcodeScannerView] (preview) with [SupyArOverlay], the
/// cornered finder painter, [SupyTopBar], [SupyUserGuidanceCard], and
/// [SupyActionBar]. Owns its own [SupyBarcodeScannerController] unless one
/// is supplied via [controller].
@immutable
class SupyBarcodeScannerScreen extends StatefulWidget {
  /// Creates a Scanbot-parity composite scanner screen.
  const SupyBarcodeScannerScreen({
    required this.useCase,
    super.key,
    this.scanOptions = const SupyBarcodeScanOptions(),
    this.palette = const SupyScannerPalette.supyDark(),
    this.locale,
    this.topBar = const SupyTopBarConfiguration(),
    this.viewFinder = const SupyViewFinderConfiguration(),
    this.userGuidance = const SupyUserGuidanceConfiguration(),
    this.actionBar = const SupyActionBarConfiguration(),
    this.arOverlay = const SupyArOverlayConfiguration(),
    this.controller,
    this.onSingleScan,
    this.onMultipleScan,
    this.onFindAndPick,
    this.onCancel,
    this.onError,
  });

  /// The active use case — drives sheet selection + result-callback routing.
  final SupyScanUseCase useCase;

  /// Native scanner options (formats, scan window, camera, native-core flag).
  final SupyBarcodeScanOptions scanOptions;

  /// Palette tokens used for top-bar / sheets / overlay defaults. Currently
  /// passed through to children that already wire their own configs — kept
  /// here so callers can theme the whole screen in one place.
  final SupyScannerPalette palette;

  /// BCP-47 language code (`'en'`, `'ar'`, …) selecting the built-in string
  /// bundle and text direction for all chrome the configs leave unset. When
  /// null, falls back to the ambient [Localizations] locale, then English.
  /// Additive — Scanbot call sites that never passed a locale keep English.
  final String? locale;

  /// Top-bar (cancel button + scrim) configuration.
  final SupyTopBarConfiguration topBar;

  /// Cornered finder configuration. Set `visible: false` to hide.
  final SupyViewFinderConfiguration viewFinder;

  /// Guidance-card configuration. Set `visible: false` to hide.
  final SupyUserGuidanceConfiguration userGuidance;

  /// Action-bar configuration (flash / zoom / flip / close-focus).
  final SupyActionBarConfiguration actionBar;

  /// AR overlay (per-barcode bounding boxes + labels) configuration.
  final SupyArOverlayConfiguration arOverlay;

  /// Optional externally-owned controller. When omitted, the screen creates
  /// and disposes its own.
  final SupyBarcodeScannerController? controller;

  /// Called for the single-scan use case. With the default confirmation
  /// sheet, fires when the user confirms; with the sheet disabled, fires
  /// immediately on first detection.
  final ValueChanged<SupyBarcode>? onSingleScan;

  /// Called when the user submits the multi-scan sheet. Receives the
  /// accumulated items (with their counts for counting mode).
  final ValueChanged<List<SupyMultipleScanItem>>? onMultipleScan;

  /// Called when the user submits a complete find-and-pick run. Receives
  /// the per-expected-row progress (every row [SupyFindAndPickRow.isComplete]).
  final ValueChanged<List<SupyFindAndPickRow>>? onFindAndPick;

  /// Called when the user taps the top-bar cancel button.
  final VoidCallback? onCancel;

  /// Called when the native side reports an error.
  final ValueChanged<Object>? onError;

  @override
  State<SupyBarcodeScannerScreen> createState() =>
      _SupyBarcodeScannerScreenState();
}

class _SupyBarcodeScannerScreenState extends State<SupyBarcodeScannerScreen> {
  late final SupyBarcodeScannerController _controller;
  late final bool _ownsController;

  SupyMultipleScanAccumulator? _multiAcc;
  SupyFindAndPickAccumulator? _findAcc;

  // Single-scan: when set, the confirmation sheet is shown for this barcode.
  SupyBarcode? _pendingSingle;

  // Latest detection — used to render the AR overlay (one box at a time).
  List<SupyBarcode> _latest = const [];

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? SupyBarcodeScannerController();
    switch (widget.useCase) {
      case SupySingleScanUseCase():
        break;
      case SupyMultipleScanUseCase(:final config):
        _multiAcc = SupyMultipleScanAccumulator(config: config);
      case SupyFindAndPickUseCase(:final config):
        _findAcc = SupyFindAndPickAccumulator(config: config);
    }
  }

  @override
  void dispose() {
    _multiAcc?.dispose();
    _findAcc?.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onDetected(SupyBarcode barcode) {
    setState(() => _latest = [barcode]);
    switch (widget.useCase) {
      case SupySingleScanUseCase(:final config):
        if (!config.confirmationSheetEnabled) {
          widget.onSingleScan?.call(barcode);
          return;
        }
        // Pause preview while the user confirms.
        unawaited(_controller.pause());
        setState(() => _pendingSingle = barcode);
      case SupyMultipleScanUseCase():
        _multiAcc?.offer(barcode, now: DateTime.now());
      case SupyFindAndPickUseCase():
        _findAcc?.offer(barcode);
    }
  }

  void _retrySingle() {
    setState(() => _pendingSingle = null);
    unawaited(_controller.resume());
  }

  void _confirmSingle() {
    final b = _pendingSingle;
    if (b == null) return;
    widget.onSingleScan?.call(b);
  }

  Widget? _buildSheet(SupyScannerStrings strings) {
    switch (widget.useCase) {
      case SupySingleScanUseCase(:final config):
        final pending = _pendingSingle;
        if (pending == null) return null;
        return SupySingleScanConfirmationSheet(
          barcode: pending,
          config: config,
          palette: widget.palette,
          strings: strings,
          onConfirm: _confirmSingle,
          onRetry: _retrySingle,
        );
      case SupyMultipleScanUseCase(:final config):
        return SupyMultipleScanSheet(
          accumulator: _multiAcc!,
          config: config,
          palette: widget.palette,
          strings: strings,
          onSubmit: () => widget.onMultipleScan?.call(_multiAcc!.items),
          onClear: _multiAcc!.clear,
        );
      case SupyFindAndPickUseCase(:final config):
        return SupyFindAndPickSheet(
          accumulator: _findAcc!,
          config: config,
          palette: widget.palette,
          strings: strings,
          onSubmit: () => widget.onFindAndPick?.call(_findAcc!.rows),
          onClear: _findAcc!.clear,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SupyScannerStrings.of(
      widget.locale ?? Localizations.maybeLocaleOf(context)?.languageCode,
    );
    final sheet = _buildSheet(strings);
    return Directionality(
      textDirection: strings.textDirection,
      child: Scaffold(
        backgroundColor: widget.palette.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SupyBarcodeScannerView(
              options: widget.scanOptions,
              controller: _controller,
              onBarcodeDetected: _onDetected,
              onError: (e) => widget.onError?.call(e),
              showFinder: false,
              palette: widget.palette,
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: SupyFinderPainter(
                    config: widget.viewFinder,
                    palette: widget.palette,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: SupyArOverlay(
                  barcodes: _latest,
                  config: widget.arOverlay,
                  palette: widget.palette,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SupyTopBar(
                config: widget.topBar,
                palette: widget.palette,
                strings: strings,
                onCancel: () => widget.onCancel?.call(),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: sheet == null ? 120 : 220,
              child: Center(
                child: SupyUserGuidanceCard(
                  config: widget.userGuidance,
                  palette: widget.palette,
                  strings: strings,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SupyActionBar(
                    config: widget.actionBar,
                    controller: _controller,
                    palette: widget.palette,
                    strings: strings,
                  ),
                  if (sheet != null) sheet,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
