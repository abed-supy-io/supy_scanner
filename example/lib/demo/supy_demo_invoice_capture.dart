import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../branding/supy_brand.dart';
import 'invoice/invoice_capture_screen.dart';
import 'invoice/invoice_confirm_screen.dart';

/// Entry point for the Option B invoice flow demo.
///
/// Orchestrates the three stages: **Capture** (embedded multi-page scanner) →
/// **Confirm invoice** (branded review with edit / supplier / upload) →
/// **Invoice uploaded**. This is the Supy-branded confirmation step the raw
/// Scanbot SDK is missing.
class SupyDemoInvoiceCapture extends StatelessWidget {
  const SupyDemoInvoiceCapture({super.key});

  Future<void> _start(BuildContext context) async {
    final pages = await Navigator.of(context).push<List<SupyDocumentPage>>(
      MaterialPageRoute(builder: (_) => const InvoiceCaptureScreen()),
    );
    if (pages == null || pages.isEmpty || !context.mounted) return;

    final outcome = await Navigator.of(context).push<InvoiceConfirmOutcome>(
      MaterialPageRoute(builder: (_) => InvoiceConfirmScreen(pages: pages)),
    );
    if (!context.mounted) return;

    // If the user chose "Rescan" from confirm, loop back into capture.
    if (outcome == InvoiceConfirmOutcome.cancelled) {
      return _start(context);
    }
    if (outcome == InvoiceConfirmOutcome.uploaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice uploaded successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Invoice capture (Option B)')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: SupyBrand.accent,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Scan an invoice',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: SupyBrand.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Capture one or more pages, review and edit them, pick a '
                  'supplier, then upload — with an explicit confirm step.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SupyBrand.onSurfaceMuted),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _start(context),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Start scanning'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
