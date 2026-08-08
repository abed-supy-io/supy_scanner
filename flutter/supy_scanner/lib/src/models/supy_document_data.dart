import 'package:meta/meta.dart';

import 'supy_document_page.dart';
import 'supy_document_scanner_backend.dart';

/// The result of a multi-page document scan.
@immutable
class SupyDocumentData {
  /// Creates a document scan result.
  const SupyDocumentData({
    required this.pages,
    required this.ocrText,
    this.pdfUri,
    this.tiffUri,
    this.resolvedBackend = SupyDocumentScannerBackend.unknown,
  });

  /// Deserializes a document result from a channel map.
  factory SupyDocumentData.fromMap(Map<Object?, Object?> map) {
    final rawPages = (map['pages']! as List<Object?>)
        .cast<Map<Object?, Object?>>()
        .map(SupyDocumentPage.fromMap)
        .toList(growable: false);
    return SupyDocumentData(
      pages: List.unmodifiable(rawPages),
      ocrText: (map['ocrText'] as String?) ?? '',
      pdfUri: map['pdfUri'] as String?,
      tiffUri: map['tiffUri'] as String?,
      resolvedBackend: SupyDocumentScannerBackend.fromWire(
        map['resolvedBackend'] as String?,
      ),
    );
  }

  /// Ordered list of captured pages.
  final List<SupyDocumentPage> pages;

  /// Concatenated OCR text across all pages.
  ///
  /// Empty string when OCR was disabled or produced no results.
  final String ocrText;

  /// File URI of the assembled multi-page PDF. Populated when
  /// `SupyDocumentScanOptions.outputFormat` is `pdf` (image-only) or
  /// `searchablePdf` (with an invisible OCR text layer). `null` otherwise.
  /// v1.1 / Sprint 7; `searchablePdf` added in v1.2 / Phase DC8.
  final String? pdfUri;

  /// File URI of the assembled multi-page TIFF. Populated only when
  /// `SupyDocumentScanOptions.outputFormat == SupyDocumentOutputFormat.tiff`.
  /// `null` otherwise. v1.2 / Phase DC8.
  final String? tiffUri;

  /// Which native backend produced this result. v1.2 / Phase CXD1.
  /// Android reports `gms` or `cameraX`; iOS always reports `gms`. Older
  /// native builds that predate the field will surface as `unknown`.
  final SupyDocumentScannerBackend resolvedBackend;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SupyDocumentData) return false;
    if (other.ocrText != ocrText) return false;
    if (other.pdfUri != pdfUri) return false;
    if (other.tiffUri != tiffUri) return false;
    if (other.resolvedBackend != resolvedBackend) return false;
    if (other.pages.length != pages.length) return false;
    for (var i = 0; i < pages.length; i++) {
      if (other.pages[i] != pages[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(pages),
    ocrText,
    pdfUri,
    tiffUri,
    resolvedBackend,
  );

  @override
  String toString() =>
      'SupyDocumentData(pages: ${pages.length}, ocrText: ${ocrText.length} chars'
      '${pdfUri != null ? ', pdfUri: $pdfUri' : ''}'
      '${tiffUri != null ? ', tiffUri: $tiffUri' : ''}, '
      'resolvedBackend: ${resolvedBackend.wireName})';
}
