import 'package:flutter/material.dart';

import 'catalog_entry.dart';
import 'demos/ar_overlay_demo.dart';
import 'demos/barcode_parsers_demo.dart';
import 'demos/batch_scan_demo.dart';
import 'demos/branded_document_demo.dart';
import 'demos/decode_image_demo.dart';
import 'demos/document_scan_demo.dart';
import 'demos/embedded_scanner_demo.dart';
import 'demos/id_compose_demo.dart';
import 'demos/licensing_demo.dart';
import 'demos/log_hud_demo.dart';
import 'demos/mrz_parser_demo.dart';
import 'demos/native_core_demo.dart';
import 'demos/permissions_demo.dart';
import 'demos/smart_document_demo.dart';
import 'demos/text_pattern_demo.dart';
import 'demos/text_recognition_demo.dart';
import 'demos/theming_demo.dart';
import 'demos/use_cases_demo.dart';
import 'demos/vin_parser_demo.dart';

/// The single source of truth for the example catalog.
///
/// Every public `supy_scanner` API area appears here exactly once. The home
/// screen groups these by [CatalogEntry.category]; there is no other list to
/// keep in sync. Add a feature => add one row here.
final List<CatalogEntry> kCatalogEntries = [
  // ---- Barcode ---------------------------------------------------------
  CatalogEntry(
    category: CatalogCategory.barcode,
    icon: Icons.crop_free,
    title: 'Embedded scanner view',
    description:
        'Drop the live camera preview into your own layout and receive '
        'detections via a callback.',
    apiSummary: 'SupyBarcodeScannerView + SupyBarcodeScannerController',
    builder: (_) => const EmbeddedScannerDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.barcode,
    icon: Icons.qr_code_scanner,
    title: 'Scan use-cases',
    description:
        'Full-screen scanner with the five Scanbot-parity use-cases: single, '
        'immediate, counting, unique, find-and-pick.',
    apiSummary: 'SupyBarcodeScannerScreen(useCase:, palette:)',
    builder: (_) => const UseCasesDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.barcode,
    icon: Icons.dynamic_feed,
    title: 'Batch scan',
    description:
        'Scan many codes in one session; get back the deduplicated set with a '
        'duplicate count.',
    apiSummary: 'SupyBarcodeScanner.startMultiple → SupyBatchBarcodeResult',
    builder: (_) => const BatchScanDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.barcode,
    icon: Icons.center_focus_strong,
    title: 'AR overlay',
    description:
        'Paint bounding boxes over the live preview for every detected '
        'barcode.',
    apiSummary: 'SupyArOverlay over SupyBarcodeScannerView',
    builder: (_) => const ArOverlayDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.barcode,
    icon: Icons.image_search,
    title: 'Decode from image',
    description:
        'Decode a still image on disk instead of the live camera — the '
        'deterministic path.',
    apiSummary: 'SupyScannerChannel.decodeImage(SupyDecodeImageOptions)',
    builder: (_) => const DecodeImageDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.barcode,
    icon: Icons.account_tree,
    title: 'Barcode parsers',
    description:
        'Interpret decoded payloads as typed documents: Wi-Fi, vCard, URL, '
        'GS1 and more.',
    apiSummary: 'SupyBarcode.parseDocument() → SupyBarcodeDocument?',
    builder: (_) => const BarcodeParsersDemo(),
  ),

  // ---- Document --------------------------------------------------------
  CatalogEntry(
    category: CatalogCategory.document,
    icon: Icons.document_scanner,
    title: 'Document scan',
    description:
        'Detect edges, correct perspective, filter, and return cropped page '
        'images plus OCR text.',
    apiSummary: 'SupyScannerChannel.scanDocument → SupyDocumentData',
    builder: (_) => const DocumentScanDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.document,
    icon: Icons.auto_awesome,
    title: 'Smart document (live guidance)',
    description:
        'Embed the live document camera with auto-snap: real-time coaching '
        'hints, a guidance state machine, and manual capture fallback.',
    apiSummary: 'SupyDocumentScannerView + SupyDocumentGuidanceConfiguration',
    builder: (_) => const SmartDocumentDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.document,
    icon: Icons.fullscreen,
    title: 'Branded document scanner',
    description:
        'The full-screen, Scanbot-parity document session: solid brand bars, a '
        'live green/red edge overlay, an in-bar auto-capture toggle, gallery '
        'import, and a multi-page review grid.',
    apiSummary: 'SupyDocumentScannerScreen(onComplete:, onCancel:)',
    builder: (_) => const BrandedDocumentDemo(),
  ),

  // ---- OCR & Text ------------------------------------------------------
  CatalogEntry(
    category: CatalogCategory.ocr,
    icon: Icons.text_snippet,
    title: 'Text recognition (OCR)',
    description:
        'Run OCR over a captured page and inspect the block → line → element '
        'tree.',
    apiSummary: 'SupyScannerChannel.recognizeText → SupyRecognizedText',
    builder: (_) => const TextRecognitionDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.ocr,
    icon: Icons.directions_car,
    title: 'VIN parser',
    description:
        'Parse and validate a 17-character Vehicle Identification Number, '
        'incl. the check-digit.',
    apiSummary: 'SupyVinParser.parse → SupyVin',
    builder: (_) => const VinParserDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.ocr,
    icon: Icons.badge,
    title: 'MRZ parser',
    description:
        'Parse the machine-readable zone of passports and ID cards (TD1 / TD3) '
        'with checksum validation.',
    apiSummary: 'SupyMrzParser.parse → SupyMrzDocument',
    builder: (_) => const MrzParserDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.ocr,
    icon: Icons.contact_page,
    title: 'ID compose',
    description:
        'Merge MRZ, barcode and front-of-card sources into one unified '
        'identity document.',
    apiSummary: 'SupyIdParser.compose → SupyIdDocument',
    builder: (_) => const IdComposeDemo(),
  ),

  // ---- Data Capture ----------------------------------------------------
  CatalogEntry(
    category: CatalogCategory.dataCapture,
    icon: Icons.pattern,
    title: 'Text pattern scanner',
    description:
        'Live-scan the camera for text matching regex patterns — emails, URLs, '
        'SKUs, anything.',
    apiSummary: 'SupyTextPatternScannerView(patterns: [SupyTextPattern])',
    builder: (_) => const TextPatternDemo(),
  ),

  // ---- Advanced --------------------------------------------------------
  CatalogEntry(
    category: CatalogCategory.advanced,
    icon: Icons.palette,
    title: 'Theming & localization',
    description:
        'Rebrand and localize every scanner surface via a palette and a '
        'strings bundle (incl. Arabic / RTL).',
    apiSummary: 'SupyScannerPalette · SupyScannerStrings',
    builder: (_) => const ThemingDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.advanced,
    icon: Icons.workspace_premium,
    title: 'Licensing',
    description:
        'The Phase PAID on-device license gate — inspect the active license '
        'and toggle the gate.',
    apiSummary: 'SupyScanner.activate / isActivated / license',
    builder: (_) => const LicensingDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.advanced,
    icon: Icons.photo_camera,
    title: 'Camera permission',
    description:
        'Pre-flight camera access and branch on the four-state permission '
        'result.',
    apiSummary: 'SupyPermissions.requestCamera → SupyCameraPermissionStatus',
    builder: (_) => const PermissionsDemo(),
  ),

  // ---- Dev / QA --------------------------------------------------------
  CatalogEntry(
    category: CatalogCategory.devQa,
    icon: Icons.memory,
    title: 'Native core probe',
    description:
        'Round-trip a call to the native side and report its version / ABI — '
        'a plugin health check.',
    apiSummary: 'SupyScannerChannel.nativeCoreProbe → SupyNativeCoreProbe',
    builder: (_) => const NativeCoreDemo(),
  ),
  CatalogEntry(
    category: CatalogCategory.devQa,
    icon: Icons.terminal,
    title: 'Logging & debug HUD',
    description:
        'Emit structured SupyLog records and tail them on-device via the '
        'in-app debug HUD.',
    apiSummary: 'SupyLog.debug/info/warn/error · SupyDebugHud',
    builder: (_) => const LogHudDemo(),
  ),
];

/// [kCatalogEntries] grouped by [CatalogCategory], preserving declaration order
/// within each group and skipping categories with no entries.
Map<CatalogCategory, List<CatalogEntry>> catalogByCategory() {
  final map = <CatalogCategory, List<CatalogEntry>>{};
  for (final entry in kCatalogEntries) {
    map.putIfAbsent(entry.category, () => []).add(entry);
  }
  return map;
}
