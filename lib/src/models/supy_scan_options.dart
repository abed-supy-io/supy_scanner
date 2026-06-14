import 'package:meta/meta.dart';

import 'supy_barcode_format.dart';
import 'ui/supy_camera_configuration.dart';

/// Options for the embedded barcode scanner.
@immutable
class SupyBarcodeScanOptions {
  /// Creates barcode scan options.
  const SupyBarcodeScanOptions({
    this.formats = const [SupyBarcodeFormat.all],
    this.useScanWindow = false,
    this.findBarcodeAtCenter = false,
    this.useNativeCore = false,
    this.camera = const SupyCameraConfiguration(),
  });

  /// Active symbologies. Defaults to [SupyBarcodeFormat.all].
  final List<SupyBarcodeFormat> formats;

  /// When `true`, only barcodes inside the on-screen finder window are
  /// reported.
  final bool useScanWindow;

  /// When `true`, only the barcode closest to the preview center is reported
  /// per detection pass (matches Scanbot's `findBarcodeAtCenter`).
  final bool findBarcodeAtCenter;

  /// v1.1 feature flag — when `true`, the native C++ core handles
  /// pre-processing (binarization, deconvolution, fusion) before handing
  /// the frame to ML Kit / Vision. Default `false` keeps the v1.0
  /// behaviour. See docs/V1.1_PLAN.md.
  final bool useNativeCore;

  /// Camera-level configuration applied at preview-start.
  final SupyCameraConfiguration camera;

  /// Serializes to the channel argument shape.
  Map<String, Object?> toWire() => {
        'formats': formats.map((f) => f.wireName).toList(),
        'useScanWindow': useScanWindow,
        'findBarcodeAtCenter': findBarcodeAtCenter,
        'useNativeCore': useNativeCore,
        'camera': camera.toWire(),
      };
}

/// Per-page image encoding for the document scanner. v1.1 / Sprint 7.
///
/// - [jpg] — default; matches v1.0 behaviour. Honours `jpegQuality`.
/// - [png] — lossless. `jpegQuality` is ignored.
/// - [pdf] — pages still persist individually (as JPG), AND the native side
///   assembles a single multi-page PDF whose URI is surfaced on
///   `SupyDocumentData.pdfUri`.
enum SupyDocumentOutputFormat {
  /// JPEG-encoded pages. Default — preserves v1.0 behaviour.
  jpg,

  /// PNG-encoded pages (lossless).
  png,

  /// JPG pages + an assembled multi-page PDF on `SupyDocumentData.pdfUri`.
  pdf,
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
    this.useNativeCore = false,
    this.autoCaptureDelayMs = 800,
    this.outputFormat = SupyDocumentOutputFormat.jpg,
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

  /// v1.1 feature flag — when `true`, the native C++ core post-processes
  /// captured pages (shadow removal, top-hat flatten, CLAHE, perspective
  /// warp to ≥300 DPI) before OCR. Default `false` keeps the v1.0
  /// behaviour. See docs/V1.1_PLAN.md.
  final bool useNativeCore;

  /// Milliseconds the embedded scanner waits in `ready` before auto-firing
  /// `controller.capture()`. `0` disables auto-capture; the consumer must
  /// trigger captures manually. Defaults to 800ms — matches Scanbot's
  /// "Ready → Capturing" hold.
  final int autoCaptureDelayMs;

  /// Per-page encoding. Defaults to [SupyDocumentOutputFormat.jpg] (v1.0
  /// behaviour). v1.1 / Sprint 7 — `png` switches the encoder; `pdf` adds
  /// a multi-page PDF URI on the result.
  final SupyDocumentOutputFormat outputFormat;

  /// Serializes to the channel argument shape.
  Map<String, Object?> toWire() => {
        'maxPages': maxPages,
        'ocrLanguages': ocrLanguages,
        'jpegQuality': jpegQuality,
        'locale': locale,
        'palettePrimary': palettePrimary,
        'paletteOnPrimary': paletteOnPrimary,
        'useNativeCore': useNativeCore,
        'autoCaptureDelayMs': autoCaptureDelayMs,
        'outputFormat': outputFormat.name,
      };
}
