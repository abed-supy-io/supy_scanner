import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../../branding/supy_brand.dart';

/// Live capture stage for the Option B invoice flow.
///
/// Mounts the embedded [SupyDocumentScannerView] with the invoice guidance
/// preset and lets the user snap one or more pages. Unlike the raw Scanbot
/// flow (camera stays open with no finish button), this screen owns an
/// explicit page counter and a **Done** button — the user decides when the
/// invoice is complete, then lands on the branded confirm screen.
///
/// Pops with the `List<SupyDocumentPage>` captured this session. In
/// [singlePage] mode it pops after the first capture — used by the page editor
/// to re-scan / re-crop a single page.
class InvoiceCaptureScreen extends StatefulWidget {
  const InvoiceCaptureScreen({super.key, this.singlePage = false});

  /// When `true`, the screen returns after a single capture (re-scan one page).
  final bool singlePage;

  @override
  State<InvoiceCaptureScreen> createState() => _InvoiceCaptureScreenState();
}

class _InvoiceCaptureScreenState extends State<InvoiceCaptureScreen> {
  final SupyDocumentScannerController _controller =
      SupyDocumentScannerController();

  final List<SupyDocumentPage> _pages = <SupyDocumentPage>[];
  SupyDocumentGuidanceFrame? _frame;
  String? _error;
  bool _torchOn = false;
  bool _capturing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    await _controller.setTorch(on: !_torchOn);
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      // `capture()` rectifies against the locked quad and returns the persisted,
      // scored page. Fall back to a full-frame still when no quad is locked yet
      // so the user always gets a picture.
      SupyDocumentPage? page;
      try {
        page = await _controller.capture();
      } on Object {
        final still = await _controller.captureFullFrame();
        page = SupyDocumentPage(
          uri: Uri.file(still.path).toString(),
          width: still.widthPx,
          height: still.heightPx,
        );
      }
      _controller.clearCapturePhase();
      if (page == null || !mounted) return;
      _pages.add(page);
      if (widget.singlePage) {
        Navigator.of(context).pop(List<SupyDocumentPage>.unmodifiable(_pages));
        return;
      }
      setState(() {});
    } on Object catch (e) {
      _controller.clearCapturePhase();
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _done() {
    Navigator.of(context).pop(List<SupyDocumentPage>.unmodifiable(_pages));
  }

  @override
  Widget build(BuildContext context) {
    final ready = _frame?.isReady ?? false;
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.singlePage ? 'Re-scan page' : 'Capture invoice'),
          actions: [
            IconButton(
              tooltip: 'Toggle torch',
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: _toggleTorch,
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // `autoCapture: false` — this screen drives capture itself via
            // `controller.capture()` so it can collect the returned page; the
            // view's built-in auto-snap discards its result.
            SupyDocumentScannerView(
              controller: _controller,
              guidance: const SupyDocumentGuidanceConfiguration(
                maxCoverageRatio: 0.85,
                interiorVarianceFloor: 8.0,
                edgeClipBlocking: true,
                readyStableFrames: 6,
                holdSteadyFrames: 7,
                autoCapture: false,
              ),
              onGuidance: (f) => setState(() => _frame = f),
              onError: (e) => setState(() => _error = e.message),
            ),
            if (_error != null)
              Positioned(
                left: 20,
                right: 20,
                top: 16,
                child: _Banner(message: _error!),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CaptureBar(
                pageCount: _pages.length,
                ready: ready,
                capturing: _capturing,
                singlePage: widget.singlePage,
                onCapture: _capture,
                onDone: _done,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureBar extends StatelessWidget {
  const _CaptureBar({
    required this.pageCount,
    required this.ready,
    required this.capturing,
    required this.singlePage,
    required this.onCapture,
    required this.onDone,
  });

  final int pageCount;
  final bool ready;
  final bool capturing;
  final bool singlePage;
  final VoidCallback onCapture;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final shutterColor = ready ? SupyBrand.success : SupyBrand.accent;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Row(
        children: [
          // Page-count badge.
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SupyBrand.navy,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$pageCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1.0,
                  ),
                ),
                const Text(
                  'pages',
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Shutter.
          GestureDetector(
            onTap: capturing ? null : onCapture,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: capturing ? Colors.white24 : shutterColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: capturing
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt, color: Colors.white),
            ),
          ),
          const Spacer(),
          // Done — the finish button the raw SDK flow is missing.
          SizedBox(
            width: 56,
            child: singlePage
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: pageCount > 0 ? onDone : null,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SupyBrand.critical,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}
