import Vision

/// Bidirectional mapper between Dart `SupyBarcodeFormat` wire names and
/// `VNBarcodeSymbology`.
///
/// Wire names are the camelCase enum names produced by Dart
/// (`SupyBarcodeFormat.wireName`). Keep this table in sync with
/// `docs/SYMBOLOGIES.md` and the Android `FormatMapper.kt`.
enum SymbologyMapper {

  /// Translates wire names to the symbology list passed to
  /// `VNDetectBarcodesRequest.symbologies`.
  ///
  /// Returns `nil` when the caller has asked for `all` (or no specific
  /// formats), signalling that we should fall back to Vision's default
  /// (every supported symbology).
  static func toVisionSymbologies(
    _ wireFormats: [String]
  ) -> [VNBarcodeSymbology]? {
    if wireFormats.isEmpty || wireFormats.contains("all") {
      return nil
    }
    let values = wireFormats.flatMap { wireToVision($0) }
    return values.isEmpty ? nil : values
  }

  /// Maps a Dart wire name to one or more Vision symbologies.
  ///
  /// `itf` covers both `i2of5` and `itf14` on Vision.
  /// `upcA` requires special handling at the emission site — Vision returns
  /// UPC-A barcodes as `.ean13` with a leading `0`, so we always request
  /// `.ean13` for `upcA` and disambiguate in detection emission.
  private static func wireToVision(_ wire: String) -> [VNBarcodeSymbology] {
    switch wire {
    case "qr": return [.qr]
    case "ean13": return [.ean13]
    case "ean8": return [.ean8]
    case "upcA": return [.ean13]
    case "upcE": return [.upce]
    case "code39": return [.code39]
    case "code93": return [.code93]
    case "code128": return [.code128]
    case "itf": return [.i2of5, .itf14]
    case "pdf417": return [.pdf417]
    case "dataMatrix": return [.dataMatrix]
    case "aztec": return [.aztec]
    case "codabar": return [.codabar]
    // Unsupported on the Vision path — these decode only via the native
    // zxing-cpp core (`useNativeCore`). Returning [] drops them from the
    // Vision symbology request. See docs/SYMBOLOGIES.md.
    case "dataBar", "dataBarExpanded", "microQr", "rMQR", "maxiCode":
      return []
    default: return []
    }
  }

  /// Inverse of `wireToVision` — used when emitting detection events.
  /// `payload` is supplied so we can disambiguate UPC-A (13-digit EAN-13
  /// starting with `0`) from genuine EAN-13.
  static func visionToWire(
    _ symbology: VNBarcodeSymbology,
    payload: String?
  ) -> String {
    switch symbology {
    case .qr: return "qr"
    case .ean13:
      if let p = payload, p.count == 13, p.first == "0" {
        return "upcA"
      }
      return "ean13"
    case .ean8: return "ean8"
    case .upce: return "upcE"
    case .code39: return "code39"
    case .code93: return "code93"
    case .code128: return "code128"
    case .i2of5, .itf14: return "itf"
    case .pdf417: return "pdf417"
    case .dataMatrix: return "dataMatrix"
    case .aztec: return "aztec"
    case .codabar: return "codabar"
    default: return "all"
    }
  }
}
