import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../channel/supy_scanner_channel.dart';
import '../licensing/supy_scanner_license.dart';
import '../models/supy_barcode.dart';
import '../models/supy_batch_barcode_options.dart';
import '../models/supy_batch_barcode_result.dart';
import '../models/supy_scan_options.dart';
import '../models/ui/supy_multiple_scan_use_case_configuration.dart';
import '../models/ui/supy_scan_use_case.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../widgets/supy_barcode_scanner_screen.dart';
import '../widgets/supy_multiple_scan_accumulator.dart';

/// High-level entry point for the full-screen, multi-count barcode scanner —
/// Scanbot's `BatchBarcodeScanner` / "scan many barcodes in one session" flow.
///
/// This is the drop-in replacement for the native batch presenter the retailer
/// app used to launch. A consumer keeps its
/// `Future<SupyBatchBarcodeResult?> scanBatch(BuildContext)` shape; the result
/// is identical whichever path runs. See `docs/MIGRATION.md`.
abstract final class SupyBarcodeScanner {
  /// Launches the multi-count barcode session and resolves with the accumulated
  /// result, or `null` if the user cancelled without keeping anything.
  ///
  /// Routing (see `TODO.md` decisions + `docs/MIGRATION.md`):
  /// - On Android / iOS this pushes the Supy-branded Flutter session
  ///   ([SupyBarcodeScannerScreen] in its multi-scan use case) so the whole
  ///   detect → accumulate → submit loop is drawn by Flutter over the native
  ///   camera preview. The [SupyBatchBarcodeResult] is adapted from the branded
  ///   accumulator: `items` are the distinct payloads (first-seen order),
  ///   `duplicateCount` is the number of repeat detections.
  /// - Any non-mobile platform (web / desktop) falls back to the native
  ///   full-screen batch scanner via [SupyScannerChannel.scanBarcodesBatch].
  ///
  /// [context] is accepted for call-site symmetry with the native launcher and
  /// to host the pushed route on the mobile path.
  ///
  /// [options] carries the Scanbot-parity batch knobs (formats, dedupe window).
  /// On the branded path they map onto the embedded view + accumulator; on the
  /// native path they are forwarded verbatim on the wire.
  static Future<SupyBatchBarcodeResult?> startMultiple(
    BuildContext context, {
    SupyBatchBarcodeScanOptions options = const SupyBatchBarcodeScanOptions(),
    SupyMultipleScanUseCaseConfiguration? sheetConfiguration,
    String palettePrimary = '#6448C3',
    String paletteOnPrimary = '#FFFFFF',
  }) {
    SupyLicenseGate.ensureActivated();
    if (_useBrandedSession()) {
      return _startBranded(
        context,
        options: options,
        sheetConfiguration: sheetConfiguration,
        palettePrimary: palettePrimary,
        paletteOnPrimary: paletteOnPrimary,
      );
    }

    return SupyScannerChannel.instance.scanBarcodesBatch(options);
  }

  /// The branded Flutter session covers the two mobile targets. Web / desktop
  /// have no embedded PlatformView, so they fall back to the native scanner.
  static bool _useBrandedSession() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Pushes the branded multi-scan session and bridges its submit / cancel
  /// callbacks to the route result. The screen never pops itself; a submit
  /// resolves with the adapted [SupyBatchBarcodeResult] and a cancel with
  /// `null`, mirroring the native scanner's terminal outcomes.
  static Future<SupyBatchBarcodeResult?> _startBranded(
    BuildContext context, {
    required SupyBatchBarcodeScanOptions options,
    required SupyMultipleScanUseCaseConfiguration? sheetConfiguration,
    required String palettePrimary,
    required String paletteOnPrimary,
  }) {
    // Counting mode so repeat detections are tracked — that is what lets the
    // adapter recover a Scanbot-parity `duplicateCount`. The dedupe window maps
    // onto the counting debounce. Callers can override the whole config.
    final config =
        sheetConfiguration ??
        SupyMultipleScanUseCaseConfiguration(
          mode: SupyMultipleScanMode.counting,
          countingRepeatDelay: Duration(milliseconds: options.dedupeWindowMs),
        );

    final accent = _parseHexColor(palettePrimary);
    final onAccent = _parseHexColor(paletteOnPrimary);
    const base = SupyScannerPalette.supyDark();
    final palette = base.copyWith(primary: accent, onPrimary: onAccent);

    return Navigator.of(context).push<SupyBatchBarcodeResult>(
      MaterialPageRoute<SupyBatchBarcodeResult>(
        fullscreenDialog: true,
        builder:
            (routeContext) => SupyBarcodeScannerScreen(
              useCase: SupyMultipleScanUseCase(config: config),
              scanOptions: SupyBarcodeScanOptions(formats: options.formats),
              palette: palette,
              onMultipleScan:
                  (items) =>
                      Navigator.of(routeContext).pop(_toBatchResult(items)),
              onCancel: () => Navigator.of(routeContext).pop(),
            ),
      ),
    );
  }

  /// Adapts the branded accumulator's rows to the native batch result shape.
  /// `items` are the distinct payloads (one per row, first-seen order);
  /// `duplicateCount` is every detection beyond the first for each payload
  /// (`sum(counts) - uniqueRows`).
  @visibleForTesting
  static SupyBatchBarcodeResult debugToBatchResult(
    List<SupyMultipleScanItem> items,
  ) => _toBatchResult(items);

  static SupyBatchBarcodeResult _toBatchResult(
    List<SupyMultipleScanItem> items,
  ) {
    final total = items.fold<int>(0, (sum, i) => sum + i.count);
    return SupyBatchBarcodeResult(
      items: items.map<SupyBarcode>((i) => i.barcode).toList(),
      duplicateCount: total - items.length,
    );
  }

  /// Parses a `#RRGGBB` / `#AARRGGBB` (or `0x`-prefixed) hex string. Returns
  /// `null` for anything unparseable so the caller keeps the preset token.
  static Color? _parseHexColor(String value) {
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.startsWith('0x') || hex.startsWith('0X')) hex = hex.substring(2);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
