import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../branding/supy_brand.dart';

/// Live smart-guidance document scanner demo.
///
/// Mounts the embedded [SupyDocumentScannerView] so the guidance overlay,
/// per-frame hints, and auto-snap countdown are visible on a device — the iOS
/// equivalent of the Android CameraX auto-snap experience. The guidance state
/// machine ([SupyDocumentStateMachine]) drives the overlay; this screen adds a
/// live HUD so you can watch the state transitions and the metrics behind them.
class SupyDemoSmartDocumentPage extends StatefulWidget {
  const SupyDemoSmartDocumentPage({super.key});

  @override
  State<SupyDemoSmartDocumentPage> createState() =>
      _SupyDemoSmartDocumentPageState();
}

class _SupyDemoSmartDocumentPageState extends State<SupyDemoSmartDocumentPage> {
  final SupyDocumentScannerController _controller =
      SupyDocumentScannerController();

  SupyDocumentGuidanceFrame? _frame;
  String? _capturedPath;
  String? _error;
  bool _torchOn = false;
  bool _autoCapture = true;
  // The in-view coaching card is the primary UX now; the metrics HUD is an
  // opt-in debugging aid, hidden by default.
  bool _showHud = false;

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

  Future<void> _manualCapture() async {
    setState(() => _error = null);
    try {
      final capture = await _controller.captureAndRectify();
      if (!mounted) return;
      setState(() => _capturedPath = capture.path);
    } on StateError catch (e) {
      // Falls back to a full-frame still when no quad is locked in yet.
      try {
        final capture = await _controller.captureFullFrame();
        if (!mounted) return;
        setState(() => _capturedPath = capture.path);
      } on StateError {
        if (!mounted) return;
        setState(() => _error = e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Smart Document'),
          actions: [
            IconButton(
              tooltip: _autoCapture ? 'Auto-snap on' : 'Auto-snap off',
              icon: Icon(_autoCapture ? Icons.bolt : Icons.bolt_outlined),
              onPressed: () => setState(() => _autoCapture = !_autoCapture),
            ),
            IconButton(
              tooltip: 'Toggle torch',
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: _toggleTorch,
            ),
            IconButton(
              tooltip: _showHud ? 'Hide metrics HUD' : 'Show metrics HUD',
              icon: Icon(_showHud ? Icons.bug_report : Icons.bug_report_outlined),
              onPressed: () => setState(() => _showHud = !_showHud),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: SupyBrand.navy,
          onPressed: _manualCapture,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Capture'),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // `autoCapture` is keyed so toggling it rebuilds the view with the
            // new guidance configuration.
            SupyDocumentScannerView(
              key: ValueKey<bool>(_autoCapture),
              controller: _controller,
              guidance: SupyDocumentGuidanceConfiguration(
                autoCapture: _autoCapture,
              ),
              onGuidance: (f) => setState(() => _frame = f),
              onError: (e) => setState(() => _error = e.message),
            ),
            if (_showHud) _GuidanceHud(frame: _frame),
            if (_capturedPath != null)
              _CaptureThumb(
                path: _capturedPath!,
                onClose: () => setState(() => _capturedPath = null),
              ),
            if (_error != null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 96,
                child: _ErrorBanner(message: _error!),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom HUD showing the live FSM state + the metrics driving it.
class _GuidanceHud extends StatelessWidget {
  const _GuidanceHud({required this.frame});

  final SupyDocumentGuidanceFrame? frame;

  @override
  Widget build(BuildContext context) {
    final f = frame;
    if (f == null) return const SizedBox.shrink();
    final ready = f.isReady;
    return Positioned(
      left: 16,
      right: 16,
      top: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: ready ? SupyBrand.success : SupyBrand.critical,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  f.state.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '×${f.framesAtState}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'cover ${f.metrics.coverageRatio.toStringAsFixed(2)}  '
              'tilt ${f.metrics.tiltDegrees.toStringAsFixed(0)}°  '
              'luma ${f.metrics.meanLuma.toStringAsFixed(0)}  '
              'blur ${f.metrics.blurScore.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            Text(
              'glare ${f.metrics.glareRatio.toStringAsFixed(2)}  '
              'vel ${f.metrics.cornerVelocity.toStringAsFixed(3)}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating thumbnail of the most recent capture.
class _CaptureThumb extends StatelessWidget {
  const _CaptureThumb({required this.path, required this.onClose});

  final String path;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 96,
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: SupyBrand.success, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.file(
            File(path),
            width: 96,
            height: 128,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

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
