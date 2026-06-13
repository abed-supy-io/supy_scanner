# supy_scanner

A first-party Flutter scanning library for Supy. Native-backed (AVFoundation + Vision on iOS, ML Kit on Android) with **Scanbot-compatible APIs** so the retailer mobile app can swap dependencies without changing call sites.

> **Status:** v1.0.0 candidate. Library code and compat shim complete; perf and reliability harnesses authored; numbers + device sign-off pending.

## Why

The retailer app currently ships with **Scanbot SDK** — a paid third-party scanner. This package replaces it with:

- **Zero recurring license cost** — Apple Vision + Google ML Kit are free.
- **Smaller binary** — no ~50 MB native blob.
- **Drop-in compatibility** — end users see no behavior change.
- **On-device only** — no network calls in the scanning path.

## Install

```yaml
dependencies:
  supy_scanner:
    git:
      url: git@github.com:supy-io/supy-scanner.git
      ref: v1.0.0
```

Platform setup:

- **iOS:** Deployment target ≥ 16. Add `NSCameraUsageDescription` to `Info.plist`.
- **Android:** `minSdk` ≥ 21. The plugin's manifest already declares `android.permission.CAMERA`. Google Play Services required for document scanning.

## Quickstart

### Embedded barcode preview

```dart
SupyBarcodeScannerView(
  controller: controller,
  options: const SupyBarcodeScanOptions(
    formats: {SupyBarcodeFormat.qr, SupyBarcodeFormat.ean13},
  ),
  onBarcodeDetected: (SupyBarcode b) async {
    // b.rawValue, b.format
  },
  header: const Text('Scan'),
  footer: const ManualEntryButton(),
);
```

### Document + OCR

```dart
final result = await SupyScannerChannel.instance.scanDocument(
  const SupyDocumentScanOptions(maxPages: 10, locale: 'en'),
);
if (result != null) {
  for (final page in result.pages) {
    // page.uri (file://...), page.ocrText
  }
}
```

### Batch barcode session

```dart
final batch = await SupyScannerChannel.instance.scanBarcodesBatch(
  const SupyBatchBarcodeScanOptions(maxBatchCount: 20),
);
```

## Drop-in compatibility

The retailer call sites pre-migration:

```dart
BarcodeScanbotView(controller: c, onBarcodeDetected: (List<BarcodeItem> bs) async {...}, header: ..., footer: ...);
final pages = await invoiceScannerService.scanWithCamera(context); // List<File>
```

The compat shim `supy_scanner_scanbot_compat` preserves these exact signatures so the cutover is an import-only change. See [`compat/supy_scanner_scanbot_compat/`](compat/supy_scanner_scanbot_compat/) and [`docs/MIGRATION.md`](docs/MIGRATION.md).

## Documentation

- [`docs/PLAN.md`](docs/PLAN.md) — delivery plan, phases, risks, verification
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — modules, MethodChannel contract, PlatformView pipeline
- [`docs/MIGRATION.md`](docs/MIGRATION.md) — Scanbot ↔ supy_scanner API mapping
- [`docs/SYMBOLOGIES.md`](docs/SYMBOLOGIES.md) — iOS Vision ↔ Android ML Kit symbology matrix
- [`docs/LOCALIZATION.md`](docs/LOCALIZATION.md) — string ownership + en/ar coverage
- [`docs/QA.md`](docs/QA.md) — acceptance scenarios + performance targets
- [`docs/SPRINTS.md`](docs/SPRINTS.md) — sprint breakdown
- [`TODO.md`](TODO.md) — live tracker
- [`CHANGELOG.md`](CHANGELOG.md) — release notes

## Constraints

- No paid SDK dependencies.
- No cloud OCR; no network calls in the scanning path.
- The MethodChannel is versioned (`io.supy.scanner/v1`). A v2 means a parallel surface, not a breaking change.
