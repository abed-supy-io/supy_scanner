import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Live camera with AR-style bounding boxes painted over each detected
/// barcode via `SupyArOverlay` stacked on `SupyBarcodeScannerView`.
class ArOverlayDemo extends StatefulWidget {
  const ArOverlayDemo({super.key});

  @override
  State<ArOverlayDemo> createState() => _ArOverlayDemoState();
}

class _ArOverlayDemoState extends State<ArOverlayDemo> {
  final SupyBarcodeScannerController _controller =
      SupyBarcodeScannerController();
  final List<SupyBarcode> _barcodes = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetected(SupyBarcode barcode) {
    if (!mounted) return;
    // Keep only the most recent detection so the box tracks the live frame.
    setState(() {
      _barcodes
        ..clear()
        ..add(barcode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'AR overlay',
      description:
          'Highlight barcodes in place: SupyArOverlay paints a bounding box '
          '(and optional label) over the live preview for every detection, '
          'using the barcode\'s normalized boundingBox. Point at any code.',
      apiSummary:
          'Stack([ SupyBarcodeScannerView(onBarcodeDetected: …), '
          'Positioned.fill(SupyArOverlay(barcodes: …)) ])',
      fullBleed: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SupyBarcodeScannerView(
            controller: _controller,
            onBarcodeDetected: _onDetected,
          ),
          Positioned.fill(child: SupyArOverlay(barcodes: _barcodes)),
          if (_barcodes.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Card(
                color: Colors.black.withValues(alpha: 0.78),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${_barcodes.last.format.wireName}\n'
                    '${_barcodes.last.rawValue}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
