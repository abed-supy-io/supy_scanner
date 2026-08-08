/// Canonical barcode symbology identifiers supported by [SupyBarcodeScannerView].
///
/// The native side maps each value to its platform-specific symbology — see
/// `docs/SYMBOLOGIES.md` for the full matrix.
enum SupyBarcodeFormat {
  /// Convenience value: enables every supported format on the current platform.
  all,

  /// QR Code (2D).
  qr,

  /// EAN-13 retail barcode.
  ean13,

  /// EAN-8 retail barcode.
  ean8,

  /// UPC-A retail barcode.
  upcA,

  /// UPC-E compressed retail barcode.
  upcE,

  /// Code 39 industrial barcode.
  code39,

  /// Code 93 high-density barcode.
  code93,

  /// Code 128 alphanumeric barcode.
  code128,

  /// ITF (Interleaved 2 of 5) barcode.
  itf,

  /// PDF417 stacked 2D barcode.
  pdf417,

  /// Data Matrix 2D barcode.
  dataMatrix,

  /// Aztec 2D barcode.
  aztec,

  /// Codabar barcode (legacy library / blood-bank usage).
  codabar,

  /// GS1 DataBar (RSS-14) linear barcode.
  ///
  /// Decodes only via the native zxing-cpp core (`useNativeCore: true`); the
  /// ML Kit and Vision platform decoders do not support it.
  dataBar,

  /// GS1 DataBar Expanded linear barcode.
  ///
  /// Decodes only via the native zxing-cpp core (`useNativeCore: true`); the
  /// ML Kit and Vision platform decoders do not support it.
  dataBarExpanded,

  /// Micro QR Code (2D).
  ///
  /// Decodes only via the native zxing-cpp core (`useNativeCore: true`); the
  /// ML Kit and Vision platform decoders do not support it.
  microQr,

  /// Rectangular Micro QR Code (rMQR, 2D).
  ///
  /// Decodes only via the native zxing-cpp core (`useNativeCore: true`); the
  /// ML Kit and Vision platform decoders do not support it.
  rMQR,

  /// MaxiCode (2D, UPS shipping).
  ///
  /// Decodes only via the native zxing-cpp core (`useNativeCore: true`); the
  /// ML Kit and Vision platform decoders do not support it.
  maxiCode;

  /// Wire-format name passed across the platform channel.
  ///
  /// Mirrors the enum name verbatim so `SupyBarcodeFormat.qr` ↔ `'qr'`.
  String get wireName => name;

  /// Parses a wire-format name back into the enum.
  ///
  /// Throws [ArgumentError] if [value] is not a recognized format.
  static SupyBarcodeFormat fromWireName(String value) {
    return SupyBarcodeFormat.values.firstWhere(
      (f) => f.name == value,
      orElse:
          () =>
              throw ArgumentError.value(
                value,
                'value',
                'Unknown SupyBarcodeFormat wire name',
              ),
    );
  }
}
