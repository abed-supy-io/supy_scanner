# Symbology Matrix

`SupyBarcodeFormat` is the canonical Dart enum. Each value maps to a platform-native symbology on each side. Where a format isn't natively supported, the value is rejected at `setFormats` time with a `format_unsupported` error.

## Coverage

| `SupyBarcodeFormat` | iOS (Vision `VNBarcodeSymbology`) | Android (ML Kit `Barcode.FORMAT_*`) | Notes |
|---|---|---|---|
| `qr` | `.QR` | `FORMAT_QR_CODE` | Full support both sides. |
| `ean13` | `.EAN13` | `FORMAT_EAN_13` | Retailer's most common SKU scan. |
| `ean8` | `.EAN8` | `FORMAT_EAN_8` | |
| `upcA` | (derived via EAN-13 with leading zero) | `FORMAT_UPC_A` | iOS Vision returns UPC-A as EAN-13 with a `0` prefix — `SymbologyMapper.swift` strips it. |
| `upcE` | `.UPCE` | `FORMAT_UPC_E` | |
| `code39` | `.Code39` (+ `.Code39Checksum`, `.Code39FullASCII`) | `FORMAT_CODE_39` | |
| `code93` | `.Code93` (+ `.Code93i`) | `FORMAT_CODE_93` | |
| `code128` | `.Code128` | `FORMAT_CODE_128` | `minTextLen=5` from retailer is enforced in Dart filter, not native. |
| `itf` | `.I2of5` (+ `.ITF14`) | `FORMAT_ITF` | |
| `pdf417` | `.PDF417` | `FORMAT_PDF417` | |
| `dataMatrix` | `.DataMatrix` | `FORMAT_DATA_MATRIX` | |
| `aztec` | `.Aztec` | `FORMAT_AZTEC` | |
| `codabar` | `.Codabar` *(iOS 15+)* | `FORMAT_CODABAR` | Available, not currently used by retailer. |
| `all` | All of the above | `FORMAT_ALL_FORMATS` | Convenience value; native side enumerates explicitly to avoid surprise on new OS releases. |

## Rationale for the explicit `all` expansion

Both ML Kit and Vision auto-expand "all formats." We pin the list anyway:

1. Future OS updates won't quietly add new symbologies that affect retailer scanning behavior.
2. ML Kit's `FORMAT_ALL_FORMATS` ships heavier — on devices where on-demand format-specific models exist, listing only the formats we use reduces memory.
3. Cross-platform parity is easier to reason about and test.

## Behavior contract

- Calling `setFormats(formats: [])` is equivalent to `setFormats(formats: ['all'])`.
- Calling `setFormats` with a format unsupported on the current platform throws `format_unsupported` with the offending value in `message`.
- Detection results always carry the canonical `SupyBarcodeFormat` name (lowercase) regardless of platform-specific raw values.

## Out-of-scope symbologies (v1)

- **MRZ** (machine-readable zone on passports/IDs) — separate flow if ever needed.
- **RSS / DataBar** — ML Kit supports, Vision does not; would force cross-platform divergence.
- **Maxicode** — minimal retail use.

If any of these surface as a real requirement, add a row above, add the mapping in both `FormatMapper.kt` and `SymbologyMapper.swift`, add a fixture in the example app's symbology screen, and bump the package minor version.
