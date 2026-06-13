# Localization

`supy_scanner` ships **no user-facing strings** in its public surface. The
library treats locale as a wire value passed through to native frameworks,
which then render their own UI in the system language.

## Coverage matrix

| Surface | Owner | en | ar / RTL |
|---|---|---|---|
| Embedded barcode preview (`SupyBarcodeScannerView`) | Library — no chrome shipped. Host app supplies header/footer/error widgets. | host-controlled | host-controlled |
| Finder overlay (`_FinderPainter`) | Library — painted shapes only, no text. | n/a | n/a |
| Document scanner UI (iOS) | `VNDocumentCameraViewController` (system) | system | system |
| Document scanner UI (Android) | `GmsDocumentScanning` (system) | system | system |
| OCR engine | `VNRecognizeTextRequest` / ML Kit `TextRecognition` | en pack | ar pack |
| Permission denied placeholder | **Host app** via `SupyBarcodeScannerView.onError` callback | host | host |
| `SupyScanError.message` | Library — diagnostic only, never displayed to end users | en (technical) | en (technical) |

## Compat shim

`supy_scanner_scanbot_compat` is also string-free. `BarcodeScanbotView` no
longer renders its own AppBar — the host supplies the title chrome through
the `header` slot, identical to the pre-migration Scanbot usage.

## Locale plumbing

- `SupyDocumentScanOptions(locale: 'en' | 'ar')` is forwarded to the native
  channel. **Note:** on-device, both VisionKit and `GmsDocumentScanning`
  ignore the locale arg and use the system language — documented in
  `docs/MIGRATION.md`. The arg is accepted for source-compat with Scanbot.
- OCR language packs (`ocrLanguages`) DO take effect and select the
  recognition model.

## QA

`docs/QA.md §D5` exercises Arabic UI on a device set to Arabic locale.
`docs/QA.md §D7` exercises Arabic OCR. Both are device-required scenarios.

## Adding a string to the library

Don't. If new user-visible copy becomes unavoidable, route it through a
host-provided `Localizations` lookup or a builder callback — never embed it
in `lib/`.
