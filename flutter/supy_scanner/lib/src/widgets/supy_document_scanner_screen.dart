import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../channel/supy_scanner_channel.dart';
import '../models/supy_document_page.dart';
import '../models/supy_scan_error.dart';
import '../models/ui/supy_document_guidance_configuration.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import 'supy_document_scanner_controller.dart';
import 'supy_document_scanner_view.dart';

/// Full-screen, Supy-branded multi-page document session.
///
/// This is the Flutter-drawn parity surface for the native document scanner
/// (`VNDocumentCameraViewController` / GMS `GmsDocumentScanning`). It composes
/// the embedded [SupyDocumentScannerView] preview with a top bar
/// (cancel + torch), a horizontal page tray (thumbnail, delete, drag-reorder),
/// and a manual shutter + `Done` action.
///
/// Captures accumulate as [SupyDocumentPage]s (each a rectified still persisted
/// on disk); [onComplete] fires with the ordered pages when the user taps
/// `Done`. Result routing mirrors [SupyBarcodeScannerScreen]'s callback style —
/// the screen never pops itself; the host wires [onComplete] / [onCancel] to
/// `Navigator.pop`.
@immutable
class SupyDocumentScannerScreen extends StatefulWidget {
  /// Creates a branded multi-page document session screen.
  const SupyDocumentScannerScreen({
    required this.onComplete,
    super.key,
    this.onCancel,
    this.onError,
    this.guidance = const SupyDocumentGuidanceConfiguration(autoCapture: false),
    this.palette = const SupyScannerPalette.supyDark(),
    this.accentColor,
    this.maxPages = 0,
    this.locale = 'en',
    this.controller,
  });

  /// Called when the user finishes the session. Receives the ordered pages
  /// (always non-empty; `Done` is disabled until at least one page exists).
  final ValueChanged<List<SupyDocumentPage>> onComplete;

  /// Called when the user cancels without keeping any pages.
  final VoidCallback? onCancel;

  /// Called when the embedded view reports a capture / preview error.
  final ValueChanged<SupyScanError>? onError;

  /// Guidance thresholds + copy driving the embedded preview overlay.
  ///
  /// Auto-capture is **off by default** in this branded session (manual
  /// shutter). Pass a config with `autoCapture: true` to re-enable the
  /// countdown-and-shoot behaviour.
  final SupyDocumentGuidanceConfiguration guidance;

  /// Palette tokens for the chrome (top bar, tray, buttons).
  final SupyScannerPalette palette;

  /// Optional brand accent for the primary actions (Done, page-count chip,
  /// shutter ring). Defaults to [SupyScannerPalette.primary].
  final Color? accentColor;

  /// Maximum pages to capture. `0` means unlimited (matches Scanbot's
  /// `pagesScanLimit = 0`). On reaching the cap the preview pauses until a
  /// page is deleted.
  final int maxPages;

  /// Locale for the in-screen copy (`'ar'` for Arabic, `'en'` otherwise).
  final String locale;

  /// Optional externally-owned controller. When omitted, the screen creates
  /// and disposes its own.
  final SupyDocumentScannerController? controller;

  @override
  State<SupyDocumentScannerScreen> createState() =>
      _SupyDocumentScannerScreenState();
}

class _SupyDocumentScannerScreenState extends State<SupyDocumentScannerScreen> {
  late final SupyDocumentScannerController _controller;
  late final bool _ownsController;

  final List<SupyDocumentPage> _pages = <SupyDocumentPage>[];
  bool _torchOn = false;
  bool _busy = false;

  SupyScannerStrings get _strings => SupyScannerStrings.of(widget.locale);
  bool get _reachedMax =>
      widget.maxPages > 0 && _pages.length >= widget.maxPages;
  Color get _accent => widget.accentColor ?? widget.palette.primary;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? SupyDocumentScannerController();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  // Auto-capture path (countdown-completed) surfaces here via the view.
  void _onCapture(SupyDocumentCapture capture) {
    if (!mounted) return;
    setState(() {
      _pages.add(
        SupyDocumentPage(
          uri: Uri.file(capture.path).toString(),
          width: capture.widthPx,
          height: capture.heightPx,
        ),
      );
    });
    // Acknowledge the capture so the view can re-arm, then stop at the cap.
    _controller.clearCapturePhase();
    if (_reachedMax) unawaited(_controller.pause());
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
      final page = await SupyScannerChannel.instance.importDocumentImage();
      if (page == null || !mounted) return;
      setState(() => _pages.add(page));
      if (_reachedMax) unawaited(_controller.pause());
    } on SupyScanError catch (e) {
      widget.onError?.call(e);
    } on Object catch (e) {
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
  }

  // [toIndex] is already adjusted for the item removed at [fromIndex].
  void _reorder(int fromIndex, int toIndex) {
    setState(() {
      final page = _pages.removeAt(fromIndex);
      _pages.insert(toIndex, page);
    });
  }

  void _finish() {
    if (_pages.isEmpty) return;
    widget.onComplete(List<SupyDocumentPage>.unmodifiable(_pages));
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
              guidance: widget.guidance,
              palette: widget.palette,
              strings: strings,
              onCapture: _onCapture,
              onError: (e) => widget.onError?.call(e),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(strings),
                  const Spacer(),
                  _buildBottomBar(strings),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(SupyScannerStrings strings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close),
            color: widget.palette.onSurface,
            tooltip: strings.cancel,
          ),
          const Spacer(),
          if (_pages.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.maxPages > 0
                    ? '${_pages.length}/${widget.maxPages}'
                    : '${_pages.length}',
                style: TextStyle(
                  color: widget.palette.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            onPressed: _toggleTorch,
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            color: widget.palette.onSurface,
            tooltip: strings.flash,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTorch() async {
    final next = !_torchOn;
    await _controller.setTorch(on: next);
    if (mounted) setState(() => _torchOn = next);
  }

  Widget _buildBottomBar(SupyScannerStrings strings) {
    return DecoratedBox(
      decoration: BoxDecoration(color: widget.palette.modalOverlay),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pages.isNotEmpty) ...[
              _buildPageTray(),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    _reachedMax
                        ? strings.maxPagesReached
                        : strings.aimAtDocument,
                    style: TextStyle(color: widget.palette.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  onPressed: _reachedMax ? null : _importFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  color: widget.palette.onSurface,
                  disabledColor: widget.palette.onSurfaceVariant,
                  tooltip: strings.importFromGallery,
                ),
                const SizedBox(width: 8),
                _ShutterButton(
                  color: _accent,
                  enabled: !_reachedMax,
                  onTap: _manualCapture,
                  label: strings.capturePage,
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _pages.isEmpty ? null : _finish,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: widget.palette.onPrimary,
                    disabledBackgroundColor: widget.palette.primaryDisabled,
                  ),
                  child: Text(strings.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageTray() {
    return SizedBox(
      height: 88,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        onReorderItem: _reorder,
        itemCount: _pages.length,
        itemBuilder: (context, index) {
          final page = _pages[index];
          return ReorderableDragStartListener(
            key: ValueKey<String>(page.uri),
            index: index,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _PageThumbnail(
                page: page,
                index: index,
                onDelete: () => _deletePage(index),
                pageLabel: _strings.documentPageLabel(index + 1),
                deleteLabel: _strings.deletePageLabel(index + 1),
                borderColor: widget.palette.outline,
                labelColor: widget.palette.onSurface,
                badgeColor: widget.palette.surfaceLow,
                badgeIconColor: widget.palette.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  const _PageThumbnail({
    required this.page,
    required this.index,
    required this.onDelete,
    required this.pageLabel,
    required this.deleteLabel,
    required this.borderColor,
    required this.labelColor,
    required this.badgeColor,
    required this.badgeIconColor,
  });

  final SupyDocumentPage page;
  final int index;
  final VoidCallback onDelete;
  final String pageLabel;
  final String deleteLabel;
  final Color borderColor;
  final Color labelColor;
  final Color badgeColor;
  final Color badgeIconColor;

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
            width: 64,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
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
              padding: const EdgeInsets.all(4),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: const [Shadow(blurRadius: 2)],
                ),
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
                radius: 11,
                backgroundColor: badgeColor,
                child: Icon(Icons.close, size: 14, color: badgeIconColor),
              ),
            ),
          ),
        ),
      ],
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
