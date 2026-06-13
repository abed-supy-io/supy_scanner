---
name: add-symbology
description: Use when adding or modifying a barcode symbology (format) in supy_scanner — keeps the Dart enum, both native mappers, the symbology doc, and the example-app fixture in lockstep.
---

# Add a barcode symbology

A symbology change touches **five files**. Skipping any one of them produces silent platform drift. Follow in order.

## Checklist (create TodoWrite items for each)

1. **Dart enum** — add the value to `lib/src/models/supy_barcode_format.dart`. Use lowercase camelCase (`code128`, not `CODE_128`). The canonical name surfaced in detection results must match this enum name.

2. **Symbology matrix doc** — add a row to `docs/SYMBOLOGIES.md` with:
   - Canonical Dart name
   - iOS `VNBarcodeSymbology` (or "not supported")
   - Android ML Kit `Barcode.FORMAT_*`
   - Notes (length constraints, prefix quirks, etc.)

3. **Android mapping** — `android/src/main/kotlin/io/supy/scanner/barcode/FormatMapper.kt`. Add to the bi-directional `Supy ↔ ML Kit` map. If the format is not supported by ML Kit, throw a `format_unsupported` PlatformException with the offending value in the message.

4. **iOS mapping** — `ios/Classes/barcode/SymbologyMapper.swift`. Add to the bi-directional `Supy ↔ VNBarcodeSymbology` map. Same rule for unsupported.

5. **Example-app fixture** — add a row to the symbology screen with a printable barcode image so QA can verify the round-trip on real hardware.

## Tests

- Update the channel-mock unit test that asserts `setFormats` round-trips canonical names.
- Update `docs/SYMBOLOGIES.md`'s "Behavior contract" section if the new format has quirky length / prefix rules.

## Verification

- `dart analyze && dart test` clean.
- Print the barcode. Run the example app on one Android and one iPhone. Confirm it scans and the result's `format` field matches the canonical Dart name.

## Don't

- Don't add a format only on one platform. If a symbology is supported on Android but not iOS (or vice versa), still add the enum value but make the unsupported side throw `format_unsupported` — never silently swallow it.
- Don't re-use existing enum names with new meanings. Add a new value.
