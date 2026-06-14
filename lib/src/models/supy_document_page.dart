import 'package:meta/meta.dart';

/// Coarse, user-meaningful per-page quality bucket. v1.1 / Sprint 7.
///
/// Native side scores each persisted page (variance-of-Laplacian for sharpness
/// + luma stats for exposure) and maps the raw `qualityScore` (0..1) onto one
/// of these buckets. Order matches Scanbot's `DocumentQuality` (1..5).
enum SupyDocumentPageQuality {
  /// Severely blurred / out-of-focus / over- or under-exposed. Re-capture.
  veryPoor,

  /// Noticeably degraded. OCR may misread; consider re-capture.
  poor,

  /// Acceptable for OCR; not pretty.
  ok,

  /// Sharp + well-exposed. Default expectation.
  good,

  /// Crisp, evenly lit, archival-grade.
  excellent,
}

/// One captured page of a scanned document.
@immutable
class SupyDocumentPage {
  /// Creates a document page result.
  const SupyDocumentPage({
    required this.uri,
    required this.width,
    required this.height,
    this.quality,
    this.qualityScore,
  });

  /// Deserializes a page from a channel map.
  factory SupyDocumentPage.fromMap(Map<Object?, Object?> map) {
    return SupyDocumentPage(
      uri: map['uri']! as String,
      width: (map['width']! as num).toInt(),
      height: (map['height']! as num).toInt(),
      quality: _qualityFromWire(map['quality'] as String?),
      qualityScore: (map['qualityScore'] as num?)?.toDouble(),
    );
  }

  /// File URI of the persisted page image. Format: `file:///...`. Encoded as
  /// JPEG by default; switches to PNG / contributes-to-PDF based on
  /// `SupyDocumentScanOptions.outputFormat`.
  final String uri;

  /// Pixel width of the persisted image.
  final int width;

  /// Pixel height of the persisted image.
  final int height;

  /// Coarse quality bucket assigned by the native scorer. `null` until the
  /// v1.1 native core lands per-page scoring (Sprint 7).
  final SupyDocumentPageQuality? quality;

  /// Raw quality score in `[0..1]` from the native scorer (variance-of-
  /// Laplacian + luma). `null` when the scorer hasn't run.
  final double? qualityScore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentPage &&
          other.uri == uri &&
          other.width == width &&
          other.height == height &&
          other.quality == quality &&
          other.qualityScore == qualityScore;

  @override
  int get hashCode =>
      Object.hash(uri, width, height, quality, qualityScore);

  @override
  String toString() =>
      'SupyDocumentPage(uri: $uri, ${width}x$height, '
      'quality: $quality, score: $qualityScore)';
}

SupyDocumentPageQuality? _qualityFromWire(String? wire) {
  switch (wire) {
    case 'veryPoor':
      return SupyDocumentPageQuality.veryPoor;
    case 'poor':
      return SupyDocumentPageQuality.poor;
    case 'ok':
      return SupyDocumentPageQuality.ok;
    case 'good':
      return SupyDocumentPageQuality.good;
    case 'excellent':
      return SupyDocumentPageQuality.excellent;
    case null:
      return null;
    default:
      return null;
  }
}
