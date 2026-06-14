import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../branding/supy_brand.dart';

class SupyDemoEmbeddedBarcodePage extends StatefulWidget {
  const SupyDemoEmbeddedBarcodePage({super.key});

  @override
  State<SupyDemoEmbeddedBarcodePage> createState() =>
      _SupyDemoEmbeddedBarcodePageState();
}

class _SupyDemoEmbeddedBarcodePageState
    extends State<SupyDemoEmbeddedBarcodePage> {
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
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Live Camera'),
          actions: [
            IconButton(
              tooltip: 'Toggle torch',
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: () async {
                await _controller.setTorch(on: !_torchOn);
                if (!mounted) return;
                setState(() => _torchOn = !_torchOn);
              },
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            SupyBarcodeScannerView(
              controller: _controller,
              onBarcodeDetected: (b) => setState(() => _last = b),
            ),
            if (_last != null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: SupyBrand.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: SupyBrand.success,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _last!.rawValue,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SupyBrand.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _last!.format.wireName,
                        style: const TextStyle(
                          color: SupyBrand.onSurfaceMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
