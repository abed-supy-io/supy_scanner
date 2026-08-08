/// Drop-in compatibility shim that exposes Scanbot-named symbols
/// (`BarcodeScanbotView`, `BarcodeItem`, `BarcodeScannerController`,
/// `InvoiceScannerService`) backed by `supy_scanner`.
///
/// The goal is import-only migration: the retailer app can swap
/// `package:scanbot_sdk/scanbot_sdk.dart` and the retailer's local
/// `scanbot/scanbot_index.dart` import for this package and keep
/// compiling.
library;

export 'src/barcode_item.dart';
export 'src/barcode_scanbot_view.dart';
export 'src/invoice_scanner_service.dart';
