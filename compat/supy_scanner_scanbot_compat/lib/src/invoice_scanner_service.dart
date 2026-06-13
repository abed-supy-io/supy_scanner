import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// Abstract surface preserved verbatim from the retailer's
/// `features/invoice/services/invoice_scanner_service.dart`.
abstract class IInvoiceScannerService {
  /// Launches the document scanner UI and returns the captured page files.
  Future<List<File>> scanWithCamera(BuildContext context);
}

/// Scanbot-shaped invoice scanner backed by `supy_scanner`'s document flow.
///
/// Errors collapse to an empty list, matching the original behaviour
/// (`scanWithCamera` resolves with `[]` on cancel or failure rather than
/// throwing).
class InvoiceScannerService implements IInvoiceScannerService {
  /// Creates a Scanbot-shaped scanner. Pass [channel] only in tests to inject
  /// a fake `SupyScannerChannel`; production callers should use the no-arg
  /// form, mirroring the retailer's existing `InvoiceScannerService()` shape.
  const InvoiceScannerService({SupyScannerChannel? channel})
      : _channel = channel;

  final SupyScannerChannel? _channel;

  SupyScannerChannel get _ch => _channel ?? SupyScannerChannel.instance;

  @override
  Future<List<File>> scanWithCamera(BuildContext context) async {
    final languageCode = Localizations.maybeLocaleOf(context)?.languageCode;
    final locale = languageCode == 'ar' ? 'ar' : 'en';

    try {
      final result = await _ch.scanDocument(
        SupyDocumentScanOptions(locale: locale),
      );
      if (result == null) return const <File>[];
      return _pagesToFiles(result.pages);
    } on SupyScanError {
      // `cancelled` and any other native error degrade to an empty list so
      // call sites that already branch on `result.isEmpty` keep working.
      return const <File>[];
    }
  }

  List<File> _pagesToFiles(List<SupyDocumentPage> pages) {
    return pages
        .map((p) => File(Uri.parse(p.uri).toFilePath()))
        .where((f) => f.existsSync())
        .toList(growable: false);
  }
}
