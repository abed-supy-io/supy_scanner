import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner_scanbot_compat/supy_scanner_scanbot_compat.dart';

/// These tests don't run native code — they only assert that the retailer's
/// call shapes compile against the compat surface. If a retailer file would
/// fail to compile after switching imports, this file fails first.
void main() {
  test('BarcodeScanbotView accepts retailer-shaped args', () {
    final controller = BarcodeScannerController();
    final widget = BarcodeScanbotView(
      onBarcodeDetected: (List<BarcodeItem> barcodes) async {
        // Mirrors `assign_barcode_page.dart` — read .first.text.
        final first = barcodes.first;
        // ignore: unused_local_variable
        final text = first.text;
      },
      header: const SizedBox.shrink(),
      footer: const SizedBox.shrink(),
      controller: controller,
      scannerBoxBuilder: (active) => const SizedBox.shrink(),
      scanWindow: const Rect.fromLTWH(0, 0, 100, 100),
    );
    expect(widget, isA<Widget>());
  });

  test('BarcodeScannerController exposes pause/resume/toggle', () {
    final controller = BarcodeScannerController();
    expect(controller.isPaused, isFalse);
    // Not awaited — would otherwise hit a real MethodChannel.
    // We only need this to compile.
    // ignore: unawaited_futures
    controller.pause;
    // ignore: unawaited_futures
    controller.resume;
    // ignore: unawaited_futures
    controller.toggle;
  });

  test('InvoiceScannerService implements IInvoiceScannerService', () {
    const service = InvoiceScannerService();
    expect(service, isA<IInvoiceScannerService>());
  });
}
