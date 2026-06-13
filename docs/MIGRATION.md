# Migration — Scanbot → supy_scanner

> Drop-in cookbook for the retailer mobile app. The goal: **end users see no difference**. Every Scanbot call site has a one-to-one replacement with the same arguments, the same defaults, and the same visible behavior.

## TL;DR

1. Replace `package:scanbot_sdk/scanbot_sdk.dart` imports with `package:supy_scanner/supy_scanner.dart` (or with the compat shim for zero call-site churn — see below).
2. Rename `BarcodeScanbotView` → `SupyBarcodeScannerView`, `BarcodeItem` → `SupyBarcode`, `DocumentData` → `SupyDocumentData`.
3. Delete Scanbot license-key initialization. `supy_scanner` needs no key.
4. Verify iOS host app has `NSCameraUsageDescription` in `Info.plist` (already present for Scanbot — no change needed).

If using the compat shim package `supy_scanner_scanbot_compat`, only **step 1** is required and only the import line changes.

---

## Call-site mapping

The retailer app has four touch-points with Scanbot. Each one maps as follows:

### 1. Embedded barcode widget

**Before** (`core/services/scanbot/barcode_scanbot_view.dart` consumers):

```dart
BarcodeScanbotView(
  controller: barcodeController,
  onBarcodeDetected: (List<BarcodeItem> barcodes) async { ... },
  header: const _ScanHeader(),
  footer: const _ScanFooter(),
  useScanWindow: true,
  findBarcodeAtCenter: true,
  scanWindow: const Rect.fromLTWH(0.1, 0.35, 0.8, 0.3),
)
```

**After:**

```dart
SupyBarcodeScannerView(
  controller: barcodeController,
  onBarcodeDetected: (List<SupyBarcode> barcodes) async { ... },
  header: const _ScanHeader(),
  footer: const _ScanFooter(),
  useScanWindow: true,
  findBarcodeAtCenter: true,
  scanWindow: const Rect.fromLTWH(0.1, 0.35, 0.8, 0.3),
)
```

Identical prop names. Same 2-second cooldown enforced by the controller. Same yellow 5px finder border with 20px radius (re-implemented in Dart on top of the PlatformView).

### 2. Barcode controller

**Before:**

```dart
final controller = BarcodeScannerController();
controller.pause();
controller.resume();
controller.toggle();
final paused = controller.isPaused;
```

**After:**

```dart
final controller = SupyBarcodeScannerController();
controller.pause();
controller.resume();
controller.toggle();
final paused = controller.isPaused;
```

Identical surface. `SupyBarcodeScannerController` extends `ChangeNotifier` and exposes the same methods.

### 3. Document scanning service (`invoice_scanner_service.dart`)

**Before:**

```dart
abstract class IInvoiceScannerService {
  Future<List<File>> scanWithCamera(BuildContext context);
}

class InvoiceScannerService implements IInvoiceScannerService {
  @override
  Future<List<File>> scanWithCamera(BuildContext context) async {
    final result = await startMultiPageScanning(context);
    return _parseScanResult(result);
  }
  // ...
}
```

**After:**

```dart
abstract class IInvoiceScannerService {
  Future<List<File>> scanWithCamera(BuildContext context);
}

class InvoiceScannerService implements IInvoiceScannerService {
  @override
  Future<List<File>> scanWithCamera(BuildContext context) async {
    final result = await SupyDocumentScanner.startMultiPage(
      context,
      maxPages: 0, // 0 = unlimited (matches Scanbot pagesScanLimit=0)
      ocrLanguages: const ['en', 'ar'],
      paletteOnPrimary: '#FFFFFF',
      palettePrimary: '#6448C3',
      locale: Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en',
    );
    return result?.pages.map((p) => File(p.uri.replaceFirst('file://', ''))).where((f) => f.existsSync()).toList() ?? [];
  }
}
```

The `IInvoiceScannerService` interface is **unchanged** — every consumer (`features/invoice/...`) keeps calling `scanWithCamera(context)` and gets back `List<File>`. Only the internal implementation swaps.

### 4. Localized strings (`ScanbotStrings`)

The retailer's `ScanbotStrings` class can be kept verbatim. `supy_scanner` accepts a `locale` parameter and the host app passes through its own translated guidance strings via `SupyDocumentScanOptions.userGuidance`:

```dart
SupyDocumentScanOptions(
  userGuidance: SupyUserGuidance(
    tooDark: ScanbotStrings.get('tooDark'),
    tooSmall: ScanbotStrings.get('tooSmall'),
    noDocumentFound: ScanbotStrings.get('noDocumentFound'),
  ),
);
```

On iOS, VisionKit owns the guidance strings (system-localized); the `userGuidance` overrides apply on Android only — but the iOS VisionKit strings are already correctly localized for `en` and `ar`, so behavior is parity.

### 5. License check

**Before:** `checkLicenseStatus(context)` showed a dialog if the Scanbot trial expired.

**After:** delete `checkLicenseStatus` entirely. No license. The dialog and the `ScanbotSdk.getLicenseInfo()` call go away.

### 6. SDK initialization

**Before** (`scanbot_sdk_manager.dart`):

```dart
await ScanbotSdk.initialize(documentScannerConfig);
```

**After:** optional, only for warm-up:

```dart
await SupyDocumentScanner.prewarm();
```

This downloads the GMS Document Scanner model on Android if it hasn't been fetched yet. Safe to call multiple times; safe to omit (the model will download on first scan).

---

## Compatibility shim — zero call-site churn

For teams that want to migrate import-only, the `supy_scanner_scanbot_compat` package exports type aliases:

```dart
// In supy_scanner_scanbot_compat/lib/supy_scanner_scanbot_compat.dart:
export 'package:supy_scanner/supy_scanner.dart';

typedef BarcodeScanbotView      = SupyBarcodeScannerView;
typedef BarcodeItem             = SupyBarcode;
typedef BarcodeScannerController = SupyBarcodeScannerController;
typedef DocumentData            = SupyDocumentData;
typedef ScanbotColor            = SupyColor; // hex-string wrapper
```

Then the retailer's existing files compile unchanged — only the import line at the top swaps:

```dart
// Before:
import 'package:scanbot_sdk/scanbot_sdk.dart';

// After:
import 'package:supy_scanner_scanbot_compat/supy_scanner_scanbot_compat.dart';
```

The shim is provided as a transitional courtesy. The recommendation is to rename to the canonical `Supy*` types within one or two sprints after cutover and then drop the shim dependency.

---

## Host-app config — what stays, what changes

| Item | Before (Scanbot) | After (supy_scanner) |
|---|---|---|
| `Info.plist` `NSCameraUsageDescription` | Required | Required (no change) |
| Android `minSdk` | 21 | 24 (CameraX + ML Kit) |
| iOS deployment target | 13.0 | **16.0** (Vision barcode + VisionKit document) |
| `pubspec.yaml` dep | `scanbot_sdk` | `supy_scanner` (git ref or internal pub) |
| License key in env / build flavor | Required | Removed |
| Native podfile additions | Scanbot pods | None — supy_scanner pulls Apple frameworks only |
| Android proguard | Scanbot rules | None needed (ML Kit handles its own) |

**iOS deployment target jump from 13 to 16** is the only host-app constraint to verify with the mobile lead before cutover. Confirm retailer-app analytics show <1% iOS 15 fleet (Phase 0 gate).

---

## Cutover checklist (for a future migration PR)

This is **not** scope for the supy_scanner package itself — it's the consumer-side checklist the retailer-app team will follow when cutover happens.

- [ ] Bump retailer iOS target to 16 (or define a fallback strategy).
- [ ] Add `supy_scanner` to `apps/retailer/pubspec.yaml`.
- [ ] Add `supy_scanner_scanbot_compat` (transitional) OR rename call sites directly.
- [ ] Replace `barcode_scanbot_view.dart` body with thin wrapper over `SupyBarcodeScannerView` (or delete and import the Supy view directly at the four feature pages).
- [ ] Replace `InvoiceScannerService` body per section 3 above.
- [ ] Delete `scanbot_sdk_manager.dart`, license-key env vars, and `checkLicenseStatus`.
- [ ] Remove `scanbot_sdk` from `pubspec.yaml`.
- [ ] Run QA matrix from `docs/QA.md`.
- [ ] Ship behind a feature flag for first 1–2 releases; remove flag once metrics confirm parity.
