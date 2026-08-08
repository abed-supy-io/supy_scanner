/// Image enhancement intensity applied to captured document pages before
/// they are persisted, OCR'd, or assembled into a PDF.
///
/// The pipeline (illumination flatten → tone curve → unsharp mask, gated by
/// a blur quality check) runs in the shared native C++ core so Android and
/// iOS produce visually comparable output. See `docs/ENHANCEMENT.md`.
enum SupyDocumentEnhanceMode {
  /// Disable the native enhance pipeline entirely. The raw capture is
  /// persisted as-is. Default on iOS, where VisionKit already enhances.
  off,

  /// Fast preset — illumination flatten only. ~1.5× faster than `balanced`
  /// at the cost of contrast/sharpness.
  fast,

  /// Default Android preset — illumination + tone + unsharp. Best
  /// general-purpose result for OCR / LLM ingestion / human viewing.
  balanced,

  /// Maximum quality — reserved for the v2 denoise/binarize stages. Today
  /// behaves identically to [balanced]; will diverge once v2 lands.
  max;

  /// Wire-format value sent on the method channel.
  String get wireName => name;
}
