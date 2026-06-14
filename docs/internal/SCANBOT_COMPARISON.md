# supy_scanner vs Scanbot SDK — Full Comparison

Internal reference for the retailer-app migration. The goal of `supy_scanner` is **drop-in replacement** of Scanbot at the call-site level — same API shape, no recurring license fee, smaller footprint, fully on-device.

---

## 1. At a glance

| | **Scanbot SDK** | **supy_scanner** |
|---|---|---|
| Vendor | scanbot.io (third-party) | First-party (Supy) |
| License | Commercial, per-app license key, scales with active devices | Proprietary internal, no per-device cost |
| Distribution | pub.dev (`scanbot_sdk`) + native AARs/frameworks | Git dep (`publish_to: none`) |
| iOS backend | Scanbot's proprietary native lib | AVFoundation + Vision + VisionKit (OS-native) |
| Android backend | Scanbot's proprietary native lib | CameraX + ML Kit (Barcode, Text Recognition v2) + GMS Document Scanner |
| Network in scan path | None (on-device), but license activation pings | None — fully offline |
| Binary footprint | Large (several MB of native libs per ABI) | Small (system frameworks + ML Kit modules) |
| iOS deployment target | iOS 13+ | iOS 16 |
| Android `minSdk` | 21 | 24 |
| Custom C++ core | No | Yes — `native/` shared by Android JNI, iOS Obj-C++, future `dart:ffi` |
| Symbology coverage | Broad (incl. MRZ, ID, medical) | v1: 1D + 2D commercial (QR, EAN, UPC, Code 39/93/128, ITF, PDF417, Data Matrix, Aztec) |
| OCR scripts | Many (incl. Arabic) | Latin only on Android (ML Kit limit); iOS Vision covers more, but parity is Latin |
| Document scanner UX | Scanbot's own UI | iOS: `VNDocumentCameraViewController`; Android: `GmsDocumentScanner` intent |
| Embedded preview | Yes | v1.1 onwards via `SupyBarcodeScannerView` PlatformView |

## 2. Cost & footprint

| Dimension | Scanbot | supy_scanner |
|---|---|---|
| Per-device license | Yes (recurring) | **None** |
| Activation telemetry | License-server ping | **None** |
| iOS framework size | Tens of MB | System frameworks (no shipped weight beyond Swift code) |
| Android `.aar` size | Tens of MB across ABIs | ML Kit modules only; native core is a small C++ lib |
| Build complexity | Adds licensed framework | CocoaPods + standard Gradle + CMake for shared core |

The recurring license cost is the headline reason for the rewrite. Everything else (smaller APK/IPA, no activation network call, no third-party vendor risk) is secondary upside.

## 3. Architecture

### Scanbot
- Black-box native frameworks per platform.
- Single Dart facade (`scanbot_sdk`).
- License initialization required before any scan call.
- UI either Scanbot-provided full-screen flows or composable widgets the SDK exposes.

### supy_scanner
- Ports-and-adapters. Flutter owns the public API and state; native modules own camera, detection, and OCR.
- Versioned `MethodChannel`: `io.supy.scanner/v1`. A v2 would be a parallel surface, never a breaking rename.
- Shared C++ core under `native/` — one source-of-truth for Android JNI + iOS Obj-C++ + future `dart:ffi`. Gated zxing-cpp integration on the Sprint 2 path.
- Errors surface as `PlatformException` → sealed `SupyScanError` variant on the result.
- No license init step. Camera permission is the only runtime gate.

## 4. API surface — drop-in compat

The migration path is **import-only**. The retailer app keeps its existing Scanbot call sites and swaps the import via the compat shim.

| Scanbot symbol | supy_scanner equivalent | Lives in |
|---|---|---|
| `BarcodeScanbotView` | `SupyBarcodeScannerView` | `lib/` (Supy name) + `compat/` (Scanbot alias) |
| `BarcodeScannerController` | `SupyBarcodeScannerController` | same |
| `BarcodeItem` | `SupyBarcode` | same |
| `InvoiceScannerService` | (re-exported from compat) | `compat/` only |
| `BarcodeFormat` enum | `SupyBarcodeFormat` | `lib/src/models/supy_barcode_format.dart` |
| `ScanResult` (sealed) | `SupyScanResult` variants: `SupyBarcode`, `SupyBatchBarcodeResult`, `SupyDocumentData`, `SupyScanError` | `lib/src/models/` |

Migration cookbook in `docs/MIGRATION.md`. The library itself NEVER uses Scanbot-named types — they live exclusively in `compat/supy_scanner_scanbot_compat/`. This keeps `lib/` clean while letting the retailer migrate one import line.

## 5. Feature coverage

| Feature | Scanbot | supy_scanner v1 | Notes |
|---|---|---|---|
| Single barcode | ✅ | ✅ | All commercial symbologies. |
| Batch / continuous barcode | ✅ | ✅ | Dedupe by payload + 800ms window. |
| QR | ✅ | ✅ | |
| 1D commercial (EAN/UPC/Code-128/…) | ✅ | ✅ | Matrix in `docs/SYMBOLOGIES.md`. |
| Data Matrix / PDF417 / Aztec | ✅ | ✅ | |
| Document scan + multi-page | ✅ | ✅ | iOS VisionKit / Android GMS scanner. |
| OCR (Latin) | ✅ | ✅ | |
| OCR (Arabic) | ✅ | ❌ (Android) / partial (iOS) | ML Kit limit on Android. Documented caveat. |
| MRZ / passport / ID | ✅ | ❌ | Out of v1 scope; not used by retailer. |
| Health card / check | ✅ | ❌ | Out of v1 scope. |
| Embedded PlatformView preview | ✅ | ✅ (v1.1) | `SupyBarcodeScannerView`. |
| AR overlay / find-and-pick UI | ✅ | ✅ | `SupyArOverlay`, `SupyFindAndPickSheet`. |
| Custom UI palettes | Limited | ✅ | `SupyScannerPalette`, `SupyTopBarConfiguration`, etc. — see `docs/UI_CONFIGURATION.md`. |
| Cloud OCR fallback | (available) | ❌ — by design | On-device only is a hard constraint. |

## 6. Platform requirements

| | Scanbot | supy_scanner |
|---|---|---|
| iOS min | 13 | **16** |
| Android `minSdk` | 21 | **24** |
| Android GMS | Optional | **Required** for document scanner (ML Kit barcode works without GMS but document scanner does not) |
| Camera permission | Required | Required (`SupyPermissions`) |
| Info.plist usage strings | `NSCameraUsageDescription` | `NSCameraUsageDescription` (same) |
| First-launch model download | None | ML Kit Document Scanner downloads ~10 MB once via Play services |

## 7. Threading

| | Scanbot | supy_scanner |
|---|---|---|
| iOS capture session | Opaque | Started/stopped on `DispatchQueue.global(qos: .userInitiated)` |
| iOS detection | Opaque | `VNRequest` on background queue, results marshalled to main at the FlutterResult boundary |
| Android camera | Opaque | `LifecycleCameraController` bound to host Activity lifecycle |
| Android detection | Opaque | Analyzer thread; main thread never blocks |

## 8. Risks vs Scanbot

| Risk vs Scanbot | Mitigation |
|---|---|
| Lose Scanbot's MRZ / ID-card support | Not currently used by retailer. Tracked as out-of-scope follow-up if a concrete need surfaces. |
| Arabic OCR gap on Android | Documented in `docs/MIGRATION.md`. Retailer flow that needs Arabic OCR has to stay on iOS or wait for a custom model. |
| GMS Document Scanner unavailable on non-Google Android (Huawei) | Documented requirement. Fallback to CameraX + ML Kit Text Recognition explored in Phase 5 if a customer reports it. |
| iOS 16 cuts off iOS 15 users | Retailer already targets iOS 15+. Confirmed acceptable. |
| Symbology drift between Vision and ML Kit | `docs/SYMBOLOGIES.md` enforces the parity matrix; the example app's test matrix is the regression gate. |
| Behavioral drift from Scanbot at migration | Compat shim + `docs/MIGRATION.md` cookbook + `docs/QA.md` per-phase walkthroughs. |

## 9. When to keep Scanbot

If a future app — not retailer — needs MRZ, passport, check, or health-card recognition, it should not adopt `supy_scanner` v1. Either:
- Add that capability to `supy_scanner` as a new phase (with a separate plan), or
- Keep Scanbot for that single app.

The retailer app is the only current consumer and does not use any of those features.

## 10. Migration status (as of 2026-06-13)

- **Sprint 1 (native core scaffold)**: in progress — V1-S1-09 device probe verification pending.
- **Sprint 1.5 (Scanbot-parity embedded UI)**: complete.
- **Sprint 2 (barcode pipeline lift, zxing-cpp)**: in progress.
- **Retailer cutover plan**: separate plan, kicks off after v1.0.0 tag.

See `TODO.md` for live sprint progress.
