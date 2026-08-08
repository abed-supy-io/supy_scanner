# UI Parity Matrix — Supy Scanner

**Last audited:** 2026-08-06 · **Scope:** the branded Supy scanning UI across iOS + Android, for all four use-cases.
**Companion to:** `docs/superpowers/plans/2026-08-06-track-d-unified-supy-ui.md` (this is that plan's **D0** deliverable).

> **How to read this:** The Supy UI chrome is drawn in **Flutter** (`lib/src/widgets/`) over a native camera-preview **PlatformView**. Because the chrome is one Dart widget tree, its iOS/Android rendering is *structurally identical* — the parity risk is not "does the widget look the same" but **"does the user-facing entry point actually route to the Flutter widget, or to a native full-screen surface?"** and **"is the native preview + detection contract equivalent on both platforms?"** Those are the columns that matter.

## Legend

| Symbol | Meaning |
|---|---|
| ✅ | Parity-complete / branded-embedded end-to-end |
| ⚠️ | Exists but diverges (native full-screen surface, or themed by convention not by the palette driver) |
| ❌ | Not routed to the branded widget / missing |
| — | Not applicable |

---

## 1. Verdict per use-case (the headline)

| Use-case | Branded end-to-end? | What the facade/compat actually invokes today |
|---|---|---|
| **Single-scan barcode** | ✅ | Flutter `SupyBarcodeScannerScreen`/`View` over embedded barcode PlatformView. Compat `BarcodeScanbotView` → `SupyBarcodeScannerView` (`compat/.../barcode_scanbot_view.dart:156`). |
| **Find-and-pick** | ✅ | Flutter `SupyFindAndPickSheet` + accumulator over the same embedded barcode PlatformView. |
| **Document (multi-page)** | ✅ *(mobile, generic)* | **D1 landed (2026-08-07).** `SupyDocumentScanner.startMultiPage` → on Android/iOS with the default generic intent, pushes Flutter `SupyDocumentScannerScreen` over the branded `SupyDocumentScannerView` (`lib/src/document/supy_document_scanner.dart`). Compat `InvoiceScannerService.scanWithCamera` (default generic intent, consumes only `.pages`) inherits the branded flow. **Native `scanDocument` retained as fallback only** for `intent: invoice` (native OCR + PDF) and non-mobile (`kIsWeb`/desktop). |
| **Batch / multiple** | ❌ | `SupyScannerChannel.scanBarcodesBatch` (`lib/src/channel/supy_scanner_channel.dart:55`) → **native full-screen** (iOS `BatchBarcodeScannerPresenter`; Android `BatchBarcodeScannerLauncher` → `BatchBarcodeScannerActivity`). Flutter `SupyMultipleScanSheet` + accumulator **exist but are bypassed.** |

**Three of four use-cases are branded end-to-end on mobile (document landed via D1, 2026-08-07). Batch still routes to a native full-screen surface** despite having a complete Flutter widget — that remaining gap is the rest of plan phase **D1**.

---

## 2. Native capture-surface routing (the divergence, in detail)

| Use-case | Branded embedded widget (exists) | iOS native fallback path | Android native fallback path | Default today |
|---|---|---|---|---|
| Single-scan | `SupyBarcodeScannerView` (`lib/src/widgets/supy_barcode_scanner_view.dart`) | — | — | ✅ embedded |
| Find-and-pick | `SupyFindAndPickSheet` (`lib/src/widgets/supy_find_and_pick_sheet.dart`) | — | — | ✅ embedded |
| Document | `SupyDocumentScannerScreen` → `SupyDocumentScannerView` (`lib/src/widgets/`) | `ios/Classes/document/DocumentScannerPresenter.swift` → `VNDocumentCameraViewController` *(now invoice/desktop fallback)* | `android/.../document/DocumentScannerLauncher.kt` → GMS `GmsDocumentScanning` → `CameraXDocumentScannerActivity.kt` *(now invoice/desktop fallback)* | ✅ **embedded** *(mobile, generic)* |
| Batch/multiple | `SupyMultipleScanSheet` (`lib/src/widgets/supy_multiple_scan_sheet.dart`) | `ios/Classes/barcode/BatchBarcodeScannerPresenter.swift` | `android/.../barcode/BatchBarcodeScannerLauncher.kt` → `BatchBarcodeScannerActivity.kt` | ⚠️ **native** |

**D1 target:** flip both rows' "Default today" to embedded; demote the native columns to explicit fallbacks (camera denied / no Play Services / device-tier gate). **Document row flipped 2026-08-07** — native retained for `intent: invoice` (native OCR + PDF) and non-mobile. Batch row still pending.

---

## 3. Flutter chrome inventory (structurally cross-platform)

Every element below is one Flutter widget → renders identically on both platforms by construction. The "Palette" column reflects the D-2 finding: theming is a **convention**, not yet a driver.

| Chrome element | Widget | Themed via `SupyScannerPalette` driver? |
|---|---|---|
| Viewfinder / finder brackets | `supy_finder_painter.dart` | ⚠️ config carries own color literals (`supy_view_finder_configuration.dart`) |
| Top bar (cancel + scrim) | `supy_top_bar.dart` | ⚠️ `supy_top_bar_configuration.dart` |
| Action bar (torch/zoom/flip) | `supy_action_bar.dart` | ⚠️ `supy_action_bar_configuration.dart` + `SupyActionButtonSpec` |
| AR bounding boxes + labels | `supy_ar_overlay.dart` | ⚠️ `supy_ar_overlay_configuration.dart` |
| Static guidance pill | `supy_user_guidance_card.dart` | ⚠️ `supy_user_guidance_configuration.dart` |
| Single-scan confirmation sheet | `supy_single_scan_confirmation_sheet.dart` | ⚠️ `supy_single_scan_use_case_configuration.dart` |
| Multiple-scan sheet + accumulator | `supy_multiple_scan_sheet.dart` / `supy_multiple_scan_accumulator.dart` | ⚠️ `supy_multiple_scan_use_case_configuration.dart` |
| Find-and-pick sheet + accumulator | `supy_find_and_pick_sheet.dart` / `supy_find_and_pick_accumulator.dart` | ⚠️ `supy_find_and_pick_use_case_configuration.dart` |
| Document overlay + countdown ring | `supy_document_scanner_view.dart` (`SupyDocumentCountdownRing`) | ⚠️ `supy_document_guidance_configuration.dart` |

> **Palette gap (D2):** `SupyBarcodeScannerScreen` accepts a `palette` param, but each `Supy*Configuration` default holds its own hardcoded `Color(...)`, so a single palette swap does **not** propagate. D0-4 enumerates the literals; D2-1 converts config defaults to palette derivations.

---

## 4. Native embedded contract parity (barcode) — ✅ FULL

Both embedded barcode PlatformViews register under **`io.supy.scanner/v1/barcode_view`** (`ios/.../SupyBarcodeScannerViewFactory.swift:11`, `android/.../SupyBarcodeScannerViewFactory.kt:33`) and handle the identical per-view MethodChannel surface:

| Method | iOS (`SupyBarcodeScannerView.swift`) | Android (`SupyBarcodeScannerView.kt`) |
|---|---|---|
| `pause` | ✅ :470 | ✅ :651 |
| `resume` | ✅ :475 | ✅ :655 |
| `setTorch` | ✅ :480 | ✅ :664 |
| `setZoom` | ✅ :483 | ✅ :670 |
| `flipCamera` | ✅ :486 | ✅ :692 |
| `setMinFocusDistanceLock` | ✅ :488 | ✅ :722 |
| `setFormats` | ✅ :491 | ✅ :733 |

**No method drift.** Detection events carry `boundingBox` on both → the Flutter AR overlay is fed identically.

---

## 5. Native embedded contract parity (document) — ✅ WITH A STALE COMMENT

Both embedded document PlatformViews register under **`io.supy.scanner/v1/document_view`** and emit the same event surface:

| Signal / method | iOS (`SupyDocumentScannerView.swift`) | Android (`SupyDocumentScannerView.kt`) |
|---|---|---|
| `preview_started` event | ✅ | ✅ :148 |
| `frame_metrics` event (quad, coverage, tilt, luma, blur, glare, stability, `liveQualityScore`) | ✅ (Vision) | ✅ :156 (JNI `detectQuad` via `DocumentFrameAnalyzer`) |
| `captureAndRectify` method | ✅ | ✅ :253 |
| Live edge detection wired | ✅ | ✅ (`DocumentFrameAnalyzer` + `SupyNativeCore.detectQuad`) |

Guidance FSM (`SupyDocumentStateMachine` in Dart) consumes `frame_metrics` from **both** platforms → live guidance is real and cross-platform, **not** iOS-only, **not** stubbed. Different engines (iOS Vision, Android JNI C++ core), equivalent wire contract.

> **⚠️ Known defect (D0-5):** `android/.../document/SupyDocumentScannerView.kt:45-46` carries a stale class-doc claiming "Edge-detection … is not wired on Android in this spike." The code below it (`:148`, `:156`, `:253`, and `DocumentFrameAnalyzer`) contradicts it. One-line cleanup so the embedded path is trusted.

---

## 6. Scanbot-compat shim status

`compat/supy_scanner_scanbot_compat/` is an import-only shim:

| Compat surface | Routes to | Branded? |
|---|---|---|
| `BarcodeScanbotView` / `BarcodeScannerController` (`barcode_scanbot_view.dart`) | Supy embedded barcode widget (`:156`) | ✅ |
| `InvoiceScannerService.scanWithCamera` (`invoice_scanner_service.dart:35`) | `startMultiPage` (default generic intent) → branded `SupyDocumentScannerScreen` on mobile; native `scanDocument` fallback for invoice/desktop | ✅ *(mobile, 2026-08-07)* |
| Scanbot document-UI-v2 types (`DocumentScanningFlow`, `ScanbotColor`) | intentionally omitted ("out-of-shim") | — |

Compat signatures are snapshot-locked (`test/api_signature_snapshot_test.dart`); D1 must keep that suite + `retailer_call_sites_test.dart` green while re-routing the *implementation* behind `scanWithCamera`.

---

## 7. Derived D1 backlog (what this audit hands to the plan)

1. ~~**Re-route document** — `startMultiPage` / compat `scanWithCamera` → Flutter flow on `SupyDocumentScannerView`; native `scanDocument` becomes fallback.~~ **✅ Landed 2026-08-07** via `SupyDocumentScannerScreen` (generic intent, mobile). *(D1-1, D1-3, D1-4)*
2. **Re-route batch** — batch entry → `SupyMultipleScanSheet`; native `scanBarcodesBatch`/`scanBatchBarcodes` becomes fallback. *(D1-2)*
3. **Palette-drive config defaults** — remove per-config `Color(...)` literals. *(D2-1)*
4. **Fix stale Android doc comment** — `SupyDocumentScannerView.kt:45-46`. *(D0-5)*

Barcode single-scan + find-and-pick require **no routing work** — they are already branded end-to-end and only inherit the D2 palette + D5 golden-test passes.

---

## 8. D0-4 — Hardcoded color inventory → D2 worklist

**Status: DONE (D2-1, 2026-08-07).** Every literal below now derives from `SupyScannerPalette`. The two open questions resolved: (1) **sheet brightness** — the three result sheets now *track the palette* (`surface`/`onSurface`), so the default dark preset (`supyDark()` since 2026-08-08; `scanbotDark()` before that) renders them as dark cards and a palette swap re-skins them; (2) **barcode border purple `0xFF6448C3`** — dropped in favour of `palette.outline` (no new token added). Config color fields were retyped `Color` → `Color?` (null → derived from palette at render; an explicit `Color` still wins) — logged in `TODO.md`'s decisions log (2026-08-07). No `Color(0x…)`/`Colors.*` literals remain in `lib/src/widgets/` or config defaults; only `supy_scanner_palette.dart` holds token definitions.

Audited 2026-08-06 (`grep 'Color(0x\|Colors.'`). **The palette already defines the right tokens** (`supy_scanner_palette.dart:37-73`) — several config defaults are *byte-identical* to a palette token (marked ✅ below), which proves the palette was the design intent but was never wired as the default source. D2-1 replaces each literal with the mapped `palette.<token>` reference, keeping explicit per-field overrides available.

### 8a. Config defaults (`lib/src/models/ui/`) — the primary target

| File | Field → literal | Proposed palette token |
|---|---|---|
| `supy_view_finder_configuration.dart:103` | finder stroke `0xFF1AC0E5` | `primary` ✅ exact |
| `supy_user_guidance_configuration.dart:15-16` | title `0xFFFFFFFF` / fill `0x99000000` | `onSurface` / `modalOverlay` ✅ exact |
| `supy_document_guidance_configuration.dart:38-41` | warning `0xFFFF4D4D` / notReady `0xFFE5484D` / ready `0xFF30A46C` / scrim `0x99000000` | `warning` ✅ / `negative` / `positive` / `modalOverlay` ✅ |
| `supy_ar_overlay_configuration.dart:11-17` | stroke `0xFF1F8A4C` / fill `0x331F8A4C` / labelBg `0xCC000000` / labelText `0xFFFFFFFF` | `positive` / `positive`@20% / `surfaceLow` / `onSurface` |
| `supy_action_bar_configuration.dart:10-13` | bg `0x66000000` / fg `0xFFFFFFFF` / activeBg `0xFFFFFFFF` / activeFg `0xFF000000` | `surfaceLow`@40% / `onSurface` / `onPrimary` / `onSecondary` |
| `supy_top_bar_configuration.dart:75,79` | bg `0xCC000000` / text `0xFFFFFFFF` | `surfaceLow` / `onSurface` |
| `supy_single_scan_use_case_configuration.dart:22-27` | sheet `0xFFFFFFFF` / title `0xFF000000` / body `0xCC000000` / confirmBg `0xFF000000` / confirmFg `0xFFFFFFFF` / retryFg `0xFF000000` | `surface` / `onSurface` / `onSurfaceVariant` / `primary` / `onPrimary` / `onSurface` † |
| `supy_multiple_scan_use_case_configuration.dart:29-34` | same 6-field sheet set | same mapping † |
| `supy_find_and_pick_use_case_configuration.dart:56-63` | sheet set + matched `0xFF1F8A4C` / pending `0xFF000000` | same + `positive` / `onSurfaceVariant` † |

† **Design note for D2:** the three result sheets currently default to a **light** surface (white bg / black text) regardless of palette. Mapping them to `surface`/`onSurface` makes them follow the palette brightness — confirm with design that the sheets should track the palette (they should, for dark-mode correctness) rather than stay permanently light.

### 8b. Widget-level literals (`lib/src/widgets/`) — secondary

| File:line | Literal | Note |
|---|---|---|
| `supy_barcode_scanner_view.dart:162-163` | `_scrim 0x99000000`, `_border 0xFF6448C3` | scrim → `modalOverlay`; border is a purple not in palette — needs a token decision |
| `supy_barcode_scanner_view.dart:207,214` | `Colors.black`, `Colors.white` | error-state placeholder → `surface`/`onSurface` |
| `supy_document_scanner_view.dart:428,766-820` | `Colors.white/black/black26` | capture flash + page-review chrome → palette tokens |

**Not in scope for D2 recolor:** `supy_scanner_palette.dart:37-73` — those literals *are* the token definitions (the source), and the two presets `scanbotDark`/`scanbotLight`.

**Verdict:** 9 config files + 2 widget files carry literals; ~60% map to an existing palette token 1:1, the rest need a trivial token assignment. One genuine design decision (sheet brightness) and one missing token (barcode border purple `0xFF6448C3`) to resolve before D2-1 lands.
