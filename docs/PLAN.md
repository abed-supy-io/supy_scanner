# supy_scanner — Delivery Plan

## 1. Context

Supy's retailer app uses **Scanbot SDK** for barcode and document scanning. Scanbot is paid, per-app licensed, and bundles ~50 MB of native code per platform.

We are replacing it with **`supy_scanner`**, a Supy-owned Flutter package backed by:

- **iOS:** AVFoundation, Vision, VisionKit (built into iOS 13+).
- **Android:** Google ML Kit (Barcode, Text Recognition v2) + GMS Document Scanner.

**Hard requirement (stakeholder, 2026-06-13):** drop-in compatibility with the retailer app's existing Scanbot call sites — end users must see no behavioral difference.

### Current Scanbot surface (must be matched)

**Barcode — embedded `BarcodeScanbotView` widget** (`apps/retailer/lib/core/services/scanbot/barcode_scanbot_view.dart`)
- `onBarcodeDetected: Future<void> Function(List<BarcodeItem> barcodes)`
- Slots: `header`, `footer`
- Config: `useScanWindow`, `scannerBoxBuilder`, `findBarcodeAtCenter`, `scanWindow`
- `BarcodeScannerController` exposing `pause()`, `resume()`, `toggle()`, `isPaused`
- 2-second cooldown between scans, paused-overlay on detection
- Native UX: yellow finder rectangle, torch toggle, "Scan Barcode" app bar, tap-to-select overlay (iOS only today)
- Symbology config: `BarcodeFormatCommonConfiguration` (stripCheckDigits=false, minTextLen=3), Code128 minTextLen=5
- Engine mode used: `NEXT_GEN_LOW_POWER_FAR_DISTANCE`

**Document scan — service-style API** (`apps/retailer/lib/features/invoice/services/invoice_scanner_service.dart`)
- `InvoiceScannerService.scanWithCamera(BuildContext) -> Future<List<File>>`
- Underlying: `startMultiPageScanning(context) -> Future<DocumentData?>`
- `DocumentData.pages[].documentImageURI` → `File` on disk
- Multi-page, manual + auto snap, review/crop/rotate/reorder/delete screens
- Localized in Arabic + English (`ScanbotStrings`)
- Brand: primary color `#6448C3`, on-primary `#FFFFFF`

**Other call sites:**
- `features/inventory/.../scan_barcode_counting_page.dart` (batch-style stock count)
- `features/inventory/.../assign_barcode_page.dart` (single barcode → item)
- `features/packaging/.../create_new_package_screen.dart` (barcode-in-form)

## 2. Goals & Non-Goals

### Goals
1. Pub-installable `supy_scanner` package with drop-in–compatible APIs.
2. Feature parity:
   - **Embedded** barcode scanner widget with header/footer slots, pause/resume, finder, torch.
   - Multi-page document scanner returning `List<File>`.
   - Multi-language OCR (English + Arabic at minimum).
3. Zero paid third-party SDK dependencies.
4. Compatibility shim package (`supy_scanner_scanbot_compat`) so retailer flips a single import.
5. Bench-proven perf: ≤ Scanbot scan latency on equivalent hardware.
6. CI for analyze + test + iOS/Android example build on every PR.

### Non-Goals (v1)
- MRZ / passport / ID-card / check / health-card recognition (not used by retailer today).
- Web/desktop platforms.
- Cloud OCR fallback.
- Image filter pipeline beyond default document enhancement.

## 3. High-Level Architecture

Ports-and-adapters with a versioned platform seam.

```
supy_scanner/
├── lib/                                         ← Dart public API
│   ├── supy_scanner.dart                        ← barrel export
│   └── src/
│       ├── models/
│       │   ├── supy_barcode.dart                ← drop-in shape for BarcodeItem
│       │   ├── supy_barcode_format.dart
│       │   ├── supy_document_data.dart          ← drop-in shape for DocumentData
│       │   ├── supy_scan_options.dart
│       │   └── supy_scan_error.dart
│       ├── channel/
│       │   ├── method_channel.dart              ← MethodChannel('io.supy.scanner/v1')
│       │   └── event_channel.dart               ← EventChannel for continuous detection stream
│       ├── widgets/
│       │   ├── supy_barcode_scanner_view.dart   ← PlatformView host + controller
│       │   ├── supy_barcode_scanner_controller.dart
│       │   └── supy_scanner_finder_overlay.dart
│       └── services/
│           ├── supy_document_scanner.dart       ← static entrypoint matching scanning_bot.dart
│           └── supy_permissions.dart
├── android/src/main/kotlin/io/supy/scanner/
│   ├── SupyScannerPlugin.kt                     ← FlutterPlugin + MethodCallHandler
│   ├── barcode/
│   │   ├── BarcodeScannerView.kt                ← PlatformView (CameraX + ML Kit analyzer)
│   │   ├── BarcodeScannerViewFactory.kt
│   │   └── FormatMapper.kt
│   ├── document/
│   │   ├── DocumentScannerLauncher.kt           ← GmsDocumentScanner intent
│   │   └── OcrRunner.kt                         ← ML Kit Text Recognition over JPEGs
│   └── util/
├── ios/Classes/
│   ├── SupyScannerPlugin.swift
│   ├── barcode/
│   │   ├── BarcodeScannerPlatformView.swift     ← FlutterPlatformView (AVCaptureSession + Vision)
│   │   ├── BarcodeScannerViewFactory.swift
│   │   └── SymbologyMapper.swift
│   ├── document/
│   │   ├── DocumentScannerPresenter.swift       ← VNDocumentCameraViewController
│   │   └── OcrRunner.swift                      ← VNRecognizeTextRequest
│   └── Util/
├── example/                                     ← Flutter sample app / QA harness
├── compat/
│   └── supy_scanner_scanbot_compat/             ← shim package: re-exports as Scanbot names
├── docs/
└── .github/workflows/ci.yml
```

### MethodChannel + EventChannel contract

`io.supy.scanner/v1` (MethodChannel)

| Method | Args | Returns |
|---|---|---|
| `scanDocument` | `{ maxPages, ocrLanguages[], jpegQuality, locale, palettePrimary, paletteOnPrimary }` | `{ pages: [{ uri, width, height }], ocrText }` |
| `prewarm` | — | `{}` (downloads ML Kit Document Scanner model on Android) |
| `requestCameraPermission` | — | `{ status }` |

`io.supy.scanner/v1/barcode/<viewId>` (EventChannel per PlatformView)

Streams `{ type: 'detection', items: [{ rawValue, format, boundingBox }] }` and `{ type: 'error', code, message }`.

`io.supy.scanner/v1/barcode/<viewId>` also accepts host-→native calls via the MethodChannel for: `pause`, `resume`, `setTorch`, `setFormats`.

### Public Dart API (frozen for v1)

```dart
// ───── models ─────
final class SupyBarcode {
  final String rawValue;
  final SupyBarcodeFormat format;
  final Rect? boundingBox;
  const SupyBarcode({required this.rawValue, required this.format, this.boundingBox});
}

enum SupyBarcodeFormat { all, qr, ean13, ean8, upcA, upcE, code39, code93, code128, itf, pdf417, dataMatrix, aztec, unknown }

final class SupyDocumentPage {
  final String documentImageURI;          // file:// URI on disk
  final int width;
  final int height;
}

final class SupyDocumentData {
  final List<SupyDocumentPage> pages;
  final String? ocrText;
}

// ───── embedded barcode widget ─────
class SupyBarcodeScannerController {
  Future<void> pause();
  Future<void> resume();
  Future<void> toggle();
  Future<void> setTorch(bool on);
  ValueListenable<bool> get isPaused;
  ValueListenable<bool> get flashAvailable;
}

class SupyBarcodeScannerView extends StatefulWidget {
  const SupyBarcodeScannerView({
    super.key,
    required this.onBarcodeDetected,
    this.controller,
    this.header,
    this.footer,
    this.useScanWindow = true,
    this.findBarcodeAtCenter = true,
    this.scannerBoxBuilder,
    this.scanWindow,
    this.formats = const [SupyBarcodeFormat.all],
    this.cooldown = const Duration(seconds: 2),
    this.minimumTextLength = 3,
  });

  final Future<void> Function(List<SupyBarcode> barcodes) onBarcodeDetected;
  final SupyBarcodeScannerController? controller;
  final Widget? header;
  final Widget? footer;
  final bool useScanWindow;
  final bool findBarcodeAtCenter;
  final Widget Function(bool isActive)? scannerBoxBuilder;
  final Rect? scanWindow;
  final List<SupyBarcodeFormat> formats;
  final Duration cooldown;
  final int minimumTextLength;
}

// ───── document scan ─────
abstract class SupyDocumentScanner {
  static Future<SupyDocumentData?> startMultiPage(BuildContext context, {SupyDocumentOptions options});
  static Future<void> prewarm();
}

abstract class ISupyInvoiceScannerService {
  Future<List<File>> scanWithCamera(BuildContext context);
}
```

## 4. Phased Roadmap

Five phases, ~9 weeks elapsed. Each phase is independently demo-able.

### Phase 0 — Foundations (1 week)
Scaffold the package, CI, example app shell, frozen API types, and PlatformView/MethodChannel bridges that compile but no-op.

**Exit:**
- `flutter pub get` works for the package + example app.
- iOS and Android builds green in CI.
- Public API surface compiles (with `UnimplementedError` bodies).
- Channel contract documented in `docs/ARCHITECTURE.md`.

### Phase 1 — Embedded Barcode Scanner, Android-first (2 weeks)
This is the riskiest piece. PlatformView + CameraX + ML Kit analyzer + finder overlay + torch + pause/resume + 2s cooldown.

**Tasks**
- `BarcodeScannerView.kt` — `PlatformView` wrapping `PreviewView`.
- `BarcodeScanning.getClient(...)` analyzer attached to CameraX `ImageAnalysis`.
- `EventChannel` streaming detections.
- `MethodChannel` accepting pause/resume/torch/setFormats per-view.
- Symbology mapping (ML Kit `Barcode.FORMAT_*` ↔ `SupyBarcodeFormat`).
- Min-text-length filter and dedupe with cooldown (mirror current 2s).
- Finder rectangle: native overlay (yellow 5px border, 20px radius) **plus** Flutter widget passthrough (`scannerBoxBuilder`).
- Center-detection mode (`findBarcodeAtCenter`).
- Tap-to-select bounding-box overlay (parity with current iOS-only feature, ship it on both).
- Dart `SupyBarcodeScannerView` widget composing `AndroidView` + header/footer Stack.

**Exit:**
- Drop the widget into the example app, scan a Code-128 and a QR on a physical Android device.
- Pause/resume from the controller works; torch toggles.
- Header/footer Flutter widgets render on top of the camera preview.

### Phase 2 — Embedded Barcode Scanner, iOS (1.5 weeks)
Mirror Phase 1 on iOS using `AVCaptureSession` + `VNDetectBarcodesRequest` + a `UIView` wrapped as `FlutterPlatformView`.

**Tasks**
- `BarcodeScannerPlatformView.swift` — wraps `AVCaptureVideoPreviewLayer`.
- `VNDetectBarcodesRequest` with `symbologies` set from options.
- Symbology mapping (`VNBarcodeSymbology` ↔ `SupyBarcodeFormat`).
- Torch toggle via `AVCaptureDevice`.
- EventChannel + MethodChannel parity with Android.
- iOS Info.plist `NSCameraUsageDescription` documented in `docs/MIGRATION.md`.

**Exit:**
- Identical Dart API behavior on iPhone and Android device.
- Symbology matrix (`docs/SYMBOLOGIES.md`) published.

### Phase 3 — Document Scanner + OCR (2 weeks)
Multi-page scan returning `SupyDocumentData` (with file URIs) on both platforms, plus OCR text concat.

**Tasks**
- **Android:** `GmsDocumentScanner` intent (JPEG result format, page limit, gallery import). Save JPEGs to app cache, return `file://` URIs. Run `TextRecognition.getClient(...)` over each JPEG, concatenate.
- **iOS:** `VNDocumentCameraViewController` → write each page as JPEG to `NSTemporaryDirectory()`, return `file://` URIs. Per-page `VNRecognizeTextRequest` with `recognitionLevel = .accurate` and `recognitionLanguages = [<options>]`.
- Locale-aware UI strings (English + Arabic for v1 — port the existing `ScanbotStrings` map verbatim).
- Brand palette wired through (primary `#6448C3`, on-primary `#FFFFFF`).
- `prewarm()` method that triggers ML Kit Document Scanner model download up front.
- `SupyDocumentScanner.startMultiPage(...)` + a `SupyInvoiceScannerService` implementing the same interface as today's `IInvoiceScannerService`.

**Exit:**
- Scan a 5-page invoice in the example app on both platforms.
- `List<File>` returned, all files exist on disk.
- Arabic OCR returns recognizable Arabic strings.

### Phase 4 — Compat Shim + Drop-in Verification (1 week)
Build `supy_scanner_scanbot_compat` so retailer can adopt with minimal churn.

**Tasks**
- Type aliases (`typedef BarcodeItem = SupyBarcode`) — but only where the public Scanbot API contract is reasonably stable.
- Widget alias `BarcodeScanbotView` → `SupyBarcodeScannerView` translating prop names.
- `IInvoiceScannerService` implementation backed by `SupyDocumentScanner`.
- Local fork-test: copy retailer call sites into the example app, swap imports, confirm zero call-site changes needed.
- A `MIGRATION.md` cookbook with side-by-side diffs.

**Exit:**
- All four call sites in retailer compile against the shim with only the import line changed.
- Side-by-side video recording: Scanbot vs supy_scanner on the same flow shows no visible difference to a user.

### Phase 5 — Hardening, Docs, v1.0.0 (1.5 weeks)
- Bench scenarios (see Verification).
- Memory profile a 10-page scan loop (50 iterations) — no leak.
- Threading review: ensure detector runs off main thread on both platforms.
- Cancellation paths: backgrounding, screen rotation, navigator pop.
- Finalize all docs.
- Tag `v1.0.0`, push to internal pub registry / pin git SHA.

**Exit:**
- v1.0.0 tagged.
- Sign-off from mobile lead + QA.
- Retailer cutover plan unblocked.

### Sprint mapping (2-week sprints)

| Sprint | Calendar wks | Phases |
|---|---|---|
| Sprint 1 | wks 1–2 | Phase 0 + start of Phase 1 |
| Sprint 2 | wks 3–4 | Finish Phase 1 + Phase 2 |
| Sprint 3 | wks 5–6 | Phase 3 |
| Sprint 4 | wks 7–8 | Phase 4 + Phase 5 (first half) |
| Buffer | wk 9 | Phase 5 finish, regression, v1.0.0 |

Detailed ticket-level breakdown lives in [`docs/SPRINTS.md`](SPRINTS.md).

### Post-v1.0 — v1.1 Performance workstream

Full plan: [`docs/PERFORMANCE.md`](PERFORMANCE.md). Lands on top of v1.0.0 as `v1.1.x` — no public API changes, additive EventChannel payloads only (`thermal`, `idle_pause`, `idle_resume`, `torch_idle_suggested`). Decision: ships as **v1.1**, not deferred to v1.2 — the Moto G Power floor is the binding constraint for the retailer cutover and the same release that turns the library on by default should hit it.

| Phase | Status | Surface |
|---|---|---|
| P1 — DeviceTier + tier-adaptive analyzer | ✅ done | `perf/SupyDeviceTier`, analyzer resolution/FPS caps |
| P2 — ThermalGovernor + thermal events | ✅ done | `perf/ThermalGovernor` + `perf/SupyThermalGovernor`; `{type:'thermal'}` event |
| P3 — Idle pause (luma variance) | ✅ done | `perf/IdleDetector` + `perf/SupyIdleDetector`; `{type:'idle_pause'\|'idle_resume'}` events |
| P3.5 — Torch-idle advisory | ✅ done | `{type:'torch_idle_suggested'}` event emitted alongside `idle_pause` when torch is on; consumer-driven (library never toggles torch) |
| P4 — OCR downscale + per-page memory budget | ✅ done | Tier-tiered long-edge downscale (HIGH uncapped / MID 1600 / LOW 1280) before recognition; tier-aware JPEG quality |
| P5 — Hardening + sign-off | pending | Re-bench on Moto G Power / Pixel 8 / SE 3 / 15 Pro; tag `v1.1.0` |

### v1.2 — Active phases

v1.2 inherits the same constraints as v1.1: drop-in compatibility, on-device only, no paid SDK dep, channel stays at `io.supy.scanner/v1` unless a surface genuinely breaks.

#### Phase CXD — CameraX document fallback (non-GMS Android)

Replaces the current `model_unavailable` failure on non-GMS Android devices (Huawei, AOSP, locked-down enterprise images) with a first-party CameraX-backed document capture flow. **Auto-detected** via `GoogleApiAvailability` at call-time — no public API change. Pages flow through the existing `OcrRunner` so OCR coverage is unchanged.

| Sub-phase | Status | Scope |
|---|---|---|
| CXD1 — Availability gate | pending | `GmsAvailability` helper wraps `GoogleApiAvailability.isGooglePlayServicesAvailable`. `DocumentScannerLauncher.launch` branches before touching the GMS client; existing GMS path unchanged when available. |
| CXD2 — CameraX capture Activity | pending | New `CameraXDocumentScannerActivity` (manual capture UX): preview + tap-to-capture button + page-thumbnail strip + retake/delete + done. Returns JPEG URIs back to `DocumentScannerLauncher` via `ActivityResultLauncher`. No edge detection in v1.2 — auto-snap is a v1.3 candidate. |
| CXD3 — OCR + JPEG pipeline reuse | pending | Captured frames re-encoded via existing `JpegReencoder` (tier-aware quality) and fed to `OcrRunner`. No new OCR code. |
| CXD4 — Permission + cancel paths | pending | Camera permission via existing `SupyPermissions`. User back/cancel → resolves `scanDocument` with `[]` (matches D4 in QA.md). Permission denied → `permission_denied`. |
| CXD5 — Docs + QA | pending | `docs/CAMERAX_FALLBACK.md` design doc; `docs/ARCHITECTURE.md` Android module table row; `docs/QA.md` adds D12 (Huawei/AOSP fallback path) + revises D10 (GMS-unavailable no longer fails; now exercises the new path). |
| CXD6 — Sign-off | pending | Manual walkthrough on one non-GMS device (Huawei P30 or emulator with GMS stripped); D1/D2/D4/D10/D12 all pass; tag `v1.2.0`. |

**Exit:** `SupyDocumentScanner.startMultiPage` succeeds on a non-GMS device; result shape identical to GMS path; retailer code is unchanged.

#### Post-v1.2 — candidates

Scope sketch only — nothing ships until promoted.

| Candidate | Why | Promotion gate |
|---|---|---|
| **MRZ / ID-card recognition** | Out-of-Scope §3 today — Scanbot specialty we don't currently use. | Concrete product ask from retailer or another internal app. |
| **Image-filter pipeline for document enhancement (B&W, color, perspective polish)** | Out-of-Scope §5. Scanbot exposes these knobs; not yet needed. | Retailer-side UX feedback after v1.1 cutover shows OCR quality gap. |
| **Reliability stress harness in CI** | Mentioned in v1.0 sign-off pending list. Currently a manual Instruments / Profiler pass; would catch leak regressions earlier. | Bench-rig automation available on CI runners. |
| **Tier debug override** | `debugForceTier` was speculatively documented then removed in v1.1 because no surface existed. If QA churn around tier behavior recurs, expose a `SupyScanOptions.debugForceTier: SupyDeviceTier?` (debug builds only). | A second perf bug where reproducing requires forcing tier on a flagship. |

Anything we add to this list crosses a phase boundary and updates `docs/PLAN.md`, `TODO.md`, and the relevant phase doc in `docs/`.

## 5. Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | PlatformView lifecycle bugs (camera not releasing on pop) | High | High | Treat Phase 1 as a spike; write a stress test in the example app that opens/closes the scanner 100x. |
| R2 | GMS Document Scanner unavailable on non-Google Android (Huawei, AOSP) | Medium | Medium | Document GMS requirement; Phase 5 evaluates CameraX + custom edge-detect fallback. |
| R3 | ML Kit model download (~10 MB) on first document scan | Medium | Low | `prewarm()` API + retailer calls it on app start. |
| R4 | Symbology drift between Vision and ML Kit | Medium | Medium | Phase 2 publishes `docs/SYMBOLOGIES.md`; cross-platform integration test in example app. |
| R5 | Visible UX regression vs Scanbot (worse autosnap, different finder) | High | High | Phase 4 side-by-side recording with mobile lead before tagging v1.0.0. |
| R6 | Arabic OCR quality below Scanbot | Medium | Medium | Benchmark on 5 real retailer invoices; if regression > 20%, escalate before cutover. |
| R7 | iOS minimum deployment target jump (iOS 13 → 16 if we use newer Vision features) | Low | Medium | Confirm retailer's current iOS floor in Phase 0; stay on iOS 13 APIs where possible. |
| R8 | PlatformException semantics differ across platforms | Low | Low | Standardized error codes (`cancelled`, `permission_denied`, `camera_unavailable`, `model_unavailable`, `unknown`). |

## 6. Verification

Each phase exits only when its checklist passes. v1.0.0 ships only after the **acceptance bench** passes:

1. **Functional parity (Phase 4 acceptance)**
   - All retailer call sites compile against the compat shim with only the import changed.
   - Side-by-side video on three flows (stock count, assign barcode, scan invoice) — no visible UX regression.

2. **Performance bench (Phase 5)** — measured on Moto G Power (5th gen) and iPhone SE 3:
   - QR scan latency: p50 < 300 ms, p95 < 800 ms.
   - 10-page document scan + OCR: < 12 s end-to-end on iPhone SE 3.
   - Stock-count batch: 20 unique barcodes in < 30 s, zero duplicates in result.
   - Memory: ≤ 80 MB working set during continuous barcode detection.

3. **Reliability**
   - Stress test: 100 open/close cycles of the embedded barcode view — no native leak (verified via Xcode Instruments and Android Studio Profiler).
   - 50-iteration document scan loop — no temp-file accumulation > 200 MB.

4. **Static checks**
   - `dart analyze` zero warnings.
   - `dart format --set-exit-if-changed`.
   - Kotlin: `./gradlew lint` green.
   - Swift: `swiftformat --lint` green.

5. **CI**
   - GitHub Actions: analyze + test + iOS build + Android build on every PR.

## 7. Out-of-Scope Follow-ups (separate plans)

1. **Retailer cutover** — feature-flag rollout, parity QA, Scanbot dependency removal.
2. **Vendor app cutover** — once retailer is stable.
3. **MRZ / ID-card** — only if a concrete product need lands.
4. **Image filter pipeline** — additional document enhancement (B&W, color, etc.).
