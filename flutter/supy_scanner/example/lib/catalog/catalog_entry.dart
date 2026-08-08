import 'package:flutter/material.dart';

/// Top-level grouping a [CatalogEntry] belongs to in the example home.
enum CatalogCategory {
  barcode('Barcode', Icons.qr_code_scanner),
  document('Document', Icons.document_scanner),
  ocr('OCR & Text', Icons.text_fields),
  dataCapture('Data Capture', Icons.pattern),
  advanced('Advanced', Icons.tune),
  devQa('Dev / QA', Icons.developer_mode);

  const CatalogCategory(this.label, this.icon);

  /// Section header shown in the catalog home.
  final String label;

  /// Leading icon for the section header.
  final IconData icon;
}

/// A single showcase in the example app.
///
/// One entry == one feature of the public `supy_scanner` API. The [title] and
/// [description] make the catalog self-explanatory; [apiSummary] names the exact
/// `Supy*` types the demo exercises so the example doubles as API reference.
@immutable
class CatalogEntry {
  const CatalogEntry({
    required this.category,
    required this.icon,
    required this.title,
    required this.description,
    required this.apiSummary,
    required this.builder,
  });

  /// Section this entry is filed under on the home screen.
  final CatalogCategory category;

  /// Leading icon on the entry card.
  final IconData icon;

  /// Short entry title, e.g. "Single scan".
  final String title;

  /// One-line description of what the feature does / when to use it.
  final String description;

  /// The `Supy*` types and methods the demo calls, e.g.
  /// `SupyScannerChannel.recognizeText → SupyVinParser.parse`.
  final String apiSummary;

  /// Builds the detail page. Usually returns a `DemoScaffold`.
  final WidgetBuilder builder;
}
