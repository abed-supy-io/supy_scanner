/// First-party Flutter scanning library for Supy.
///
/// Provides native-backed barcode and document scanning with drop-in
/// Scanbot-compatible APIs. See `docs/MIGRATION.md` for the migration cookbook.
library supy_scanner;

export 'src/channel/supy_document_event_channel.dart';
export 'src/channel/supy_event_channel.dart';
export 'src/channel/supy_scanner_channel.dart';
export 'src/document/supy_document_state_machine.dart'
    show SupyDocumentStateMachine;
export 'src/models/supy_barcode.dart';
export 'src/models/supy_barcode_format.dart';
export 'src/models/supy_batch_barcode_options.dart';
export 'src/models/supy_batch_barcode_result.dart';
export 'src/models/supy_document_data.dart';
export 'src/models/supy_document_frame_metrics.dart'
    show SupyDocumentFrameMetrics;
export 'src/models/supy_document_frame_state.dart'
    show SupyDocumentFrameState, SupyDocumentGuidanceFrame;
export 'src/models/supy_document_page.dart';
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
export 'src/models/ui/supy_single_scan_use_case_configuration.dart'
    show SupySingleScanUseCaseConfiguration;
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
export 'src/widgets/supy_document_scanner_view.dart'
    show SupyDocumentCountdownRing, SupyDocumentScannerView;
export 'src/widgets/supy_find_and_pick_accumulator.dart'
    show SupyFindAndPickAccumulator, SupyFindAndPickRow;
export 'src/widgets/supy_find_and_pick_sheet.dart' show SupyFindAndPickSheet;
export 'src/widgets/supy_multiple_scan_accumulator.dart'
    show SupyMultipleScanAccumulator, SupyMultipleScanItem;
export 'src/widgets/supy_multiple_scan_sheet.dart'
    show SupyMultipleScanSheet;
export 'src/widgets/supy_single_scan_confirmation_sheet.dart'
    show SupySingleScanConfirmationSheet;
