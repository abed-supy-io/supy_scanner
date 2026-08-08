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

- [x] **D1-1 (document)** Route `SupyDocumentScanner.startMultiPage` (and thus compat `InvoiceScannerService.scanWithCamera`) to a Flutter flow built on the embedded `SupyDocumentScannerView` + `SupyDocumentCountdownRing` by default on both platforms. The `scanDocument` native path (VisionKit / GMS / `CameraXDocumentScannerActivity`) becomes an explicit fallback, selected only when the embedded path is unavailable (camera denied, no Play Services for GMS, device-tier gate). No new *required* args — fallback selection is internal. *(2026-08-07 — `SupyDocumentScannerScreen` branded session; `generic` intent branded on mobile, `invoice`/web/desktop native fallback. See `TODO.md` decisions.)*
- [x] **D1-2 (batch)** Route the batch/multiple entry to the Flutter `SupyMultipleScanSheet` + `SupyMultipleScanAccumulator` over the embedded barcode PlatformView by default, demoting the native `scanBarcodesBatch`/`scanBatchBarcodes` presenters/activities to the same fallback contract. *(2026-08-07 — `SupyBarcodeScanner.startMultiple` facade; branded on mobile, native fallback on web/desktop; counting-mode `duplicateCount = sum(counts) − uniqueRows` adapter; `maxBatchCount` not enforced on branded path. See `TODO.md` decisions + `docs/MIGRATION.md`.)*
- [x] **D1-3** Ensure the compat facade (`compat/supy_scanner_scanbot_compat`) presents the branded embedded UI for both, matching Scanbot's RTU (ready-to-use) look-and-feel expectation. Compat snapshot + retailer call-site suites stay green (no signature change). *(2026-08-07 — barcode/counting compat already renders the embedded branded `SupyBarcodeScannerView`. Document compat `InvoiceScannerService.scanWithCamera` was still calling native `scanDocument` directly; re-routed the production (no-injected-channel) path through `SupyDocumentScanner.startMultiPage` so the real retailer document call site is branded on mobile. `channel` test seam retained → API snapshot + retailer call-site suites unchanged.)*
- [x] **D1-4** Document the fallback contract in `docs/MIGRATION.md`: exactly when a native/unbranded surface can still appear, and that palette/locale are honored on the embedded path (superseding the S3-04 no-op note). *(2026-08-07 — `docs/MIGRATION.md` created with the entry-point table + "Fallback contract (Track D / D1)" section covering non-mobile, `invoice` intent, capability failure, palette/locale, and the batch `maxBatchCount` gap. Full Scanbot config-mapping table remains D6-2.)*
- [x] **D1-5** Mocked unit tests for the path-selection logic (embedded vs. fallback) for both document and batch, on both platforms. *(2026-08-07 — `test/barcode/supy_barcode_scanner_test.dart` + `test/document/supy_document_scanner_test.dart` / `test/widgets/supy_document_scanner_screen_test.dart`: macOS-override asserts native-channel fallback, default-android asserts branded push with the channel untouched.)*

**Exit:** all four use-cases are branded-embedded by default on both platforms; the native launchers are fallback-only and documented; compat + retailer call-site suites green.

### D2 — Theming completeness (`SupyScannerPalette` drives everything)

- [x] **D2-1** Replace every hardcoded color from D0-4 with a `SupyScannerPalette` derivation — **in both the widgets and the `Supy*Configuration` defaults** (the audit found the color literals live mostly in the config defaults, which is why a `palette` swap doesn't currently propagate). After this, one palette change re-skins all four use-cases. No `Color(0x…)` literals left in `lib/src/widgets/` or config defaults; explicit per-field overrides remain allowed.
- [x] **D2-2** Verify each use-case config (`Supy*UseCaseConfiguration`, `SupyViewFinderConfiguration`, `SupyTopBarConfiguration`, `SupyActionBarConfiguration`, `SupyArOverlayConfiguration`, `SupyDocumentGuidanceConfiguration`) is honored by its widget with sensible palette-derived defaults. **(2026-08-07)** Audit confirmed every nullable color field has a `?? palette.<token>` fallback at its point of use; the one dead field was `SupyTopBarConfiguration.statusBarMode` — now fully wired in `SupyTopBar` (light/dark via `AnnotatedRegion<SystemUiOverlayStyle>`, `hidden` via `SystemChrome`, restored on dispose). Default `hidden` hides the system status bar on all four branded screens (Scanbot RTU parity) — see TODO.md decisions log.
- [x] **D2-3** Locale/RTL pass: all guidance/label strings localized (en + ar), layouts mirror correctly in RTL. Ties into `docs/LOCALIZATION.md`. **(2026-08-07)** Added `SupyScannerStrings` (`.en()`/`.ar()` presets + `.of(languageCode)`), the string counterpart to `SupyScannerPalette`; every config string field widened `String → String?` (default `null` → resolve `config.field ?? strings.field` at render). Barcode screen gained an additive optional `locale`; both screens wrap chrome in `Directionality(strings.textDirection)` and use `EdgeInsetsDirectional`/`AlignmentDirectional`/`PositionedDirectional` so Arabic mirrors. `docs/LOCALIZATION.md` published (strategy, resolution order, RTL contract, override rules, adding a locale). Tests: bundle presets/`of()`/direction/format-helpers/`copyWith`, config-null defaults, and `locale: 'ar'` → RTL + Arabic-bundle resolution on the barcode screen. Green gate clean (root 401 + compat 11 + `dart analyze --fatal-infos`). Compat-surface widening logged in TODO.md decisions (2026-08-07).
- [x] **D2-4** Dark-mode correctness for every screen (palette must resolve for both brightnesses). **(2026-08-07)** D2-1/D2-2 already routed every color through `SupyScannerPalette` (zero `Color(0x…)` literals in `lib/src` outside the palette file; no `Theme.of`/`Brightness` logic in widgets), so both brightnesses are structurally covered by the two presets — `scanbotDark()` (default) and `scanbotLight()`. Added a screen-level propagation proof, `test/widgets/supy_palette_brightness_test.dart`: each of the four branded screens (single/multiple/find-and-pick barcode + document) pumps under both presets, asserts `takeException()` is null (renders for both brightnesses), and reads `Scaffold.backgroundColor` back to prove a single `palette:` swap re-skins the screen end-to-end (light `surface` drives the chrome and differs from dark). No new public API — deliberately did not add brightness-auto-follow (would be a logged compat decision, out of scope). Green gate clean (root 439 + compat 11 + `dart analyze --fatal-infos`).

**Exit:** a single palette change re-skins all four use-cases on both platforms; Arabic/RTL renders correctly.

### D3 — Live guidance / AR overlay parity (the "delight" layer)

The overlay is where perceived quality lives (from the quality brainstorm's Layer 3). It must be fed by **real native detection signals**, identically on both platforms.

- [x] **D3-1** Define the guidance signal contract on the `io.supy.scanner/v1` event surface: document quad, sharpness, luma/too-dark, distance/too-far, in-frame. (If any key is iOS-only or Android-only per D0, add it to the missing platform — update the `docs/ARCHITECTURE.md` method/event table in the same PR.) **(2026-08-07)** Audit (signal-coverage matrix) found the five aim signals already at full iOS/Android parity — each has a typed `SupyDocumentFrameMetrics` field, is channel-parsed in `supy_document_event_channel.dart`, and is emitted identically by both native `toMap()`s (`DocumentDetector.swift` / `DocumentFrameAnalyzer.kt`). So the parenthetical's "add missing key" clause was **not** triggered for any of the five — no native change needed. The real gap was documentation: `docs/ARCHITECTURE.md` enumerated the data-capture wire keys but named only the Dart target types for the document stream. Formalized the full `frame_metrics` contract there (every key: type, range, meaning; the five aim-signal mappings; and the two **optional** iOS-only derived fields `state`/`liveQualityScore` with their Dart-FSM fallback). Locked it with a contract test — `supy_document_event_channel_test.dart` now round-trips the complete documented key set (was untested for `glareRatio`/`cornerVelocity`/`centerOffset*`/`perCornerStability`/`liveQualityScore`). The iOS-native-classifier vs Dart-FSM asymmetry (so guidance *state* is bit-identical on both platforms) is explicitly deferred to D3-2, not this raw-signal contract. Green gate clean (root 446 + compat 11 + `dart analyze --fatal-infos`).
- [x] **D3-2** Wire the live overlay to the detection signals via `SupyDocumentMetricsSmoother` so it is stable, not jittery, on both platforms. **(2026-08-07)** *Correction to the ticket's scope:* the three named widgets are all **barcode-only** and consume no document signal — `SupyArOverlay` paints barcode bounding boxes (`List<SupyBarcode>`), `SupyFinderPainter` is a static cornered finder frame, `SupyUserGuidanceCard` is a static barcode guidance pill. The real live *document* overlay lives inside `supy_document_scanner_view.dart` (`_DocumentGuidancePainter` + hint card), so that is what D3-2 actually wires. Native audit (both platforms) confirmed the emitted `quad` and all scalars are **raw, per-frame** — neither side temporally smooths the corner coordinates (iOS's C++ classifier smooths internally but is never fed the quad and only emits `state`/`liveQualityScore`; Android emits raw metrics only). The concrete parity gap: `_handleEvent`'s Android path smooths inside the FSM (`_stateMachine.tick`), but the iOS/native-`state` path handed the **raw** metrics straight to the painter → stable on Android, jittery on iOS. Fix: route the iOS/native-state metrics through a standalone `SupyDocumentMetricsSmoother` (same `guidance.smoothingAlpha`, rebuilt on alpha change) while still trusting the native `state`; a Dart render-smoother is correct here precisely because iOS emits a raw quad, so it adds no double-smoothing lag. Locked with a frame-for-frame parity test (`test/document/supy_document_render_smoothing_parity_test.dart`) proving the iOS render-smoother and the Android FSM produce byte-identical smoothed metrics across alphas and a lost-document reset. Green gate clean (root 450 + compat 11 + `dart analyze --fatal-infos`).
- [x] **D3-3** Success feedback: haptic + brief bounding-box/edge flash on lock/auto-capture — identical timing on both platforms. **(2026-08-07)** Auto-capture already had a success cue (`_triggerFlash`: full-screen shutter flash + `HapticFeedback.lightImpact()`); the gap was at the *lock* moment — the transition into `ready` had no feedback. Added a lock cue in `supy_document_scanner_view.dart` fired from the shared Dart `ready` transition in `_handleEvent` (`_triggerLockCue`): a crisp `HapticFeedback.selectionClick()` (distinct from the shutter's `lightImpact`) plus a one-shot 280 ms edge flash — a new `_lockFlashController` snapped to full intensity and decayed via `reverse(from: 1.0)`, feeding `_DocumentGuidancePainter.lockFlash`, which strokes the full detected-quad outline at `readyColor` with alpha = lockFlash. **Timing parity is structural, not re-implemented:** the cue triggers off the *same* Dart-observed `ready` transition both platforms reach identically (iOS trusts the native `state`, Android classifies via the Dart FSM — both already proven byte-identical by the D3-2 render-smoothing parity test), so the haptic and flash fire at the same instant on iOS and Android by construction. The `ready` transition can't be driven in a widget test (no PlatformView on desktop), so the flash *rendering primitive* is locked with a painter-level pixel test (`test/widgets/document_guidance_painter_lock_flash_test.dart`, 4 tests) via a single `@visibleForTesting makeDocumentGuidancePainter` factory (painter type kept library-private). Green gate clean (root 454 + compat 11 + `dart analyze --fatal-infos`).
- [x] **D3-4** Auto-capture countdown (`SupyDocumentCountdownRing`) driven by the same "steady + framed" signal on both platforms. **(2026-08-07)** *Correction to the ticket's implied scope:* the ring widget and its wiring already existed (started on the `ready` transition, cancelled on non-`ready`, `onComplete` → `captureAndRectify`). The real gap was that "steady + framed" was read as *raw per-frame `ready`*, not a *stable* signal: `SupyDocumentStateMachine` treats the `ready`↔non-`ready` transition as **terminal** (fires immediately, bypassing min-dwell), so a single hand-shake / hold-steady blip frame demoted out of `ready`, and `_handleEvent` cancelled the countdown on *any* one non-ready frame — tearing down the sweeping ring (regenerated `UniqueKey`) and restarting it from zero (and re-firing the D3-3 lock cue). On a jittery handheld this could starve auto-capture indefinitely. Fix: a small frame-count hysteresis on the shared Dart gate — extracted a pure `SupyAutoCaptureHoldGate` (`lib/src/document/supy_auto_capture_hold_gate.dart`, default `graceFrames: 3` ≈ 100 ms at 30 fps) that debounces the `ready` acquisition. `_handleEvent` now drives the lock cue / `onReady` / countdown off the gate's `acquired`/`lost` edges: a ≤3-frame flicker rides through (ring keeps sweeping, no re-cue), while a genuine departure (≥4 consecutive non-ready) cancels — well inside the 600 ms sweep. **Cross-platform parity is structural:** both platforms feed the same per-frame `ready` boolean into this one gate (iOS trusts native `state`, Android classifies via the Dart FSM — byte-identical per D3-2), so auto-capture holds identically on iOS/Android by construction. Grace lives as a private widget-level default (not a public config field) — no compat-surface change. Locked with a pure gate unit test (`test/document/supy_auto_capture_hold_gate_test.dart`, 10 tests: acquire-once, flicker-within-grace holds, exceed-grace breaks once, streak-resets-between-blips, `graceFrames:0`, and a jittery-hold sequence proving one acquire + no mid-sweep cancel). Green gate clean (root 468 + compat 11 + `dart analyze --fatal-infos`).

**Exit:** aim guidance and success feedback behave identically on iOS and Android, driven by real detection, not stubs.

### D4 — Accessibility & input parity

- [x] **D4-1** Semantics labels on all interactive chrome (torch, capture, close, page thumbnails); screen-reader pass on both platforms. **(2026-08-07)** Audited every interactive control across the branded chrome; the shutter (`_ShutterButton`) already carried `Semantics(button:, enabled:, label:)` and the sheets are built from Material widgets (Buttons/ListTiles) that self-label, so the gaps were the raw `GestureDetector` chrome: the action-bar controls, the top-bar cancel, and the doc page-tray thumbnail + delete badge. A11y labels are user-facing copy → sourced from the single `SupyScannerStrings` bundle (never hardcoded): added 5 base fields (`flash` existed; new `zoom`, `flipCamera`, `closeFocus`, `documentPage`, `deletePage`) with en/ar presets + 3 label builders (`zoomLabel(factor)` → "Zoom 2x", `documentPageLabel(n)` → "Page 3", `deletePageLabel(n)` → "Delete page 3"), touching the full frozen-value contract (ctor, presets, fields, `copyWith`, `==`, `hashCode`) — additive, no compat-surface change (Supy-branded type). Wrapped each control in `Semantics(button: true, excludeSemantics: true, label: …)`: the four `_ActionButton`s also expose `toggled:` reflecting live controller state (torch/zoom/flip/focus-lock) so screen readers announce on/off; the doc thumbnail is `Semantics(image: true, label: pageLabel)` and its delete badge `Semantics(button: true, label: deleteLabel)`. `SupyBarcodeScannerScreen` threads its already-resolved `strings` into `SupyActionBar`. `excludeSemantics` prevents the visible `Text`/icon children from double-reading. Locked with `getSemantics` + `isSemantics` widget tests (action-bar labels + `isButton` + torch `isToggled` toggle; top-bar cancel button) and `SupyScannerStrings` unit tests (new field values en/ar, the 3 label builders, `copyWith`/`==`/`hashCode` round-trip). On-device VoiceOver/TalkBack pass deferred to the `docs/QA.md` phase walk (needs real hardware — no PlatformView on desktop). Green gate clean (root 477 + compat 11 + `dart analyze --fatal-infos`).
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
