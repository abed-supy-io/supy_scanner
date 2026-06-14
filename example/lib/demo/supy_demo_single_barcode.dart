import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../branding/supy_brand.dart';
import 'widgets/supy_result_card.dart';

class SupyDemoSingleBarcodePage extends StatefulWidget {
  const SupyDemoSingleBarcodePage({super.key});

  @override
  State<SupyDemoSingleBarcodePage> createState() =>
      _SupyDemoSingleBarcodePageState();
}

class _SupyDemoSingleBarcodePageState extends State<SupyDemoSingleBarcodePage> {
  SupyBarcode? _last;
  String? _error;

  Future<void> _launch() async {
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => SupyBarcodeScannerScreen(
          useCase: const SupySingleScanUseCase(),
          palette: SupyBrand.palette,
          onCancel: () => navigator.maybePop(),
          onSingleScan: (b) {
            navigator.maybePop();
            setState(() {
              _last = b;
              _error = null;
            });
          },
          onError: (e) {
            navigator.maybePop();
            setState(() => _error = e.toString());
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Scan Barcode')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _launch,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Open scanner'),
              ),
              const SizedBox(height: 20),
              if (_last != null)
                SupyResultCard(
                  title: 'LAST SCAN',
                  value: _last!.rawValue,
                  subtitle: _last!.format.wireName,
                  leading: const Icon(
                    Icons.check_circle,
                    color: SupyBrand.success,
                  ),
                )
              else if (_error != null)
                SupyResultCard(
                  title: 'ERROR',
                  value: _error!,
                  leading: const Icon(
                    Icons.error_outline,
                    color: SupyBrand.critical,
                  ),
                )
              else
                const SupyResultCard(
                  title: 'WAITING',
                  value: 'No scan yet',
                  subtitle: 'Tap "Open scanner" to begin.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
