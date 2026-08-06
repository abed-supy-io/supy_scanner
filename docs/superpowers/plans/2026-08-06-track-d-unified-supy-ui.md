# Track D — Unified Supy Scanning UI (iOS + Android parity)

**Date:** 2026-08-06
**Status:** Draft plan — pending owner review
**Related:** `docs/superpowers/specs/2026-07-17-v2-commercial-roadmap-design.md` (v2.0 roadmap — this is the missing UI track, slots alongside Tracks A/B/C), `docs/MIGRATION.md`, `CLAUDE.md`
**Owner:** owner + incoming mobile lead

---

## 1. Why this track exists

The v2.0 roadmap (Tracks A/B/C) covers scan **quality**, **smart features**, and **commercial packaging** — but never names the **UI** as a first-class, parity-guaranteed surface, even though a custom Supy UI is already ~80% built. This track formalizes it: one branded scanning UI that renders **identically on iOS and Android** for every use-case, fully drop-in behind the Scanbot-compat surface, and provably parity-locked in CI.

**Non-negotiable (from `CLAUDE.md`):** drop-in API compatibility. No renamed props, no new required args, no return-type changes vs. the current Scanbot call sites. Every task here sits *behind* the frozen surface (`io.supy.scanner/v1`) or is purely additive/optional.

## 2. Architecture decision (the spine)

**Decision D-1: The embedded Flutter-over-PlatformView path is THE Supy UI. The native full-screen launchers are fallback-only, never the branded default.**

Grounded in the current code:

- **UI chrome is drawn in Flutter**, composited over a native camera-preview `PlatformView`. iOS mounts `UiKitView`, Android mounts `AndroidView`, both against view-type `io.supy.scanner/v1/{barcode,document}_view`. → **Visual parity is structural, not duplicated per-platform.** We theme once in Dart; both platforms inherit it.
- Native side is a thin **preview + detection-signal** surface only:
  - Barcode: `ios/Classes/barcode/SupyBarcodeScannerView.swift` ↔ `android/.../barcode/SupyBarcodeScannerView.kt`
  - Document: `ios/Classes/document/SupyDocumentScannerView.swift` ↔ `android/.../document/SupyDocumentScannerView.kt` (embedded `LifecycleCameraController` + `PreviewView`).
- **The debt is bigger than one screen, and it's what the retailer actually sees today.** A parity audit (2026-08-06) confirmed the embedded branded views exist on both platforms *but nothing user-facing routes to them for two of the four use-cases*:
  - **Document:** the high-level facade (`SupyDocumentScanner.startMultiPage`) and compat `InvoiceScannerService.scanWithCamera` call the `scanDocument` channel method, which launches a **native full-screen** scanner per platform — iOS `DocumentScannerPresenter.swift` → Apple `VNDocumentCameraViewController` (system UI); Android `DocumentScannerLauncher.kt` → GMS `GmsDocumentScanning` intent, falling back to a hand-drawn `CameraXDocumentScannerActivity`. The branded `SupyDocumentScannerView` PlatformView exists with full parity **but is an orphaned alternative surface the facade never invokes.**
  - **Batch / multiple scan:** same shape — a parallel native full-screen path (iOS `BatchBarcodeScannerPresenter.swift` / `scanBarcodesBatch`; Android `BatchBarcodeScannerLauncher` → `BatchBarcodeScannerActivity` / `scanBatchBarcodes`) that bypasses the Flutter `SupyMultipleScanSheet` accumulator UI.
  - Only **single-scan barcode** and **find-and-pick** are branded end-to-end today (compat `BarcodeScanbotView` → Supy widgets).

**Consequence:** the branded, embedded PlatformView path becomes the default for document **and** batch on both platforms. The native launchers (`VNDocumentCameraViewController`, GMS, the two `*Activity` classes) are demoted to explicit, documented fallbacks (no camera / no Play Services / low-tier device) — never the surface the retailer sees by default. This is the load-bearing phase (D1): the widgets already exist; the work is **re-routing the facade + compat to them**, not building new UI.

**Decision D-2: Make `SupyScannerPalette` an actual single source of truth — today it is only a convention.** The audit found each component config (`SupyTopBarConfiguration`, `SupyViewFinderConfiguration`, `SupyActionBarConfiguration`, the document guidance config, etc.) carries its **own hardcoded color literals** as defaults; `SupyBarcodeScannerScreen` accepts a `palette` param but the sub-configs must be themed independently. So a single palette change does **not** currently re-skin everything. D2 closes that: every config's default derives from the palette; zero hardcoded `Color(0x…)` in `lib/src/widgets/` or the config defaults. Locale/RTL (Arabic) is a first-class requirement — and unlike the system launchers (where palette/locale were documented no-ops in S3-04), the embedded path makes them *real*.

## 3. Scope — the four use-cases, one UI system

All already have Dart widgets; this track makes them parity-complete, themed, and CI-locked:

| Use-case | Entry widget | Key chrome |
|---|---|---|
| Single scan | `SupyBarcodeScannerScreen` / `SupyBarcodeScannerView` | viewfinder, top bar, action bar, single-scan confirmation sheet |
| Batch / multiple scan | `SupyMultipleScanSheet` + `SupyMultipleScanAccumulator` | running count, per-item haptic, dedupe feedback |
| Find-and-pick | `SupyFindAndPickSheet` + `SupyFindAndPickAccumulator` | expected-barcode checklist, match/miss states |
| Document | `SupyDocumentScannerView` (+ `SupyDocumentCountdownRing`) | live edge/AR overlay, auto-capture countdown, guidance card, page review |

Cross-cutting chrome: `SupyTopBar`, `SupyActionBar`, `SupyArOverlay`, `SupyFinderPainter`, `SupyUserGuidanceCard`.

## 4. Phases

### D0 — Parity audit & single-source-of-truth decision (no user-facing change)

Settle, in writing, exactly what is parity-complete vs. divergent before touching code.

- [ ] **D0-1** Produce `docs/UI-PARITY.md`: for each of the four use-cases, a table of (chrome element × iOS present? × Android present? × themed via palette? × wired to real native signal?). Cite file paths.
- [ ] **D0-2** ✅ *finding confirmed 2026-08-06 — record in the doc:* both the **document** facade (`scanDocument` → VisionKit / GMS / `CameraXDocumentScannerActivity`) and the **batch** facade (`scanBarcodesBatch` / `scanBatchBarcodes` → native `*Presenter`/`*Activity`) route to native full-screen surfaces, not the Flutter widgets. Only single-scan + find-and-pick are branded end-to-end. This is the D1 backlog.
- [ ] **D0-3** Confirm the barcode embedded view exposes an equivalent contract on both platforms (preview + torch + pause/resume + detection events). List any method present on one platform and missing on the other. *(Audit: full parity under `io.supy.scanner/v1/barcode_view` — verify no drift before relying on it.)*
- [ ] **D0-4** Inventory hardcoded colors/strings in `lib/src/widgets/` **and in each `Supy*Configuration` default** (`grep` for `Color(0x`, `Colors.`, string literals). Each is a D2 task item. *(Audit already flags per-config color literals as the root cause — palette is not yet a driver.)*
- [ ] **D0-5** Fix the stale/misleading class-doc at `android/.../document/SupyDocumentScannerView.kt:45-46` ("Edge-detection … is not wired on Android in this spike") — the `DocumentFrameAnalyzer`/`detectQuad` code below it *does* wire it. One-line `docs:`/`fix:` cleanup so future readers trust the embedded path.

**Exit:** `docs/UI-PARITY.md` committed; the divergences that matter (document + batch native-full-screen default paths, any barcode method drift, per-config hardcoded-color list, stale comment) are enumerated as concrete backlog items.

### D1 — Re-route facade + compat to the branded embedded path (document AND batch)

The widgets exist; this phase changes *what the facade invokes*, not the UI itself. Two use-cases to convert.

- [ ] **D1-1 (document)** Route `SupyDocumentScanner.startMultiPage` (and thus compat `InvoiceScannerService.scanWithCamera`) to a Flutter flow built on the embedded `SupyDocumentScannerView` + `SupyDocumentCountdownRing` by default on both platforms. The `scanDocument` native path (VisionKit / GMS / `CameraXDocumentScannerActivity`) becomes an explicit fallback, selected only when the embedded path is unavailable (camera denied, no Play Services for GMS, device-tier gate). No new *required* args — fallback selection is internal.
- [ ] **D1-2 (batch)** Route the batch/multiple entry to the Flutter `SupyMultipleScanSheet` + `SupyMultipleScanAccumulator` over the embedded barcode PlatformView by default, demoting the native `scanBarcodesBatch`/`scanBatchBarcodes` presenters/activities to the same fallback contract.
- [ ] **D1-3** Ensure the compat facade (`compat/supy_scanner_scanbot_compat`) presents the branded embedded UI for both, matching Scanbot's RTU (ready-to-use) look-and-feel expectation. Compat snapshot + retailer call-site suites stay green (no signature change).
- [ ] **D1-4** Document the fallback contract in `docs/MIGRATION.md`: exactly when a native/unbranded surface can still appear, and that palette/locale are honored on the embedded path (superseding the S3-04 no-op note).
- [ ] **D1-5** Mocked unit tests for the path-selection logic (embedded vs. fallback) for both document and batch, on both platforms.

**Exit:** all four use-cases are branded-embedded by default on both platforms; the native launchers are fallback-only and documented; compat + retailer call-site suites green.

### D2 — Theming completeness (`SupyScannerPalette` drives everything)

- [ ] **D2-1** Replace every hardcoded color from D0-4 with a `SupyScannerPalette` derivation — **in both the widgets and the `Supy*Configuration` defaults** (the audit found the color literals live mostly in the config defaults, which is why a `palette` swap doesn't currently propagate). After this, one palette change re-skins all four use-cases. No `Color(0x…)` literals left in `lib/src/widgets/` or config defaults; explicit per-field overrides remain allowed.
- [ ] **D2-2** Verify each use-case config (`Supy*UseCaseConfiguration`, `SupyViewFinderConfiguration`, `SupyTopBarConfiguration`, `SupyActionBarConfiguration`, `SupyArOverlayConfiguration`, `SupyDocumentGuidanceConfiguration`) is honored by its widget with sensible palette-derived defaults.
- [ ] **D2-3** Locale/RTL pass: all guidance/label strings localized (en + ar), layouts mirror correctly in RTL. Ties into `docs/LOCALIZATION.md`.
- [ ] **D2-4** Dark-mode correctness for every screen (palette must resolve for both brightnesses).

**Exit:** a single palette change re-skins all four use-cases on both platforms; Arabic/RTL renders correctly.

### D3 — Live guidance / AR overlay parity (the "delight" layer)

The overlay is where perceived quality lives (from the quality brainstorm's Layer 3). It must be fed by **real native detection signals**, identically on both platforms.

- [ ] **D3-1** Define the guidance signal contract on the `io.supy.scanner/v1` event surface: document quad, sharpness, luma/too-dark, distance/too-far, in-frame. (If any key is iOS-only or Android-only per D0, add it to the missing platform — update the `docs/ARCHITECTURE.md` method/event table in the same PR.)
- [ ] **D3-2** Wire `SupyArOverlay` / `SupyFinderPainter` / `SupyUserGuidanceCard` to those signals via `SupyDocumentMetricsSmoother` (smoothing already exists) so the overlay is stable, not jittery, on both platforms.
- [ ] **D3-3** Success feedback: haptic + brief bounding-box/edge flash on lock/auto-capture — identical timing on both platforms.
- [ ] **D3-4** Auto-capture countdown (`SupyDocumentCountdownRing`) driven by the same "steady + framed" signal on both platforms.

**Exit:** aim guidance and success feedback behave identically on iOS and Android, driven by real detection, not stubs.

### D4 — Accessibility & input parity

- [ ] **D4-1** Semantics labels on all interactive chrome (torch, capture, close, page thumbnails); screen-reader pass on both platforms.
- [ ] **D4-2** Large-text / text-scale resilience for guidance and sheets.
- [ ] **D4-3** Haptic feedback uses the platform-appropriate API but the same semantic events (item added, lock, error).

**Exit:** the UI is usable with assistive tech on both platforms; no clipped/overflowing chrome at large text scales.

### D5 — Parity locked in CI (the "beat them, provably" gate)

This is what makes UI parity a guarantee instead of a hope — the UI analogue of the DSQ bench.

- [ ] **D5-1** Golden (widget) tests for each of the four use-case screens, rendered in {light, dark} × {LTR, RTL} × {default palette, alt palette}. Goldens are platform-agnostic Flutter renders → they *are* the parity proof, since both platforms run the same widget tree.
- [ ] **D5-2** Golden test for each overlay state (searching / too-dark / too-far / locked / countdown).
- [ ] **D5-3** Add the golden suite to CI; a diff fails the PR. Document the `--update-goldens` regen flow in `docs/QA.md`.
- [ ] **D5-4** Extend the example app to exercise all four use-cases with a live palette switcher (also serves as the demo-app polish the roadmap's Track C needs for sales).

**Exit:** any unintended UI change fails CI; the example app showcases the themable UI end-to-end.

### D6 — Docs & migration

- [ ] **D6-1** `docs/UI.md`: the Supy UI guide — the four use-cases, the config models, the palette, how to theme, the fallback contract.
- [ ] **D6-2** Scanbot RTU-UI → Supy UI mapping table in `docs/MIGRATION.md` (which Scanbot config maps to which `Supy*Configuration`).
- [ ] **D6-3** Dartdoc on all public UI types (the exports in `lib/supy_scanner.dart` lines 38–80) — full docs, per the public-API rule.

**Exit:** a consumer can theme and adopt the UI from docs alone; migration mapping is complete.

## 5. Sequencing & dependencies

```
D0 (audit) ──▶ D1 (default path) ──▶ D2 (theming) ──▶ D3 (guidance parity)
                                          │                    │
                                          └────────▶ D4 (a11y) ─┴─▶ D5 (CI goldens) ──▶ D6 (docs)
```

D0 is mandatory first — it converts assumptions into a backlog. D1 and D2 are the highest-value user-visible wins (branded default + themable). D5 should land incrementally *as* each screen stabilizes, not saved to the end. Recommended first PR: **D0-1/D0-2** (the parity doc + doc-path finding) — cheap, unblocks everything.

## 6. Global constraints (in force every task)

- **Compat inviolate.** No public-signature change; compat snapshot + retailer call-site tests green on every PR. Any intentional surface change → logged decision in `TODO.md` first.
- **On-device only.** No network in any UI/scan path. No paid SDK.
- **Channel discipline.** New guidance-signal keys go in `io.supy.scanner/v1` and the `docs/ARCHITECTURE.md` table + both native handlers + a mocked test, same PR (per the `add-channel-method` skill).
- **iOS 16 min / mid-range Android.** No iOS-17-only APIs without fallback; overlay/animation must stay smooth on low-tier devices (respect `SupyDeviceTier` / `ThermalGovernor`).
- **Conventional commits.** `feat(ui): …`, `fix(ios): …`, `test(ui): golden …`, `docs: …`. One concern per PR.

## 7. Supy Fit Assessment

This is a Flutter library with native Swift/Kotlin — most Supy backend standards are N/A; flagged honestly:

- **nx-nestjs / architecture.md** — N/A. The repo's own layering (Dart API → `channel/` → native, sealed types, no `dynamic`/`Map<String,dynamic>` past `lib/src/channel/`) is the governing standard; this plan preserves it — guidance signals cross the boundary as typed events, not raw maps.
- **NATS event patterns** — N/A (no bus). The nearest analogue, the versioned `io.supy.scanner/v1` channel, follows the same contract-stability rule: new signal keys are additive on v1, never a break.
- **Cerbos / security** — N/A. No auth surface; camera permission stays via `SupyPermissions`. No secrets touched.
- **Commit conventions** — apply fully; per-phase PRs decompose cleanly into `feat(ui)/fix/test/docs`.
- **Supy scope rule** — this is the retailer-facing, sellable SDK's UI; the branded embedded path directly serves the drop-in-Scanbot mandate. Not a tangent.
- **Roadmap fit** — slots as the missing "Track D" beside A/B/C. D5's golden gate mirrors the DSQ bench philosophy (parity/quality made provable in CI). D5-4's example-app polish feeds Track C's demo-app deliverable.

## 8. Open questions for the owner

1. **Fallback policy (D1):** when the embedded path can't run (no Play Services for GMS, camera denied, tier-low), is a *branded fallback* required, or is the system launcher acceptable as a last resort? Recommendation: branded embedded is default; system launcher only on hard capability failure, logged.
2. **Golden baseline platform (D5):** goldens render identically regardless of host, but CI must pin a Flutter version for stable font metrics. Confirm we pin to the CI Flutter already used for analyze/test.
3. **Priority vs. Track B:** does Track D run parallel to Track B (smart features), or after v1.2.0? Recommendation: D0–D2 parallel with Track A (mostly Dart, low device dependency); D3+ once devices arrive.
