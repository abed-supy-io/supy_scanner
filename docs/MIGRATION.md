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

## v1.1 Performance — advisory events (additive, opt-in)

`v1.1.0` adds two event families to the existing barcode EventChannel payload. **Both are advisory** — the existing Scanbot-parity call sites work unchanged if the consumer ignores them. The library still pauses analyzer work, drops idle frames, and tier-adapts resolution/FPS internally regardless of whether the host listens.

| Event payload | When emitted | Consumer action (optional) |
|---|---|---|
| `{type: 'thermal', state: <nominal\|light\|fair\|moderate\|serious\|critical>, paused: bool, throttled: bool}` | On thermal-state transition (Android API 29+ `PowerManager.OnThermalStatusChangedListener`; iOS `ProcessInfo.thermalStateDidChangeNotification`). | Show a toast / banner. When `paused=true`, the analyzer is stopped — surface "Device too hot, scanning paused" to avoid the user thinking the camera is broken. |
| `{type: 'idle_pause'}` / `{type: 'idle_resume'}` | Luma-variance gate flips state (only on MID/LOW tiers — HIGH opts out). | Usually ignore. A debug overlay can show "idle — waiting for motion" to explain why decode stopped without crashing. |
| `{type: 'torch_idle_suggested'}` | Emitted alongside `idle_pause` when the torch is currently on. Advisory only — native does NOT toggle the torch off automatically. | Consumer may choose to call `setTorch(false)` to save battery, or prompt the user. Safe to ignore — torch stays on otherwise. |

These events flow through the same EventChannel as `barcode_detected` payloads — discriminate on `type`. The current Scanbot consumers (which only listen for `barcode_detected`) will silently drop these and continue to work.

**Tier resolution** (`SupyDeviceTier.detect()` on each platform) is internal — it is not exposed through the public Dart surface and cannot be overridden from the host. QA verifies tier behavior by running on the four reference devices listed in `docs/PERFORMANCE.md`.

---

## Scanbot RTU-UI → supy_scanner mapping

Scanbot's Ready-To-Use (RTU) UI exposes a `BarcodeScannerConfiguration` with sub-configurations (top bar, action bar, view finder, user guidance, use-case mode, AR overlay, palette). `supy_scanner` v1.1 mirrors the same axes through `SupyBarcodeScannerScreen` + per-layer `Supy*Configuration` value types. See `docs/UI_CONFIGURATION.md` for the per-knob catalog.

| Scanbot RTU concept | `supy_scanner` equivalent | Notes |
|---|---|---|
| `BarcodeScannerConfiguration` | `SupyBarcodeScannerScreen` (full-screen widget) | Composite over `SupyBarcodeScannerView` + sheet layers. |
| `Palette` | `SupyScannerPalette` | 16 tokens; `scanbotDark()` / `scanbotLight()` const factories match RTU defaults. |
| `TopBarConfiguration` | `SupyTopBarConfiguration` | `solid` / `gradient` styles, cancel icon + tooltip. |
| `ActionBarConfiguration` (flash / zoom / flip-camera / close-focus) | `SupyActionBarConfiguration` + `SupyActionButtonSpec` | Each button individually toggle-able; wired to `SupyBarcodeScannerController`. |
| `ViewFinderConfiguration` (cornered frame + dim overlay) | `SupyViewFinderConfiguration` + `SupyFinderPainter` | `CustomPainter`-based; no PlatformView dependency. |
| `UserGuidanceConfiguration` | `SupyUserGuidanceConfiguration` | Pill-shaped guidance card. |
| `ArOverlayConfiguration` | `SupyArOverlayConfiguration` + `SupyArOverlay` | RRect bounding boxes + label chips over normalized `[0..1]` coordinates from native. |
| `CameraConfiguration` (zoom, AF, scan range) | `SupyCameraConfiguration` (`initialZoom`, `minFocusDistanceLock`, `scanRange`) | Set via `SupyBarcodeScanOptions.camera`. `scanRange = extended` engages the v1.1 native core when `useNativeCore: true`. |
| `SingleScanningMode` (+ confirmation sheet) | `SupySingleScanUseCase` + `SupySingleScanUseCaseConfiguration` | `confirmationSheetEnabled: false` matches RTU's "no confirmation" toggle. |
| `MultipleScanningMode` — counting | `SupyMultipleScanUseCase(config: ..., mode: counting)` + `SupyMultipleScanAccumulator` | `countingRepeatDelay` debounces identical successive scans. |
| `MultipleScanningMode` — unique | `SupyMultipleScanUseCase(config: ..., mode: unique)` | Default. |
| `FindAndPickScanningMode` | `SupyFindAndPickUseCase` + `SupyFindAndPickUseCaseConfiguration` (pick-list of `SupyExpectedBarcode`) | Submit gated on `SupyFindAndPickAccumulator.isComplete`. `allowUnexpected: true` surfaces non-list scans as warnings. |
| `Localization` strings | Pass strings via the relevant `Supy*Configuration` constructor | See `docs/LOCALIZATION.md`. No global locale registry; consumer-owned. |

What does **not** map 1:1:

- Scanbot's per-screen `Localization` registry is not reproduced — every label is a direct field on its config (`SupyTopBarConfiguration.cancelTooltip`, sheet button texts, etc.). Cleaner for type-checking; the migration cost is a one-time `flutter intl`-style sweep on the consumer side.
- Scanbot's "use case modes" enum is replaced by a Dart 3 sealed class (`SupyScanUseCase`). Switching modes at runtime means rebuilding the screen with a different variant — there is no setter-based mode swap. This is intentional: pattern-switching the sealed variant gives compile-time exhaustiveness in the result-callback wiring.
- Scanbot's image-result event (returning a JPEG of the captured frame) is not part of v1.1 — `SupyBarcode` returns `rawValue` + `format` + optional normalized bounding box only. File-frame capture is on the v1.2 backlog.

---

## Scanbot document → supy_scanner v1.1 field mapping

Sprint 7 (v1.1) widens the document result surface. The table below maps Scanbot's `DocumentQuality` + `DocumentFileFormat` axes onto the Supy equivalents — consumers porting from Scanbot's RTU document scanner can read this row-by-row.

| Scanbot concept | `supy_scanner` equivalent | Notes |
|---|---|---|
| `DocumentQuality.VERY_POOR` (1) | `SupyDocumentPageQuality.veryPoor` | Bucket order matches; integer mapping `1..5` is internal only — Supy uses the named enum on the wire. |
| `DocumentQuality.POOR` (2) | `SupyDocumentPageQuality.poor` | — |
| `DocumentQuality.REASONABLE` (3) | `SupyDocumentPageQuality.ok` | Renamed — `ok` reads better than `reasonable` at call sites. |
| `DocumentQuality.GOOD` (4) | `SupyDocumentPageQuality.good` | — |
| `DocumentQuality.EXCELLENT` (5) | `SupyDocumentPageQuality.excellent` | — |
| `DocumentQuality` raw float (where exposed) | `SupyDocumentPage.qualityScore` (0..1) | Supy normalizes to `[0..1]`; the enum is derived from this score via fixed bucket thresholds (`<0.2`, `<0.4`, `<0.6`, `<0.8`, `≥0.8`). |
| `DocumentFileFormat.JPG` | `SupyDocumentOutputFormat.jpg` | Default — preserves v1.0 behaviour. `SupyDocumentScanOptions.jpegQuality` still applies. |
| `DocumentFileFormat.PNG` | `SupyDocumentOutputFormat.png` | Lossless. `jpegQuality` is ignored. |
| `DocumentFileFormat.PDF` | `SupyDocumentOutputFormat.pdf` | Pages still persist individually (as JPG); the assembled multi-page PDF URI is surfaced on `SupyDocumentData.pdfUri`. |
| `Document.pdfUrl` | `SupyDocumentData.pdfUri` | `null` when `outputFormat` is not `pdf`. File URI (`file:///...`), not HTTP. |
| Scanbot `acceptedAngleScore` / `acceptedSizeScore` gates | Not exposed (yet) | The native scorer drives a single `qualityScore`; per-axis gating is on the v1.2 backlog. |

Forward-compat note: unknown `quality` wire strings from a newer native side deserialize to `null` rather than throwing — older Dart clients continue to work against newer native cores.

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
