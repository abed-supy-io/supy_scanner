import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../../branding/supy_brand.dart';

/// Live smart-guidance document scanner demo.
///
/// Mounts the embedded [SupyDocumentScannerView] so the guidance overlay,
/// per-frame hints, and auto-snap countdown are visible on a device — the iOS
/// equivalent of the Android CameraX auto-snap experience. The guidance state
/// machine ([SupyDocumentStateMachine]) drives the overlay; this screen wraps
/// it in friendly onboarding, a live status chip, and a capture-review card,
/// plus an opt-in metrics HUD for watching the state transitions.
class SmartDocumentDemo extends StatefulWidget {
  const SmartDocumentDemo({super.key});

  @override
  State<SmartDocumentDemo> createState() => _SmartDocumentDemoState();
}

class _SmartDocumentDemoState extends State<SmartDocumentDemo> {
  final SupyDocumentScannerController _controller =
      SupyDocumentScannerController();

  SupyDocumentGuidanceFrame? _frame;
  String? _capturedPath;
  String? _error;
  bool _torchOn = false;
  bool _autoCapture = true;
  // Friendly first-run coaching card. Stays up until the user taps "Got it" or
  // the first page is captured, then never nags again this session.
  bool _showHelp = true;
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
      setState(() {
        _capturedPath = capture.path;
        _showHelp = false;
      });
    } on StateError catch (e) {
      // Falls back to a full-frame still when no quad is locked in yet.
      try {
        final capture = await _controller.captureFullFrame();
        if (!mounted) return;
        setState(() {
          _capturedPath = capture.path;
          _showHelp = false;
        });
      } on StateError {
        if (!mounted) return;
        setState(() => _error = e.message);
      }
    }
  }

  void _retake() {
    setState(() {
      _capturedPath = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reviewing = _capturedPath != null;
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Smart Document'),
          actions: [
            IconButton(
              tooltip:
                  _autoCapture
                      ? 'Auto-snap on — tap to require manual capture'
                      : 'Auto-snap off — tap to snap automatically',
              icon: Icon(_autoCapture ? Icons.bolt : Icons.bolt_outlined),
              onPressed: () => setState(() => _autoCapture = !_autoCapture),
            ),
            IconButton(
              tooltip: _torchOn ? 'Torch on' : 'Torch off',
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: _toggleTorch,
            ),
            IconButton(
              tooltip: _showHud ? 'Hide metrics HUD' : 'Show metrics HUD',
              icon: Icon(
                _showHud ? Icons.bug_report : Icons.bug_report_outlined,
              ),
              onPressed: () => setState(() => _showHud = !_showHud),
            ),
          ],
        ),
        // Hide the manual-capture button while reviewing a shot — the review
        // card owns the actions then.
        floatingActionButton:
            reviewing
                ? null
                : FloatingActionButton.extended(
                  backgroundColor: SupyBrand.navy,
                  onPressed: _manualCapture,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_autoCapture ? 'Capture now' : 'Capture'),
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

            // Friendly first-run coaching, dismissed once the user gets going.
            if (_showHelp && !reviewing)
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: _HelpCard(
                  autoCapture: _autoCapture,
                  onDismiss: () => setState(() => _showHelp = false),
                ),
              ),

            // Live one-line status so the user always knows what the scanner is
            // waiting on, mirroring the in-view coaching pill in plain words.
            if (!reviewing && !_showHelp)
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: _StatusChip(frame: _frame, autoCapture: _autoCapture),
              ),

            if (reviewing)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _CaptureReview(
                  path: _capturedPath!,
                  onRetake: _retake,
                  onDone: () {
                    _retake();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Page saved')));
                  },
                ),
              ),

            if (_error != null && !reviewing)
              Positioned(
                left: 20,
                right: 20,
                bottom: 96,
                child: _ErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Friendly first-run explainer: what the scanner does and how to help it.
class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.autoCapture, required this.onDismiss});

  final bool autoCapture;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: SupyBrand.accent,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Scan a document',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: SupyBrand.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 20),
                  color: SupyBrand.onSurfaceMuted,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const _HelpStep(
              icon: Icons.fit_screen,
              text: 'Fill the frame with your page on a flat surface.',
            ),
            const _HelpStep(
              icon: Icons.wb_sunny_outlined,
              text: 'Find even light — avoid glare and shadows.',
            ),
            _HelpStep(
              icon: autoCapture ? Icons.bolt : Icons.camera_alt,
              text:
                  autoCapture
                      ? 'Hold steady when the frame turns green — it snaps for you.'
                      : 'Tap Capture when the frame turns green.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDismiss,
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: SupyBrand.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.3,
                color: SupyBrand.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact live status line — plain-language echo of the guidance state so the
/// user always has a clear next action even before the frame locks.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.frame, required this.autoCapture});

  final SupyDocumentGuidanceFrame? frame;
  final bool autoCapture;

  @override
  Widget build(BuildContext context) {
    final f = frame;
    final ready = f?.isReady ?? false;
    final (label, icon) = _describe(f, autoCapture);
    final color =
        ready ? SupyBrand.success : Colors.black.withValues(alpha: 0.55);
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, IconData) _describe(SupyDocumentGuidanceFrame? f, bool autoCapture) {
    if (f == null) {
      return ('Point at a document', Icons.document_scanner_outlined);
    }
    switch (f.state) {
      case SupyDocumentFrameState.noDocument:
        return ('Point at a document', Icons.document_scanner_outlined);
      case SupyDocumentFrameState.tooDark:
        return ('More light needed', Icons.lightbulb_outline);
      case SupyDocumentFrameState.tooClose:
        return ('Move back a little', Icons.zoom_out_map);
      case SupyDocumentFrameState.tooFar:
        return ('Move closer', Icons.zoom_in_map);
      case SupyDocumentFrameState.tooSkewed:
        return ('Straighten the page', Icons.crop_rotate);
      case SupyDocumentFrameState.blurry:
        return ('Hold still to focus', Icons.center_focus_weak);
      case SupyDocumentFrameState.glare:
        return ('Tilt away from glare', Icons.flare);
      case SupyDocumentFrameState.occluded:
        return ('Clear the edges', Icons.pan_tool_outlined);
      case SupyDocumentFrameState.handShake:
        return ('Steady your hands', Icons.vibration);
      case SupyDocumentFrameState.edgeClipped:
        return ('Fit the whole page', Icons.crop_free);
      case SupyDocumentFrameState.offCenter:
        return ('Center the document', Icons.center_focus_strong);
      case SupyDocumentFrameState.holdSteady:
        return ('Almost there — hold steady', Icons.hourglass_top);
      case SupyDocumentFrameState.ready:
        return (
          autoCapture
              ? 'Looks great — capturing…'
              : 'Looks great — tap Capture',
          Icons.check_circle_outline,
        );
      case SupyDocumentFrameState.capturing:
        return ('Capturing…', Icons.camera_alt_outlined);
      case SupyDocumentFrameState.captured:
        return ('Captured', Icons.check_circle);
    }
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
      bottom: 16,
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

/// Post-capture review card: confirms the shot and offers Retake / Done so the
/// capture isn't a mystery thumbnail the user has to guess how to dismiss.
class _CaptureReview extends StatelessWidget {
  const _CaptureReview({
    required this.path,
    required this.onRetake,
    required this.onDone,
  });

  final String path;
  final VoidCallback onRetake;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(path),
                width: 84,
                height: 112,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: const [
                      Icon(
                        Icons.check_circle,
                        color: SupyBrand.success,
                        size: 20,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Page captured',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: SupyBrand.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Check the crop and lighting. Retake if it needs another go.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: SupyBrand.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onRetake,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retake'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onDone,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SupyBrand.critical,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
