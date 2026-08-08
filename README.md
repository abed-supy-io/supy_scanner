# supy_scanner

A first-party Flutter scanning library for Supy. Native-backed (AVFoundation + Vision on iOS, ML Kit on Android) with **Scanbot-compatible APIs** so the retailer mobile app can swap dependencies without changing call sites.

> **Status:** v1.0.0 candidate. Library code and compat shim complete; perf and reliability harnesses authored; numbers + device sign-off pending.

## Why

The retailer app currently ships with **Scanbot SDK** — a paid third-party scanner. This package replaces it with a **first-party, Supy-licensed** scanner:

- **First-party licensing** — a Supy-issued license replaces Scanbot's per-seat SDK fee. See [Licensing](#licensing).
- **Smaller binary** — no ~50 MB native blob; built on Apple Vision + Google ML Kit.
- **Drop-in compatibility** — end users see no behavior change; call sites add a one-time `SupyScanner.activate(...)`.
- **On-device only** — no network calls in the scanning path. License checks are offline (signed-token verification); the network is touched once at activation, never per scan.

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

## Licensing

`supy_scanner` is a paid, Supy-licensed library. Scanning APIs are gated behind a
valid license: activate once at app startup, then every scan runs fully offline.

```dart
// Once, before the first scan (e.g. in main() or app bootstrap):
await SupyScanner.activate(licenseToken); // token issued by the licensing backend
```

- **Offline enforcement.** The token is an Ed25519 **signed license blob**. The
  library ships only the **public** verify key and checks the signature
  on-device — there is **no network call in the scanning path**. The network is
  touched exactly once, out-of-band, to obtain the token at activation.
- **What happens without a valid license.** Scan entry points
  (`scanDocument`, batch/multi sessions, etc.) throw until `activate` succeeds
  with an unexpired, correctly-signed token.
- **Getting a license.** Purchase a tier at the marketing site, then activate a
  device to receive its token. The issuing service lives in
  [`supy-licensing-backend/`](supy-licensing-backend/) (Stripe checkout →
  signed-token issuance → activation). It holds the **private** signing key;
  the library never does.

> This is a logged, intentional reversal of the library's original
> zero-license-cost mission — see the *Phase PAID* entry in the
> [`TODO.md`](TODO.md) decisions log.

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
- [`docs/HISTORY.md`](docs/HISTORY.md) — archived sprint plans and shipped design docs
- [`TODO.md`](TODO.md) — live tracker
- [`CHANGELOG.md`](CHANGELOG.md) — release notes

## Constraints

- No paid **third-party** SDK dependencies — the scanner is built on free
  platform frameworks. (The library itself is now a paid, Supy-licensed product;
  see [Licensing](#licensing) and the *Phase PAID* decision in [`TODO.md`](TODO.md).)
- No cloud OCR; no network calls in the scanning path. License verification is
  on-device; activation is the only out-of-band network call.
- The MethodChannel is versioned (`io.supy.scanner/v1`). A v2 means a parallel surface, not a breaking change.
