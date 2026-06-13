import 'package:meta/meta.dart';

import 'supy_barcode_format.dart';

/// Options for the embedded barcode scanner.
@immutable
class SupyBarcodeScanOptions {
  /// Creates barcode scan options.
  const SupyBarcodeScanOptions({
    this.formats = const [SupyBarcodeFormat.all],
    this.useScanWindow = false,
    this.findBarcodeAtCenter = false,
  });

  /// Active symbologies. Defaults to [SupyBarcodeFormat.all].
  final List<SupyBarcodeFormat> formats;

  /// When `true`, only barcodes inside the on-screen finder window are
  /// reported.
  final bool useScanWindow;

  /// When `true`, only the barcode closest to the preview center is reported
  /// per detection pass (matches Scanbot's `findBarcodeAtCenter`).
  final bool findBarcodeAtCenter;

  /// Serializes to the channel argument shape.
  Map<String, Object?> toWire() => {
        'formats': formats.map((f) => f.wireName).toList(),
        'useScanWindow': useScanWindow,
        'findBarcodeAtCenter': findBarcodeAtCenter,
      };
}

/// Options for the document scanner flow.
@immutable
class SupyDocumentScanOptions {
  /// Creates document scan options.
  const SupyDocumentScanOptions({
    this.maxPages = 0,
    this.ocrLanguages = const ['en', 'ar'],
    this.jpegQuality = 85,
    this.locale = 'en',
    this.palettePrimary = '#6448C3',
    this.paletteOnPrimary = '#FFFFFF',
  });

  /// Maximum pages to capture. `0` means unlimited (matches Scanbot's
  /// `pagesScanLimit = 0`).
  final int maxPages;

  /// OCR language hints. Use BCP-47 / ISO 639-1 short codes.
  final List<String> ocrLanguages;

  /// JPEG quality (0–100) for persisted page images.
  final int jpegQuality;

  /// Locale for in-scanner UI guidance (`'en'` or `'ar'`).
  final String locale;

  /// Hex color used for primary buttons (`#RRGGBB`).
  final String palettePrimary;

  /// Hex color used for on-primary content (`#RRGGBB`).
  final String paletteOnPrimary;

  /// Serializes to the channel argument shape.
  Map<String, Object?> toWire() => {
        'maxPages': maxPages,
        'ocrLanguages': ocrLanguages,
        'jpegQuality': jpegQuality,
        'locale': locale,
        'palettePrimary': palettePrimary,
        'paletteOnPrimary': paletteOnPrimary,
      };
}
