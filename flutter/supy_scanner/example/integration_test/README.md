# integration_test/ — supy_scanner

Per-use-case integration drivers for the example app. Established by H2-05.

## What runs where

| Surface | Native MethodChannel calls | Camera frames |
|---|---|---|
| `flutter test integration_test/` on host (no device) | throws `MissingPluginException` | n/a |
| `flutter test integration_test/` on Android emulator | ✅ resolves | ⚠️ needs camera-enabled AVD |
| `flutter test integration_test/` on iOS simulator | ✅ resolves | ⚠️ no real camera; preview is black |
| Physical Android / iOS device | ✅ | ✅ |

Tests are written so that the **navigation + page-mount path** runs headlessly (no native call until the user taps "Open scanner"). Anything that requires real native plugin resolution or camera frames is annotated `// device-only:` and gated behind `_runOnDevice` (see helper at the top of each file).

## Running

Headless smoke (CI-friendly — validates the drivers compile and the navigation graph wires up):

    cd example
    flutter test integration_test/

On a connected device or emulator (full path including native calls):

    cd example
    flutter test integration_test/ -d <device_id>

`flutter devices` lists available device IDs.

## Files

- `app_smoke_test.dart` — boots the example app, checks the demo home tiles render.
- `single_barcode_use_case_test.dart` — Scan Barcode (one-shot).
- `batch_barcode_use_case_test.dart` — Batch Count (multiple).
- `embedded_barcode_use_case_test.dart` — Live Camera (embedded `SupyBarcodeScannerView`).
- `document_use_case_test.dart` — Capture Document (multi-page + OCR).

## Adding a new use-case test

1. Add a new `<use_case>_use_case_test.dart` next to the others.
2. Mirror the structure of `single_barcode_use_case_test.dart`:
   - `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` at the top of `main()`.
   - Pump `SupyScannerExampleApp`, navigate via the demo home tile, assert the destination page widget mounted.
   - Gate camera/native-only assertions behind `_runOnDevice`.
3. Update `docs/QA.md` with a matching manual scenario row.
