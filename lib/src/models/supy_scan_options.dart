import 'package:meta/meta.dart';

import '../enhance/supy_document_enhance_mode.dart';
import '../enhance/supy_document_filter.dart';
import 'supy_barcode_format.dart';
import 'supy_document_page.dart';
import 'supy_document_scanner_backend.dart';
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

/// Capture intent for the document scanner. Drives a small bundle of preset
/// thresholds + UX decisions; consumers can still override individual
/// [SupyDocumentScanOptions] fields and those win over the preset.
///
/// Precedence (highest first):
///   1. Caller-supplied option (anything not equal to the type's default).
///   2. Intent preset (when [SupyDocumentScanOptions.intent] is non-generic).
///   3. Plugin / native defaults.
enum SupyDocumentScanIntent {
  /// Generic single-page capture — keeps v1.0 behaviour.
  generic,

  /// Multi-page invoice / receipt capture. Tightens the live-preview gates
  /// (edge-clipping becomes blocking), bumps the per-page quality threshold,
  /// and defaults the output to a multi-page PDF.
  invoice,
}

/// Options for the document scanner flow.
@immutable
class SupyDocumentScanOptions {
  /// Creates document scan options.
  const SupyDocumentScanOptions({
    this.maxPages = 0,
    this.ocrLanguages = const ['en', 'ar'],
    this.jpegQuality = 95,
    this.locale = 'en',
    this.palettePrimary = '#6448C3',
    this.paletteOnPrimary = '#FFFFFF',
    this.useNativeCore = false,
    this.autoCaptureDelayMs = 800,
    this.outputFormat = SupyDocumentOutputFormat.jpg,
    this.enhanceMode,
    this.preferredBackend,
    this.filter = SupyDocumentFilter.color,
    this.minPageQuality = SupyDocumentPageQuality.poor,
    this.intent = SupyDocumentScanIntent.generic,
  });

  /// Maximum pages to capture. `0` means unlimited (matches Scanbot's
  /// `pagesScanLimit = 0`).
  final int maxPages;

  /// OCR language hints. Use BCP-47 / ISO 639-1 short codes.
  final List<String> ocrLanguages;

  /// JPEG quality (0–100) for persisted page images. Defaults to `95` to
  /// match the perceived sharpness of the legacy Scanbot output on the same
  /// camera. On Android this also unlocks the GMS passthrough fast-path
  /// (no re-encode) when `enhanceMode` is `off`.
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

  /// Native image enhancement intensity applied to each captured page before
  /// persistence / OCR / PDF assembly. `null` (the default) lets each platform
  /// pick its own default — Android defaults to [SupyDocumentEnhanceMode.balanced]
  /// (the native pipeline is the only source of enhancement), iOS defaults to
  /// [SupyDocumentEnhanceMode.off] because VisionKit already enhances. Set
  /// explicitly to force a specific mode on both platforms.
  final SupyDocumentEnhanceMode? enhanceMode;

  /// Forces a specific document scanner backend. `null` (the default) lets
  /// the native side decide — Android picks GMS where Play Services are
  /// usable and CameraX otherwise; iOS always uses VisionKit. Set to
  /// [SupyDocumentScannerBackend.cameraX] to exercise the non-GMS path on
  /// GMS-available devices (tests, dogfood). [SupyDocumentScannerBackend.unknown]
  /// is rejected by the native side.
  final SupyDocumentScannerBackend? preferredBackend;

  /// Per-page visual filter applied after the platform scanner returns its
  /// capture. Defaults to [SupyDocumentFilter.color] — paper-preserving
  /// re-processing that matches Scanbot's output style. iOS-only in v1;
  /// Android ignores this and uses the native-core enhance pipeline.
  final SupyDocumentFilter filter;

  /// Minimum acceptable per-page quality bucket. Pages scoring below this
  /// trigger an in-flow retake prompt on iOS / CameraX and a post-flow
  /// summary sheet on Android-GMS. Defaults to
  /// [SupyDocumentPageQuality.poor] — i.e. only `veryPoor` pages prompt —
  /// so the default is drop-in safe vs. v1.0.
  final SupyDocumentPageQuality minPageQuality;

  /// Capture intent. Selecting [SupyDocumentScanIntent.invoice] applies the
  /// invoice preset across the live-preview gates, the per-page quality
  /// threshold, output format, and enhance mode — but only for fields the
  /// caller left at this type's default. See [SupyDocumentScanIntent] for
  /// the precedence rule.
  final SupyDocumentScanIntent intent;

  /// Serializes to the channel argument shape.
  ///
  /// When [intent] is non-generic, the invoice preset is folded in on a
  /// field-by-field basis using the precedence rule documented on
  /// [SupyDocumentScanIntent]: caller > preset > defaults. The intent itself
  /// is always sent on the wire so the native side can apply preset effects
  /// that have no Dart-side option (e.g. multi-page "Add another?" prompts).
  Map<String, Object?> toWire() {
    final isInvoice = intent == SupyDocumentScanIntent.invoice;

    // "Caller left it default" — used to decide whether the preset wins.
    // Compared against the constructor defaults so an explicit caller value
    // that *happens* to match a default is still treated as default (the
    // intent preset is just a smarter default, never an override).
    final effectiveOutputFormat =
        isInvoice && outputFormat == SupyDocumentOutputFormat.jpg
            ? SupyDocumentOutputFormat.pdf
            : outputFormat;
    final effectiveEnhanceMode = enhanceMode ??
        (isInvoice ? SupyDocumentEnhanceMode.balanced : null);
    final effectiveMinPageQuality =
        isInvoice && minPageQuality == SupyDocumentPageQuality.poor
            ? SupyDocumentPageQuality.ok
            : minPageQuality;

    return {
      'maxPages': maxPages,
      'ocrLanguages': ocrLanguages,
      'jpegQuality': jpegQuality,
      'locale': locale,
      'palettePrimary': palettePrimary,
      'paletteOnPrimary': paletteOnPrimary,
      'useNativeCore': useNativeCore,
      'autoCaptureDelayMs': autoCaptureDelayMs,
      'outputFormat': effectiveOutputFormat.name,
      'filter': filter.wireName,
      'minPageQuality': effectiveMinPageQuality.wireName,
      'intent': intent.name,
      if (effectiveEnhanceMode != null)
        'enhanceMode': effectiveEnhanceMode.wireName,
      if (preferredBackend != null)
        'preferredBackend': preferredBackend!.wireName,
    };
  }
}
