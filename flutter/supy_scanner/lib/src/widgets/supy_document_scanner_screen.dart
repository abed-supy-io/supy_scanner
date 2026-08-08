import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channel/supy_scanner_channel.dart';
import '../enhance/supy_document_enhance_mode.dart';
import '../models/supy_document_frame_state.dart';
import '../models/supy_document_page.dart';
import '../models/supy_scan_error.dart';
import '../models/supy_scan_options.dart';
import '../models/ui/supy_document_guidance_configuration.dart';
import '../models/ui/supy_document_scan_mode.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import 'supy_document_scanner_controller.dart';
import 'supy_document_scanner_view.dart';

/// Which of the branded document-session screens is currently on top.
enum _DocStage {
  /// The camera viewfinder: branded bar, live tracking overlay, capture bar.
  viewfinder,

  /// The captured-page review grid with the terminal finish action.
  review,
}

/// Full-screen, Supy-branded multi-page document session.
///
/// This is the Flutter-drawn parity surface for the native document scanner
/// (`VNDocumentCameraViewController` / GMS `GmsDocumentScanning`). It presents a
/// two-screen flow over the embedded [SupyDocumentScannerView] preview:
///
///  1. A branded viewfinder: a solid top bar (Cancel / "Scan Document" / help),
///     a top instruction hint, the view's live quad-tracking overlay with a
///     colour-coded status band, and a solid capture bar (gallery import,
///     auto-capture toggle, shutter, torch, and a tap-through page-stack thumb).
///  2. A page-review grid: the captured [SupyDocumentPage]s as thumbnails with a
///     dashed "add page" tile and a full-width finish action.
///
/// The [mode] governs capture flow only, never the returned type: Single /
/// Receipt advance straight to review after a capture, Multi accumulates in the
/// viewfinder. Every mode yields the same ordered `List<SupyDocumentPage>`, so
/// the surface stays drop-in Scanbot compatible.
///
/// Captures accumulate as [SupyDocumentPage]s (each a rectified still persisted
/// on disk); [onComplete] fires with the ordered pages when the user finishes.
/// Result routing mirrors [SupyBarcodeScannerScreen]'s callback style — the
/// screen never pops itself; the host wires [onComplete] / [onCancel] to
/// `Navigator.pop`.
@immutable
class SupyDocumentScannerScreen extends StatefulWidget {
  /// Creates a branded multi-page document session screen.
  const SupyDocumentScannerScreen({
    required this.onComplete,
    super.key,
    this.onCancel,
    this.onError,
    this.guidance = const SupyDocumentGuidanceConfiguration(),
    this.palette = const SupyScannerPalette.supyDark(),
    this.accentColor,
    this.maxPages = 0,
    this.locale = 'en',
    this.mode = SupyDocumentScanMode.single,
    this.frameLabel,
    this.controller,
  });

  /// Called when the user finishes the session. Receives the ordered pages
  /// (always non-empty; the finish action is unreachable until at least one
  /// page exists).
  final ValueChanged<List<SupyDocumentPage>> onComplete;

  /// Called when the user cancels without keeping any pages.
  final VoidCallback? onCancel;

  /// Called when the embedded view reports a capture / preview error.
  final ValueChanged<SupyScanError>? onError;

  /// Guidance thresholds + copy driving the embedded preview.
  ///
  /// Auto-capture is **off by default** in this branded session (manual
  /// shutter). Pass a config with `autoCapture: true` to re-enable the
  /// countdown-and-shoot behaviour.
  final SupyDocumentGuidanceConfiguration guidance;

  /// Palette tokens for the chrome (bars, frame, tabs, buttons).
  final SupyScannerPalette palette;

  /// Optional brand accent for the primary actions (frame, shutter ring, finish
  /// button, page-count badge). Defaults to [SupyScannerPalette.primary].
  final Color? accentColor;

  /// Maximum pages to capture. `0` means unlimited (matches Scanbot's
  /// `pagesScanLimit = 0`). On reaching the cap the preview pauses until a
  /// page is deleted.
  final int maxPages;

  /// Locale for the in-screen copy (`'ar'` for Arabic, `'en'` otherwise).
  final String locale;

  /// Initial capture mode (Single / Multi / Receipt). Governs capture flow
  /// only, never the returned page type.
  final SupyDocumentScanMode mode;

  /// Optional caption drawn inside the viewfinder frame (e.g. `'invoice'`). The
  /// library stays business-copy-free by default; the facade / retailer passes
  /// a domain noun. When null, the frame shows no caption.
  final String? frameLabel;

  /// Optional externally-owned controller. When omitted, the screen creates
  /// and disposes its own.
  final SupyDocumentScannerController? controller;

  @override
  State<SupyDocumentScannerScreen> createState() =>
      _SupyDocumentScannerScreenState();
}

class _SupyDocumentScannerScreenState extends State<SupyDocumentScannerScreen>
    with SingleTickerProviderStateMixin {
  late final SupyDocumentScannerController _controller;
  late final bool _ownsController;

  // Drives the white capture flash. Held at 0 (invisible); a capture kicks it
  // to 1 and reverses back to 0, giving the shutter a visible "it fired" cue
  // even when a page just accumulates in the viewfinder (Multi mode).
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  final List<SupyDocumentPage> _pages = <SupyDocumentPage>[];
  bool _torchOn = false;
  bool _busy = false;
  late final SupyDocumentScanMode _mode = widget.mode;
  // Auto-capture is a live toggle in the capture bar, seeded from the incoming
  // config. Off by default (manual shutter); flipping it rebuilds the embedded
  // view's guidance via [_effectiveGuidance] so the countdown arms/disarms.
  late bool _autoCapture = widget.guidance.autoCapture;
  _DocStage _stage = _DocStage.viewfinder;
  // Null until the first guidance frame arrives; the status band shows a
  // steady-hold prompt in the meantime (matching the branded viewfinder spec).
  SupyDocumentFrameState? _frameState;

  SupyScannerStrings get _strings => SupyScannerStrings.of(widget.locale);
  bool get _reachedMax =>
      widget.maxPages > 0 && _pages.length >= widget.maxPages;
  Color get _accent => widget.accentColor ?? widget.palette.primary;

  // Maps a page's quality bucket onto a palette severity token for the
  // review-grid badge dot/text. Informational only - never gates capture.
  Color _qualityColor(SupyDocumentPageQuality quality) {
    switch (quality) {
      case SupyDocumentPageQuality.veryPoor:
      case SupyDocumentPageQuality.poor:
        return widget.palette.negative;
      case SupyDocumentPageQuality.ok:
        return widget.palette.warning;
      case SupyDocumentPageQuality.good:
      case SupyDocumentPageQuality.excellent:
        return widget.palette.positive;
    }
  }

  // The config handed to the embedded view, with the live auto-capture toggle
  // overlaid on the caller's guidance.
  SupyDocumentGuidanceConfiguration get _effectiveGuidance =>
      widget.guidance.copyWith(autoCapture: _autoCapture);

  // A vertical shade of the brand primary so the solid bars read with visible
  // depth instead of a flat fill: a lighter highlight at the top grading to a
  // clearly darker edge at the bottom. Derived from the palette token (no
  // hard-coded hex). Kept strong enough that the Supy-purple shading reads on
  // device, not just in the simulator.
  LinearGradient get _barGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color.lerp(widget.palette.primary, Colors.white, 0.22)!,
      widget.palette.primary,
      Color.lerp(widget.palette.primary, Colors.black, 0.32)!,
    ],
    stops: const <double>[0, 0.5, 1],
  );

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? SupyDocumentScannerController();
  }

  @override
  void dispose() {
    _flash.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  // Live guidance drives the steadiness pill copy; only rebuild on state change
  // to avoid a setState per camera frame.
  void _onGuidance(SupyDocumentGuidanceFrame frame) {
    if (!mounted || frame.state == _frameState) return;
    setState(() => _frameState = frame.state);
  }

  // A capture landed: buzz + flash so the shutter always confirms it fired,
  // even in Multi mode where the page only accumulates in the corner thumb.
  void _signalCapture() {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_flash.reverse(from: 1));
  }

  // In-screen feedback for a capture / import outcome. Kept independent of
  // [widget.onError] (which the branded facade intentionally leaves null so a
  // transient failure never discards accepted pages) so the shutter is never
  // silent: a failed tap must tell the user something happened.
  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(color: widget.palette.onPrimary),
          ),
          backgroundColor:
              isError ? widget.palette.negative : widget.palette.positive,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // Auto-capture path (countdown-completed) surfaces here via the view.
  void _onCapture(SupyDocumentCapture capture) {
    if (!mounted) return;
    _signalCapture();
    setState(() {
      _pages.add(
        SupyDocumentPage(
          uri: Uri.file(capture.path).toString(),
          width: capture.widthPx,
          height: capture.heightPx,
          quality: capture.quality,
          qualityScore: capture.qualityScore,
        ),
      );
    });
    // Acknowledge the capture so the view can re-arm.
    _controller.clearCapturePhase();
    // Single / Receipt finish a page per shot and go straight to review; Multi
    // stays in the viewfinder and pauses only when the cap is hit.
    if (_mode.isSinglePage) {
      _goToReview();
    } else if (_reachedMax) {
      unawaited(_controller.pause());
    }
  }

  // Manual shutter fallback (e.g. when auto-capture is disabled).
  Future<void> _manualCapture() async {
    if (_busy || _reachedMax) return;
    _busy = true;
    try {
      SupyDocumentCapture capture;
      try {
        capture = await _controller.captureAndRectify();
      } on StateError catch (e) {
        if (e.message.startsWith('captureUnsupported') &&
            widget.guidance.allowUnrectifiedFallback) {
          capture = await _controller.captureFullFrame();
        } else {
          rethrow;
        }
      }
      _onCapture(capture);
    } on Object catch (e) {
      _showSnack(_strings.captureFailed, isError: true);
      widget.onError?.call(
        SupyScanError(
          code: SupyScanErrorCode.unknown,
          message: e.toString(),
          details: e,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  // Native gallery import: opens the platform photo picker, runs on-device
  // detect + rectify + enhance natively, and appends the returned page. A
  // dismissed picker resolves to null and is a no-op (matches iOS/Android).
  Future<void> _importFromGallery() async {
    if (_busy || _reachedMax) return;
    _busy = true;
    try {
      final page = await SupyScannerChannel.instance.importDocumentImage(
        // Gallery photos are already exposure/white-balance corrected by the
        // camera app, so the native default paper-flattening enhancement
        // (illumination + tone + unsharp) stacks on top and reads as harshly
        // over-contrasted next to a camera capture. Turning enhancement off
        // imports the picked image as a plain colour page (the default filter)
        // so it matches the in-app captures.
        const SupyDocumentScanOptions(enhanceMode: SupyDocumentEnhanceMode.off),
      );
      if (page == null || !mounted) return;
      setState(() => _pages.add(page));
      if (_mode.isSinglePage) {
        _goToReview();
      } else if (_reachedMax) {
        unawaited(_controller.pause());
      }
    } on SupyScanError catch (e) {
      _showSnack(_strings.captureFailed, isError: true);
      widget.onError?.call(e);
    } on Object catch (e) {
      _showSnack(_strings.captureFailed, isError: true);
      widget.onError?.call(
        SupyScanError(
          code: SupyScanErrorCode.unknown,
          message: e.toString(),
          details: e,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  void _deletePage(int index) {
    final wasAtMax = _reachedMax;
    setState(() => _pages.removeAt(index));
    if (wasAtMax && !_reachedMax) unawaited(_controller.resume());
    // Nothing left to review — fall back to the viewfinder to capture again.
    if (_pages.isEmpty) _goToViewfinder();
  }

  // Pauses the preview and shows the captured-page review grid.
  void _goToReview() {
    if (_pages.isEmpty) return;
    unawaited(_controller.pause());
    setState(() => _stage = _DocStage.review);
  }

  // Returns to the viewfinder to add another page (unless the cap is reached).
  void _goToViewfinder() {
    if (!_reachedMax) unawaited(_controller.resume());
    setState(() => _stage = _DocStage.viewfinder);
  }

  void _finish() {
    if (_pages.isEmpty) return;
    widget.onComplete(List<SupyDocumentPage>.unmodifiable(_pages));
  }

  Future<void> _toggleTorch() async {
    final next = !_torchOn;
    await _controller.setTorch(on: next);
    if (mounted) setState(() => _torchOn = next);
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings;
    return Directionality(
      textDirection: strings.textDirection,
      child: Scaffold(
        backgroundColor: widget.palette.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SupyDocumentScannerView(
              controller: _controller,
              guidance: _effectiveGuidance,
              palette: widget.palette,
              strings: strings,
              // The screen supplies its own solid-chrome status band, so the
              // view renders the live tracking overlay but not its hint card.
              showHintCard: false,
              onGuidance: _onGuidance,
              onCapture: _onCapture,
              onError: (e) => widget.onError?.call(e),
            ),
            if (_stage == _DocStage.viewfinder) _buildViewfinder(strings),
            if (_stage == _DocStage.review)
              Positioned.fill(
                child: ColoredBox(
                  color: widget.palette.surface,
                  child: SafeArea(child: _buildReview(strings)),
                ),
              ),
            // Capture flash: a brief white wash over everything on each shot.
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _flash,
                  child: ColoredBox(color: widget.palette.onPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Screen 1 — viewfinder
  // ---------------------------------------------------------------------------

  Widget _buildViewfinder(SupyScannerStrings strings) {
    return Column(
      children: [
        _buildBrandBar(strings),
        Expanded(
          child: Stack(
            children: [
              // Top hint, over the live camera preview.
              PositionedDirectional(
                top: 16,
                start: 24,
                end: 24,
                child: _InstructionBand(
                  text: strings.scanInstruction,
                  background: widget.palette.surfaceLow,
                  foreground: widget.palette.onSurface,
                ),
              ),
              // Live status, floating just above the capture bar.
              PositionedDirectional(
                bottom: 20,
                start: 24,
                end: 24,
                child: Center(child: _buildStatusBand(strings)),
              ),
            ],
          ),
        ),
        _buildCaptureBar(strings),
      ],
    );
  }

  Widget _buildBrandBar(SupyScannerStrings strings) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: BoxDecoration(gradient: _barGradient),
      padding: EdgeInsets.only(top: topInset),
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Center(
              child: Text(
                strings.scanDocumentTitle,
                style: TextStyle(
                  color: widget.palette.onPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            PositionedDirectional(
              start: 4,
              top: 0,
              bottom: 0,
              child: TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: widget.palette.onPrimary,
                ),
                child: Text(strings.cancel),
              ),
            ),
            PositionedDirectional(
              end: 4,
              top: 0,
              bottom: 0,
              child: IconButton(
                onPressed: () => _showHelp(strings),
                icon: const Icon(Icons.help_outline),
                color: widget.palette.onPrimary,
                tooltip: strings.help,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Live status pill: green when ready to capture, amber while centering /
  // holding, red for every blocking problem (matches the Scanbot band).
  Widget _buildStatusBand(SupyScannerStrings strings) {
    final state = _frameState;
    final text =
        state == null
            ? strings.holdSteady
            : strings.documentHints.textFor(state);
    Color color;
    IconData icon;
    switch (state) {
      case SupyDocumentFrameState.ready:
      case SupyDocumentFrameState.capturing:
      case SupyDocumentFrameState.captured:
        color = widget.palette.positive;
        icon = Icons.check_circle;
      case SupyDocumentFrameState.holdSteady:
      case SupyDocumentFrameState.offCenter:
      case null:
        color = widget.palette.warning;
        icon = Icons.center_focus_strong;
      default:
        color = widget.palette.negative;
        icon = Icons.error_outline;
    }
    return _StatusBand(
      text: text,
      icon: icon,
      background: color,
      foreground: widget.palette.onPrimary,
    );
  }

  Widget _buildCaptureBar(SupyScannerStrings strings) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(gradient: _barGradient),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Row(
        children: [
          // Left cluster: gallery import + auto-capture toggle.
          Expanded(
            child: Row(
              children: [
                IconButton(
                  onPressed: _reachedMax ? null : _importFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  color: widget.palette.onPrimary,
                  disabledColor: widget.palette.onSurfaceVariant,
                  tooltip: strings.importFromGallery,
                ),
                const SizedBox(width: 4),
                _AutoCaptureToggle(
                  active: _autoCapture,
                  label: strings.autoCapture,
                  activeBackground: widget.palette.onPrimary,
                  activeForeground: widget.palette.primary,
                  inactiveForeground: widget.palette.onSurfaceVariant,
                  onTap: _toggleAutoCapture,
                ),
              ],
            ),
          ),
          _ShutterButton(
            color: widget.palette.onPrimary,
            enabled: !_reachedMax,
            onTap: _manualCapture,
            label: strings.capturePage,
          ),
          // Right cluster: torch + captured-page stack.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _toggleTorch,
                  icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                  color:
                      _torchOn
                          ? widget.palette.onPrimary
                          : widget.palette.onSurfaceVariant,
                  tooltip: strings.flash,
                ),
                const SizedBox(width: 4),
                _PageStackThumb(
                  pages: _pages,
                  borderColor: widget.palette.onPrimary,
                  badgeBackground: widget.palette.onPrimary,
                  badgeForeground: widget.palette.primary,
                  onTap: _pages.isEmpty ? null : _goToReview,
                  label: strings.pagesCountLabel(_pages.length),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleAutoCapture() {
    setState(() => _autoCapture = !_autoCapture);
  }

  // Scanning-tips bottom sheet, opened from the brand bar help affordance.
  void _showHelp(SupyScannerStrings strings) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: widget.palette.surfaceHigh,
        showDragHandle: true,
        builder:
            (context) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.helpTitle,
                      style: TextStyle(
                        color: widget.palette.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.helpBody,
                      style: TextStyle(
                        color: widget.palette.onSurfaceVariant,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Screen 2 — page review
  // ---------------------------------------------------------------------------

  Widget _buildReview(SupyScannerStrings strings) {
    return Column(
      children: [
        _buildReviewBar(strings),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.72,
            ),
            itemCount: _pages.length + (_reachedMax ? 0 : 1),
            itemBuilder: (context, index) {
              if (index == _pages.length) {
                return _AddPageTile(
                  color: widget.palette.outline,
                  iconColor: widget.palette.onSurfaceVariant,
                  label: strings.addPage,
                  onTap: _goToViewfinder,
                );
              }
              final quality = _pages[index].quality;
              return _ReviewTile(
                page: _pages[index],
                index: index,
                borderColor: widget.palette.outline,
                cardColor: widget.palette.surfaceHigh,
                labelColor: widget.palette.onSurface,
                badgeColor: widget.palette.surfaceLow,
                badgeIconColor: widget.palette.onSurface,
                pageLabel: strings.documentPageLabel(index + 1),
                deleteLabel: strings.deletePageLabel(index + 1),
                onDelete: () => _deletePage(index),
                qualityLabel:
                    quality == null
                        ? null
                        : strings.documentQualityLabel(quality),
                qualityColor: quality == null ? null : _qualityColor(quality),
                qualityScrimColor: widget.palette.surface,
              );
            },
          ),
        ),
        _buildExportBar(strings),
      ],
    );
  }

  Widget _buildReviewBar(SupyScannerStrings strings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _goToViewfinder,
            icon: const Icon(Icons.chevron_left),
            label: Text(strings.back),
            style: TextButton.styleFrom(
              foregroundColor: widget.palette.onSurface,
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                strings.pagesCountLabel(_pages.length),
                style: TextStyle(
                  color: widget.palette.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: _pages.isEmpty ? null : _finish,
            style: TextButton.styleFrom(
              foregroundColor: _accent,
              disabledForegroundColor: widget.palette.onSurfaceVariant,
            ),
            child: Text(strings.exportAction),
          ),
        ],
      ),
    );
  }

  Widget _buildExportBar(SupyScannerStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _pages.isEmpty ? null : _finish,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: widget.palette.onPrimary,
            disabledBackgroundColor: widget.palette.primaryDisabled,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text(strings.exportAsPdf),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Viewfinder building blocks
// ---------------------------------------------------------------------------

class _InstructionBand extends StatelessWidget {
  const _InstructionBand({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _StatusBand extends StatelessWidget {
  const _StatusBand({
    required this.text,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String text;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoCaptureToggle extends StatelessWidget {
  const _AutoCaptureToggle({
    required this.active,
    required this.label,
    required this.activeBackground,
    required this.activeForeground,
    required this.inactiveForeground,
    required this.onTap,
  });

  final bool active;
  final String label;
  final Color activeBackground;
  final Color activeForeground;
  final Color inactiveForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? activeForeground : inactiveForeground;
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? activeBackground : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: foreground),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.bolt : Icons.bolt_outlined,
                size: 16,
                color: foreground,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageStackThumb extends StatelessWidget {
  const _PageStackThumb({
    required this.pages,
    required this.borderColor,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.onTap,
    required this.label,
  });

  final List<SupyDocumentPage> pages;
  final Color borderColor;
  final Color badgeBackground;
  final Color badgeForeground;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) return const SizedBox(width: 44, height: 44);
    final last = pages.last;
    final file = File(Uri.parse(last.uri).toFilePath());
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 2),
                image:
                    file.existsSync()
                        ? DecorationImage(
                          image: FileImage(file),
                          fit: BoxFit.cover,
                        )
                        : null,
              ),
            ),
            PositionedDirectional(
              top: -6,
              end: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeBackground,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${pages.length}',
                  style: TextStyle(
                    color: badgeForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.color,
    required this.enabled,
    required this.onTap,
    required this.label,
  });

  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 4),
            ),
            child: Center(
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review building blocks
// ---------------------------------------------------------------------------

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.page,
    required this.index,
    required this.borderColor,
    required this.cardColor,
    required this.labelColor,
    required this.badgeColor,
    required this.badgeIconColor,
    required this.pageLabel,
    required this.deleteLabel,
    required this.onDelete,
    required this.qualityScrimColor,
    this.qualityLabel,
    this.qualityColor,
  });

  final SupyDocumentPage page;
  final int index;
  final Color borderColor;
  final Color cardColor;
  final Color labelColor;
  final Color badgeColor;
  final Color badgeIconColor;
  final String pageLabel;
  final String deleteLabel;
  final VoidCallback onDelete;

  /// Localized quality-bucket label for the informational quality badge. Null
  /// when the native scorer returned no bucket for this page (badge hidden).
  final String? qualityLabel;

  /// Palette severity color (positive/warning/negative) for the badge dot and
  /// text. Null alongside [qualityLabel] hides the badge.
  final Color? qualityColor;

  /// Scrim behind the quality badge so it stays legible over any thumbnail.
  final Color qualityScrimColor;

  @override
  Widget build(BuildContext context) {
    final file = File(Uri.parse(page.uri).toFilePath());
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          image: true,
          label: pageLabel,
          excludeSemantics: true,
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
              image:
                  file.existsSync()
                      ? DecorationImage(
                        image: FileImage(file),
                        fit: BoxFit.cover,
                      )
                      : null,
            ),
            alignment: AlignmentDirectional.bottomStart,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: labelColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  shadows: const [Shadow(blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),
        if (qualityLabel != null && qualityColor != null)
          PositionedDirectional(
            bottom: 8,
            end: 8,
            child: Semantics(
              label: qualityLabel,
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: qualityScrimColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: qualityColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      qualityLabel!,
                      style: TextStyle(
                        color: qualityColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        PositionedDirectional(
          top: -8,
          end: -8,
          child: Semantics(
            button: true,
            label: deleteLabel,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onDelete,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: badgeColor,
                child: Icon(Icons.close, size: 16, color: badgeIconColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddPageTile extends StatelessWidget {
  const _AddPageTile({
    required this.color,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(color: color, radius: 10),
          child: Center(child: Icon(Icons.add, color: iconColor, size: 32)),
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rectangle border for the "add page" tile.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
