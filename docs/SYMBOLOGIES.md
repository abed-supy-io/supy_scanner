# Barcode symbologies

The canonical list of barcode formats `supy_scanner` exposes, and how each maps
onto the three decode backends. This table is the source of truth referenced by
`CLAUDE.md`, the `supy-scanner:add-symbology` skill, and `docs/MIGRATION.md`.

Keep it in sync with, in the same PR:

- `lib/src/models/supy_barcode_format.dart` — the `SupyBarcodeFormat` enum.
- `android/src/main/kotlin/io/supy/scanner/barcode/FormatMapper.kt` — ML Kit + `SUPY_FORMAT_*` mask.
- `ios/Classes/barcode/SymbologyMapper.swift` — Vision symbologies.
- `native/include/supy_scanner_core.h` — the `SUPY_FORMAT_*` bit definitions.

## Decode backends

| Backend | Platform | Notes |
|---|---|---|
| **ML Kit** | Android | Default Android decoder (`useNativeCore: false`). |
| **Vision** | iOS | Default iOS decoder (`VNDetectBarcodesRequest`). |
| **zxing-cpp core** | Android + iOS | Shared C++ core, opt-in via `useNativeCore: true` (gated on `SUPY_WITH_ZXING_CPP`). |

## Matrix

Legend: ✅ decodes · ✚ decodes with corner geometry via libdmtx assist · ❌ not supported by that backend.

| `SupyBarcodeFormat` | wire name | `SUPY_FORMAT_*` bit | ML Kit | Vision | zxing-cpp core |
|---|---|---|---|---|---|
| `qr` | `qr` | `QR_CODE` (10) | ✅ | ✅ | ✅ |
| `ean13` | `ean13` | `EAN_13` (7) | ✅ | ✅ | ✅ |
| `ean8` | `ean8` | `EAN_8` (6) | ✅ | ✅ | ✅ |
| `upcA` | `upcA` | `UPC_A` (11) | ✅ | ✅¹ | ✅ |
| `upcE` | `upcE` | `UPC_E` (12) | ✅ | ✅ | ✅ |
| `code39` | `code39` | `CODE_39` (2) | ✅ | ✅ | ✅ |
| `code93` | `code93` | `CODE_93` (3) | ✅ | ✅ | ✅ |
| `code128` | `code128` | `CODE_128` (4) | ✅ | ✅ | ✅ |
| `itf` | `itf` | `ITF` (8) | ✅ | ✅² | ✅ |
| `pdf417` | `pdf417` | `PDF_417` (9) | ✅ | ✅ | ✅ |
| `dataMatrix` | `dataMatrix` | `DATA_MATRIX` (5) | ✅ | ✅ | ✚ |
| `aztec` | `aztec` | `AZTEC` (0) | ✅ | ✅ | ✅ |
| `codabar` | `codabar` | `CODABAR` (1) | ✅ | ✅ | ✅ |
| `dataBar` | `dataBar` | `DATA_BAR` (13) | ❌ | ❌ | ✅ |
| `dataBarExpanded` | `dataBarExpanded` | `DATA_BAR_EXPANDED` (14) | ❌ | ❌ | ✅ |
| `microQr` | `microQr` | `MICRO_QR` (15) | ❌ | ❌ | ✅ |
| `rMQR` | `rMQR` | `RMQR` (16) | ❌ | ❌ | ✅ |
| `maxiCode` | `maxiCode` | `MAXI_CODE` (17) | ❌ | ❌ | ✅ |

¹ Vision returns UPC-A as a 13-digit `.ean13` with a leading `0`; disambiguated
at the emission site in `SymbologyMapper.visionToWire`.

² `itf` maps to both `.i2of5` and `.itf14` on Vision.

## Native-core-only formats

`dataBar`, `dataBarExpanded`, `microQr`, `rMQR`, and `maxiCode` are decoded
**only** by the zxing-cpp core. On the ML Kit / Vision platform paths they are
dropped from the symbology request, so a scan configured with only these
formats and `useNativeCore: false` will never match. Consumers that need them
must pass `useNativeCore: true`. This is documented for migrating call sites in
`docs/MIGRATION.md`.

## Not supported by any backend

These Scanbot symbologies are decodable by **none** of the three backends in the
stack (zxing-cpp, ML Kit, Vision) and are therefore not offered. Requesting them
surfaces as a `format_unsupported` gap, not a silent no-op:

- Code 11
- MSI Plessey
- Pharmacode
- Postal codes (USPS Intelligent Mail, Royal Mail, Australia Post, etc.)
