/// First-party Flutter scanning library for Supy.
///
/// Provides native-backed barcode and document scanning with drop-in
/// Scanbot-compatible APIs. See `docs/MIGRATION.md` for the migration cookbook.
library;

export 'src/barcode/parsers/supy_barcode_document_parser.dart'
    show SupyBarcodeParse;
export 'src/barcode/supy_barcode_scanner.dart' show SupyBarcodeScanner;
export 'src/channel/supy_datacapture_event_channel.dart';
export 'src/channel/supy_document_event_channel.dart';
export 'src/channel/supy_event_channel.dart';
export 'src/channel/supy_scanner_channel.dart';
export 'src/datacapture/supy_text_pattern_matcher.dart'
    show SupyTextPatternMatcher;
export 'src/document/supy_document_scanner.dart' show SupyDocumentScanner;
export 'src/document/supy_document_state_machine.dart'
    show SupyDocumentStateMachine;
export 'src/enhance/supy_document_enhance_mode.dart'
    show SupyDocumentEnhanceMode;
export 'src/enhance/supy_document_filter.dart' show SupyDocumentFilter;
export 'src/licensing/supy_license.dart'
    show
        SupyLicense,
        SupyLicenseErrorCode,
        SupyLicenseException,
        SupyLicenseTier;
export 'src/licensing/supy_license_verifier.dart'
    show SupyLicenseVerifier, kSupyLicensePublicKeyBase64;
export 'src/licensing/supy_scanner_license.dart' show SupyScanner;
export 'src/log/supy_log.dart'
    show
        SupyLog,
        SupyLogLevel,
        SupyLogRecord,
        SupyLogSink,
        SupyDebugPrintLogSink,
        SupyNullLogSink;
export 'src/models/barcode/supy_barcode_document.dart';
export 'src/models/barcode/supy_decode_image_options.dart'
    show SupyDecodeImageOptions;
export 'src/models/datacapture/supy_text_pattern.dart'
    show SupyTextPattern, SupyTextPatternScope;
export 'src/models/datacapture/supy_text_pattern_match.dart'
    show SupyTextPatternMatch;
export 'src/models/ocr/supy_id_document.dart'
    show SupyIdDocument, SupyIdDocumentType;
export 'src/models/ocr/supy_mrz_document.dart'
    show SupyMrzDocument, SupyMrzFormat, SupyMrzSex;
export 'src/models/ocr/supy_recognize_text_options.dart'
    show SupyRecognizeTextOptions;
export 'src/models/ocr/supy_recognized_text.dart'
    show SupyRecognizedText, SupyTextBlock, SupyTextElement, SupyTextLine;
export 'src/models/ocr/supy_vin.dart' show SupyVin, SupyVinSource;
export 'src/models/supy_barcode.dart';
export 'src/models/supy_barcode_format.dart';
export 'src/models/supy_batch_barcode_options.dart';
export 'src/models/supy_batch_barcode_result.dart';
export 'src/models/supy_document_data.dart';
export 'src/models/supy_document_frame_metrics.dart'
    show SupyDocumentFrameMetrics;
export 'src/models/supy_document_frame_state.dart'
    show SupyDocumentFrameState, SupyDocumentGuidanceFrame, SupyDocumentNudge;
export 'src/models/supy_document_page.dart';
export 'src/models/supy_document_scanner_backend.dart'
    show SupyDocumentScannerBackend;
export 'src/models/supy_scan_error.dart';
export 'src/models/supy_scan_options.dart';
export 'src/models/ui/supy_action_bar_configuration.dart'
    show SupyActionBarConfiguration, SupyActionButtonSpec;
export 'src/models/ui/supy_ar_overlay_configuration.dart'
    show SupyArOverlayConfiguration;
export 'src/models/ui/supy_camera_configuration.dart'
    show SupyCameraConfiguration, SupyScanRange;
export 'src/models/ui/supy_document_guidance_configuration.dart'
    show SupyDocumentGuidanceConfiguration, SupyDocumentGuidanceHints;
export 'src/models/ui/supy_find_and_pick_use_case_configuration.dart'
    show SupyExpectedBarcode, SupyFindAndPickUseCaseConfiguration;
export 'src/models/ui/supy_multiple_scan_use_case_configuration.dart'
    show SupyMultipleScanMode, SupyMultipleScanUseCaseConfiguration;
export 'src/models/ui/supy_scan_use_case.dart'
    show
        SupyFindAndPickUseCase,
        SupyMultipleScanUseCase,
        SupyScanUseCase,
        SupySingleScanUseCase;
export 'src/models/ui/supy_scanner_palette.dart' show SupyScannerPalette;
export 'src/models/ui/supy_scanner_strings.dart' show SupyScannerStrings;
export 'src/models/ui/supy_single_scan_use_case_configuration.dart'
    show SupySingleScanUseCaseConfiguration;
export 'src/ocr/id/supy_id_parser.dart' show SupyIdParser;
export 'src/ocr/mrz/supy_mrz_parser.dart' show SupyMrzParser, SupyRecognizeMrz;
export 'src/ocr/vin/supy_vin_parser.dart'
    show SupyBarcodeVin, SupyRecognizeVin, SupyVinParser;
export 'src/permissions/supy_permissions.dart' show SupyPermissions;
export 'src/widgets/supy_ar_overlay.dart' show SupyArOverlay;
export 'src/widgets/supy_barcode_scanner_controller.dart'
    show SupyBarcodeScannerController, SupyCameraPosition;
export 'src/widgets/supy_barcode_scanner_screen.dart'
    show SupyBarcodeScannerScreen;
export 'src/widgets/supy_barcode_scanner_view.dart'
    show SupyBarcodeScannerView, kDefaultBarcodeCooldown;
export 'src/widgets/supy_document_scanner_controller.dart'
    show
        SupyDocumentCapture,
        SupyDocumentCapturePhase,
        SupyDocumentScannerController;
export 'src/widgets/supy_document_scanner_screen.dart'
    show SupyDocumentScannerScreen;
export 'src/widgets/supy_document_scanner_view.dart'
    show SupyDocumentCountdownRing, SupyDocumentScannerView;
export 'src/widgets/supy_find_and_pick_accumulator.dart'
    show SupyFindAndPickAccumulator, SupyFindAndPickRow;
export 'src/widgets/supy_find_and_pick_sheet.dart' show SupyFindAndPickSheet;
export 'src/widgets/supy_multiple_scan_accumulator.dart'
    show SupyMultipleScanAccumulator, SupyMultipleScanItem;
export 'src/widgets/supy_multiple_scan_sheet.dart' show SupyMultipleScanSheet;
export 'src/widgets/supy_single_scan_confirmation_sheet.dart'
    show SupySingleScanConfirmationSheet;
export 'src/widgets/supy_text_pattern_scanner_controller.dart'
    show SupyTextPatternScannerController;
export 'src/widgets/supy_text_pattern_scanner_view.dart'
    show SupyTextPatternScannerView, kDefaultTextPatternCooldown;
