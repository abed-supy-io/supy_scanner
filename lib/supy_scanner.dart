/// First-party Flutter scanning library for Supy.
///
/// Provides native-backed barcode and document scanning with drop-in
/// Scanbot-compatible APIs. See `docs/MIGRATION.md` for the migration cookbook.
library supy_scanner;

export 'src/channel/supy_event_channel.dart';
export 'src/channel/supy_scanner_channel.dart';
export 'src/models/supy_barcode.dart';
export 'src/models/supy_barcode_format.dart';
export 'src/models/supy_batch_barcode_options.dart';
export 'src/models/supy_batch_barcode_result.dart';
export 'src/models/supy_document_data.dart';
export 'src/models/supy_document_page.dart';
export 'src/models/supy_scan_error.dart';
export 'src/models/supy_scan_options.dart';
export 'src/permissions/supy_permissions.dart' show SupyPermissions;
export 'src/widgets/supy_barcode_scanner_controller.dart'
    show SupyBarcodeScannerController;
export 'src/widgets/supy_barcode_scanner_view.dart'
    show SupyBarcodeScannerView, kDefaultBarcodeCooldown;
