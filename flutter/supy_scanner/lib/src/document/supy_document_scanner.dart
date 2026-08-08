import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../channel/supy_scanner_channel.dart';
import '../licensing/supy_scanner_license.dart';
import '../models/supy_document_data.dart';
import '../models/supy_scan_options.dart';
import '../models/ui/supy_document_guidance_configuration.dart';
import '../models/ui/supy_document_scan_mode.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../widgets/supy_document_scanner_screen.dart';

/// High-level entry point for the full-screen, multi-page document scanner.
///
/// This is the drop-in replacement for Scanbot's multi-page scanning flow that
/// the retailer's `InvoiceScannerService` wraps. A consumer keeps its
/// `Future<List<File>> scanWithCamera(BuildContext)` signature and maps the
/// returned [SupyDocumentData.pages] to files. See `docs/MIGRATION.md`.
abstract final class SupyDocumentScanner {
  /// Launches the multi-page document scanner and resolves with the captured
  /// pages, or `null` if the user cancelled without capturing anything.
  ///
  /// Routing (see `TODO.md` decisions + `docs/MIGRATION.md`):
  /// - On Android / iOS, both [SupyDocumentScanIntent.generic] and
  ///   [SupyDocumentScanIntent.invoice] push the Supy-branded Flutter session
  ///   ([SupyDocumentScannerScreen]) so the whole capture → page-tray → done
  ///   loop is drawn by Flutter over the native camera preview. The result
  ///   carries `ocrText: ''` and no `pdfUri` — the retailer's
  ///   `InvoiceScannerService` consumes only `.pages`, and server-side OCR is
  ///   the source of truth (on-device OCR is only an optimization), so this is
  ///   behaviorally equivalent for those call sites.
  /// - Any non-mobile platform (web / desktop) falls back to the native
  ///   full-screen scanner.
  ///
  /// [context] is accepted for call-site symmetry with Scanbot's
  /// `scanWithCamera(context)` and to default [locale] from the ambient
  /// [Localizations] (`'ar'` for Arabic, `'en'` otherwise) when it is omitted.
  ///
  /// Defaults mirror Scanbot parity: [maxPages] `0` is unlimited
  /// (Scanbot `pagesScanLimit = 0`); [ocrLanguages] is `['en', 'ar']`.
  ///
  /// [autoCapture] defaults to `false`: the branded session waits for a manual
  /// shutter tap. Pass `true` to re-enable the countdown-and-shoot behaviour.
  /// (Ignored on the native fall-back path, which has no auto-capture.)
  static Future<SupyDocumentData?> startMultiPage(
    BuildContext context, {
    int maxPages = 0,
    List<String> ocrLanguages = const <String>['en', 'ar'],
    String palettePrimary = '#6448C3',
    String paletteOnPrimary = '#FFFFFF',
    String? locale,
    SupyDocumentScanIntent intent = SupyDocumentScanIntent.generic,
    bool autoCapture = false,
  }) {
    SupyLicenseGate.ensureActivated();
    final resolvedLocale =
        locale ??
        (Localizations.maybeLocaleOf(context)?.languageCode == 'ar'
            ? 'ar'
            : 'en');

    if (_useBrandedSession()) {
      return _startBranded(
        context,
        maxPages: maxPages,
        palettePrimary: palettePrimary,
        paletteOnPrimary: paletteOnPrimary,
        locale: resolvedLocale,
        autoCapture: autoCapture,
      );
    }

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

  /// The branded Flutter session covers all document capture on the two mobile
  /// targets, invoice included (server-side OCR is the source of truth, so the
  /// native on-device OCR + PDF path is no longer required). Web / desktop have
  /// no branded session yet and stay on the native full-screen scanner.
  static bool _useBrandedSession() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Pushes the branded session and bridges its callbacks to the route result.
  ///
  /// A per-capture [SupyDocumentScannerScreen.onError] is intentionally *not*
  /// wired to pop the route — a transient capture failure must not discard
  /// pages the user has already accepted. The user finishes with `Done` (→
  /// pages) or cancels (→ `null`), mirroring native's terminal outcomes.
  static Future<SupyDocumentData?> _startBranded(
    BuildContext context, {
    required int maxPages,
    required String palettePrimary,
    required String paletteOnPrimary,
    required String locale,
    required bool autoCapture,
  }) {
    final accent = _parseHexColor(palettePrimary);
    final onAccent = _parseHexColor(paletteOnPrimary);
    const base = SupyScannerPalette.supyDark();
    final palette =
        onAccent == null ? base : base.copyWith(onPrimary: onAccent);

    return Navigator.of(context).push<SupyDocumentData>(
      MaterialPageRoute<SupyDocumentData>(
        fullscreenDialog: true,
        builder:
            (routeContext) => SupyDocumentScannerScreen(
              maxPages: maxPages,
              mode: SupyDocumentScanMode.multi,
              locale: locale,
              palette: palette,
              accentColor: accent,
              guidance: SupyDocumentGuidanceConfiguration(
                autoCapture: autoCapture,
              ),
              onComplete:
                  (pages) => Navigator.of(
                    routeContext,
                  ).pop(SupyDocumentData(pages: pages, ocrText: '')),
              onCancel: () => Navigator.of(routeContext).pop(),
            ),
      ),
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
