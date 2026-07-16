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

/// Extension on [SupyDocumentPageQuality] exposing the symmetric counterpart
/// to the internal `_qualityFromWire` parser. Names must stay byte-identical
/// to the wire strings the native side emits — these are the values the
/// per-page quality gate threshold (`minPageQuality`) ships across the
/// channel.
extension SupyDocumentPageQualityWire on SupyDocumentPageQuality {
  /// Channel-stable identifier (`'veryPoor'`/`'poor'`/`'ok'`/`'good'`/
  /// `'excellent'`). Mirrors the strings parsed by the internal
  /// `_qualityFromWire`.
  String get wireName {
    switch (this) {
      case SupyDocumentPageQuality.veryPoor:
        return 'veryPoor';
      case SupyDocumentPageQuality.poor:
        return 'poor';
      case SupyDocumentPageQuality.ok:
        return 'ok';
      case SupyDocumentPageQuality.good:
        return 'good';
      case SupyDocumentPageQuality.excellent:
        return 'excellent';
    }
  }
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
    this.enhancedStages,
    this.enhanceMs,
  });

  /// Deserializes a page from a channel map.
  factory SupyDocumentPage.fromMap(Map<Object?, Object?> map) {
    return SupyDocumentPage(
      uri: map['uri']! as String,
      width: (map['width']! as num).toInt(),
      height: (map['height']! as num).toInt(),
      quality: _qualityFromWire(map['quality'] as String?),
      qualityScore: (map['qualityScore'] as num?)?.toDouble(),
      enhancedStages: (map['enhancedStages'] as num?)?.toInt(),
      enhanceMs: (map['enhanceMs'] as num?)?.toInt(),
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

  /// Bitmask of enhance stages that ran on this page. `null` when enhance
  /// was disabled or unsupported. See `docs/ENHANCEMENT.md` for bit layout.
  final int? enhancedStages;

  /// Wall-clock milliseconds the enhance pipeline spent on this page. `null`
  /// when enhance didn't run.
  final int? enhanceMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentPage &&
          other.uri == uri &&
          other.width == width &&
          other.height == height &&
          other.quality == quality &&
          other.qualityScore == qualityScore &&
          other.enhancedStages == enhancedStages &&
          other.enhanceMs == enhanceMs;

  @override
  int get hashCode => Object.hash(
        uri,
        width,
        height,
        quality,
        qualityScore,
        enhancedStages,
        enhanceMs,
      );

  @override
  String toString() =>
      'SupyDocumentPage(uri: $uri, ${width}x$height, '
      'quality: $quality, score: $qualityScore, '
      'enhancedStages: $enhancedStages, enhanceMs: $enhanceMs)';
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
