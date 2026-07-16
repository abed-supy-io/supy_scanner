import 'package:flutter/widgets.dart';

import '../channel/supy_scanner_channel.dart';
import '../models/supy_document_data.dart';
import '../models/supy_scan_options.dart';

/// High-level entry point for the full-screen, multi-page document scanner.
///
/// This is the drop-in replacement for Scanbot's multi-page scanning flow that
/// the retailer's `InvoiceScannerService` wraps. A consumer keeps its
/// `Future<List<File>> scanWithCamera(BuildContext)` signature and maps the
/// returned [SupyDocumentData.pages] to files. See `docs/MIGRATION.md`.
abstract final class SupyDocumentScanner {
  /// Launches the native multi-page document scanner and resolves with the
  /// captured pages, or `null` if the user cancelled without capturing
  /// anything.
  ///
  /// [context] is accepted for call-site symmetry with Scanbot's
  /// `scanWithCamera(context)` and to default [locale] from the ambient
  /// [Localizations] (`'ar'` for Arabic, `'en'` otherwise) when it is omitted.
  ///
  /// Defaults mirror Scanbot parity: [maxPages] `0` is unlimited
  /// (Scanbot `pagesScanLimit = 0`); [ocrLanguages] is `['en', 'ar']`. The
  /// default [intent] is [SupyDocumentScanIntent.generic] so each page is
  /// persisted as an image — pass [SupyDocumentScanIntent.invoice] only if you
  /// want the invoice preset (which defaults the output to a multi-page PDF).
  static Future<SupyDocumentData?> startMultiPage(
    BuildContext context, {
    int maxPages = 0,
    List<String> ocrLanguages = const <String>['en', 'ar'],
    String palettePrimary = '#6448C3',
    String paletteOnPrimary = '#FFFFFF',
    String? locale,
    SupyDocumentScanIntent intent = SupyDocumentScanIntent.generic,
  }) {
    final resolvedLocale = locale ??
        (Localizations.maybeLocaleOf(context)?.languageCode == 'ar'
            ? 'ar'
            : 'en');
    return SupyScannerChannel.instance.scanDocument(
      SupyDocumentScanOptions(
        maxPages: maxPages,
        ocrLanguages: ocrLanguages,
        palettePrimary: palettePrimary,
        paletteOnPrimary: paletteOnPrimary,
        locale: resolvedLocale,
        intent: intent,
      ),
    );
  }
}
