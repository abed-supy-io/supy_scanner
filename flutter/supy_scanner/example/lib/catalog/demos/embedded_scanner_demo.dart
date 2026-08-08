import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// The embeddable live scanner widget: drop `SupyBarcodeScannerView` into any
/// layout, drive it with a `SupyBarcodeScannerController` (torch here), and
/// receive detections through the `onBarcodeDetected` callback.
class EmbeddedScannerDemo extends StatefulWidget {
  const EmbeddedScannerDemo({super.key});

  @override
  State<EmbeddedScannerDemo> createState() => _EmbeddedScannerDemoState();
}

class _EmbeddedScannerDemoState extends State<EmbeddedScannerDemo> {
  final SupyBarcodeScannerController _controller =
      SupyBarcodeScannerController();
  SupyBarcode? _last;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Embedded scanner view',
      description:
          'The building block behind every barcode surface: a camera preview '
          'you embed directly in your own layout. Detections stream through '
          'onBarcodeDetected; the controller exposes torch, zoom and lifecycle. '
          'Point at any code — the latest hit shows at the bottom.',
      apiSummary:
          'SupyBarcodeScannerView(controller: SupyBarcodeScannerController(), '
          'onBarcodeDetected: (SupyBarcode) {})  ·  controller.setTorch(on:)',
      fullBleed: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SupyBarcodeScannerView(
            controller: _controller,
            onBarcodeDetected: (b) => setState(() => _last = b),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'embedded-torch',
              onPressed: () async {
                await _controller.setTorch(on: !_torchOn);
                setState(() => _torchOn = !_torchOn);
              },
              child: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            ),
          ),
          if (_last != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Card(
                color: Colors.black.withValues(alpha: 0.78),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${_last!.format.wireName}\n${_last!.rawValue}',
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
