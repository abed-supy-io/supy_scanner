// Pins the compat shim to the **exact call shapes** found in the retailer
// app at /Users/abdalqaderalnajjar/Projects/supy-projects/supy-mobile/apps/retailer.
//
// Each group mirrors one retailer file, top-of-group comment names the file
// and the line range the shape was lifted from. If a retailer file changes,
// update the matching group; if the compat surface changes in a way that
// breaks one of these shapes, this file fails first.
//
// Source inventory (read-only, do not edit retailer files from this repo):
//
//   - lib/core/services/scanbot/scanbot_index.dart
//   - lib/core/services/scanbot/barcode_scanbot_view.dart
//   - lib/core/services/scanbot/scanbot_sdk_manager.dart                (init/license — out of scope for this shim)
//   - lib/core/services/services_index.dart                              (re-export only)
//   - lib/features/inventory/presentation/pages/stock/scan_barcode/scan_barcode_counting_page.dart
//   - lib/features/invoice/services/invoice_scanner_service.dart
//   - lib/features/invoice/services/scanning_bot.dart                    (document UI — out of scope for this shim)
//
// `scanbot_sdk_manager.dart` and `scanning_bot.dart` touch document-UI v2
// types (`DocumentScanningFlow`, `ScanbotSdkUiV2`, `ScanbotColor`) that the
// Supy backend does not surface — they are tracked in MIGRATION.md under
// "Out-of-shim retailer references".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner_scanbot_compat/supy_scanner_scanbot_compat.dart';

void main() {
  group('retailer: barcode_scanbot_view.dart', () {
    // Mirrors lines 7-32 of the retailer file: the local
    // BarcodeScannerController shape.
    test('BarcodeScannerController.bind accepts (pause, resume, pausedNotifier)',
        () {
      final controller = BarcodeScannerController();
      final paused = ValueNotifier<bool>(false);
      controller.bind(
        pause: () {},
        resume: () {},
        pausedNotifier: paused,
      );
      expect(controller.isPaused, isFalse);
      paused.dispose();
    });

    // Mirrors the BarcodeScanbotView constructor invocation site (lines
    // 34-55 declaration + every callsite that passes header/footer/etc.).
    test('BarcodeScanbotView accepts the full retailer-shaped arg set', () {
      final controller = BarcodeScannerController();
      final widget = BarcodeScanbotView(
        onBarcodeDetected: (List<BarcodeItem> barcodes) async {
          final first = barcodes.first;
          // ignore: unused_local_variable
          final text = first.text;
        },
        header: const SizedBox.shrink(),
        footer: const SizedBox.shrink(),
        scannerBoxBuilder: (active) => const SizedBox.shrink(),
        controller: controller,
        scanWindow: const Rect.fromLTWH(0, 0, 100, 100),
      );
      expect(widget, isA<Widget>());
    });
  });

  group('retailer: scan_barcode_counting_page.dart', () {
    // Mirrors lines 270-280 of the retailer file (`build` method).
    test('BarcodeScanbotView usage: findBarcodeAtCenter:false + footer + '
        'onBarcodeDetected reads capture.first', () {
      final widget = BarcodeScanbotView(
        findBarcodeAtCenter: false,
        onBarcodeDetected: (capture) async {
          // ignore: unused_local_variable
          final text = capture.first.text;
        },
        footer: const SizedBox.shrink(),
      );
      expect(widget, isA<Widget>());
    });

    // Mirrors line 50 — `_handleBarcode(BuildContext, BarcodeItem capture)`.
    // Asserts BarcodeItem exposes `.text` as a String on the retailer's
    // happy path.
    test('BarcodeItem.text is a String getter (used by _handleBarcode)', () {
      // Compile-time pin: the retailer never constructs a BarcodeItem
      // itself, but it reads `capture.first.text` as a String. A nullable
      // reference is enough to compile-check the getter shape.
      // Compile-time pin of the `String text` getter shape. Declared as a
      // function so `.text` is type-checked but never executed.
      String textOf(BarcodeItem b) => b.text;
      expect(textOf, isNotNull);
    });
  });

  group('retailer: invoice_scanner_service.dart', () {
    // Mirrors lines 7-30 of the retailer file: the IInvoiceScannerService
    // abstract + its InvoiceScannerService implementation.
    test('IInvoiceScannerService is implemented by InvoiceScannerService', () {
      const service = InvoiceScannerService();
      expect(service, isA<IInvoiceScannerService>());
    });

    test('scanWithCamera returns Future<List<File>>', () {
      const service = InvoiceScannerService();
      final returnType = service.scanWithCamera;
      // The retailer assigns the awaited result to `List<File> result`,
      // then iterates `.map((p) => ...)` — the shim must keep that.
      expect(returnType, isA<Future<List<File>> Function(BuildContext)>());
    });
  });

  group('retailer: scanbot_index.dart (re-export barrel)', () {
    // The retailer barrel re-exports the view + the SDK manager. We only
    // own the view side; the manager (Scanbot license init) is not part of
    // the shim — see MIGRATION.md "Out-of-shim retailer references".
    test('compat barrel exports the symbols the retailer barrel forwards',
        () {
      // Type-existence check — if any of these are renamed/removed the
      // test stops compiling.
      expect(BarcodeScannerController, isNotNull);
      expect(BarcodeScanbotView, isNotNull);
      expect(BarcodeItem, isNotNull);
    });
  });
}
