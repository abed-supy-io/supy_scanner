# Supy-Owned Document Scanner — Beat & Replace Scanbot (Phase CSU)

- **Date:** 2026-07-03
- **Status:** Approved (design review with product owner)
- **Phase:** v1.2 Phase CSU (custom scanner UI) — already scoped in `TODO.md`; this spec pins the architecture and exit criteria.

## Context

supy_scanner v1.0 reached feature parity with Scanbot by delegating the document path to system UIs: GMS Document Scanner on Android, VisionKit (`VNDocumentCameraViewController`) on iOS. That capped quality and UX at whatever Google/Apple ship: no proximity guidance ("move closer / move farther"), no control over the capture moment, washed-out VisionKit output (CHANGELOG already carries a "regressed vs Scanbot" fix bumping JPEG 85→95).

Meanwhile v1.1/v1.2 built all the hard parts in the shared C++ core (`native/`):

- **Detector** — `native/document/document_edge_detector.cpp`: downsample → blur → Sobel → adaptive Canny → Hough → quad scoring (OpenCV-free).
- **Guidance FSM** — `native/document/document_guidance_classifier.{h,cpp}`: 13 wire-stable states incl. `tooClose`, `tooFar`, `glare`, `occluded`, `handShake`, `edgeClipped`, `offCenter`; EMA smoothing, dwell, hysteresis, live quality score. Bridged on iOS (`SupyNativeCoreBridge.mm`, dormant) and on Android for the CameraX fallback (`supy_scanner_core_jni.cpp`).
- **Warp** — `native/document/perspective_warp.cpp` (8-DOF homography, bilinear).
- **Enhance** — `native/enhance/` (illumination flatten, specular clamp, top-hat, CLAHE, tone, unsharp; modes off/fast/balanced/max) + iOS `DocumentEnhancer.swift` Core Image chains.
- **Scorer** — variance-of-Laplacian page quality bucket + 0..1 score (in-flight Sprint 7).
- **Capture** — `captureAndRectify` / `captureFullFrame` on both embedded PlatformViews.

**This phase assembles those parts into a Supy-owned full-screen scanner that becomes the default document path, then proves it beats Scanbot and removes the dependency.**

## Decisions (product owner, 2026-07-03)

1. **Supy scanner is the default** document backend. GMS/VisionKit modals remain reachable by explicitly passing the existing `preferredBackend` values (`gms`/`cameraX`) as the kill-switch; a new additive `supy` backend value is introduced. `resolvedBackend` reports what ran.
2. **Minimal review UI**: thumbnail strip, per-page retake/delete, quality badge, Done. Manual crop-handle editor, rotate, reorder → deferred phase.
3. **Proof stack**: side-by-side bench vs Scanbot + `docs/QA.md` walkthrough + retailer-app pilot, all before deleting Scanbot from the retailer app.
4. **iOS first**, Android parity next.
5. **Architecture: Flutter chrome + native capture.** `launch()` pushes a Flutter route; Dart draws hints/nudges/countdown/thumbnails; the per-OS PlatformViews keep camera, detection, C++ guidance, overlay, and capture native.

## Success criteria (exit gate for removing Scanbot)

| Metric | Method | Target |
|---|---|---|
| Time-to-auto-snap | steady doc in frame → shutter, bench fixture set | p50 ≤ 1.2 s, p95 ≤ 2.5 s (MID tier) |
| Crop accuracy | corner IoU vs hand-labeled ground truth, fixture set (receipt, A4 invoice, ~50 lux, textured table, hand-held) | ≥ Scanbot on same set |
| Output readability | OCR CER on retailer invoice corpus (supy output vs Scanbot output of same physical docs) | ≤ Scanbot CER |
| Low-light | auto-snap success rate at ~50 lux | ≥ Scanbot |
| Guidance correctness | QA scenarios per state (correct hint for staged condition) | 100% of staged scenarios |
| Perf regressions | existing perfgate suite | within `kP95RegressionTolerance` (15%) |

Scanbot-side numbers are collected in a retailer A/B build while its license is still active. Results recorded in `docs/QA.md`.

## Architecture

```
SupyDocumentScanner.launch(options)                       [Dart, signature unchanged]
  ├─ preferredBackend gms/cameraX → GMS / VisionKit modal  [kill-switch, unchanged]
  └─ default (supy) → Navigator push SupyDocumentScannerScreen (Flutter route)
       ├─ Dart chrome: hint chip (13 states, en/ar), nudge arrows, countdown ring,
       │  thumbnail strip, shutter (manual fallback), torch, done/cancel
       └─ PlatformView (existing SupyDocumentScannerView, per OS)
            ├─ camera preview + native quad overlay (red→amber→green)
            ├─ detection: Vision (iOS) / C++ detector (Android)
            ├─ C++ guidance classifier → state + liveQualityScore via frame_metrics
            └─ captureAndRectify: full-res photo → on-still quad refinement
               → C++ warp → enhance → score → persist JPEG/PNG → page payload
```

- **Auto-capture orchestration lives in Dart**: on `ready` (C++ FSM already enforces `readyStableFrames` dwell), start tier-aware countdown (existing floors LOW 1200 / MID 800 / HIGH 600 ms), then call `captureAndRectify`. Manual shutter always available; with no quad it falls back to `captureFullFrame`.
- **Single source of truth for guidance is the C++ classifier** on both platforms. The Dart FSM becomes a fallback only (removed from the hot path once Android JNI wiring lands — pending FQS item).
- **No new MethodChannel methods expected.** `captureAndRectify`, `captureFullFrame`, `frame_metrics`, guidance config via creationParams all exist. Any addition discovered during implementation goes through `supy-scanner:add-channel-method` (doc table + Dart wrapper + both handlers + mocked test).

### On-capture quad refinement (new native work, both platforms)

Warping the full-res still with a preview-resolution quad limits crop sharpness. New step inside `captureAndRectify`:

1. Map last stable preview quad → photo coordinate space (respecting aspect-fill crop, rotation, mirroring).
2. Re-detect on the still: iOS via `VNDetectDocumentSegmentationRequest` on the photo; Android via the C++ detector (it self-downsamples).
3. Accept the refined quad if IoU(refined, mapped-preview) ≥ 0.8; otherwise use the mapped preview quad. Never fail the capture because refinement failed.

### Output pipeline defaults

- JPEG quality 95 (LOW tier clamp 88) — already in-flight.
- Enhancement default decided by the bench in Sprint 4: iOS `DocumentEnhancer .color` vs C++ `balanced` (whichever wins CER/readability on the corpus becomes the per-platform default; the other remains selectable via `enhanceMode`).
- Additive `filter` option on `SupyDocumentScanOptions` (`color | grayscale | blackAndWhite | original`) — already in-flight on the Dart and iOS sides — so Scanbot compat filter args map to real output. iOS chains exist in `DocumentEnhancer.swift`; Android gets grayscale + Sauvola binarize output stages in `native/enhance/` (Sauvola already exists in the barcode path). Channel arg documented in `docs/ARCHITECTURE.md` table.

## Compat surface impact (flagged per CLAUDE.md)

- **No existing prop renamed, no new required argument, no return-type change.** `SupyDocumentData`/`SupyDocumentPage` unchanged (Sprint 7 additive fields ride along).
- **Zero retailer integration steps** (amended 2026-07-03 after code inspection): `SupyDocumentScanner.startMultiPage()` already receives a `BuildContext`, so the supy path pushes its route via `Navigator.maybeOf(context)`. If no `Navigator` is reachable from the caller's context → log a warning and fall back to the system backend (never crash, never change the call-site contract). No `navigatorKey` needed. Default-backend change + kill-switch documented in `docs/MIGRATION.md`; decision logged in `TODO.md` decisions section.
- In the supy path, the CQG-G2 low-quality modal alert is replaced by an inline thumbnail badge + retake affordance. The VisionKit/GMS kill-switch path keeps the alert. (Logged as a decision.)

## Workstreams

### WS1 — iOS capture completion (Sprint 1)

- Dart defers to `nativeState` from the C++ classifier (already emitted in `frame_metrics`).
- Auto-capture on iOS (first time): dwell countdown → `captureAndRectify` (`SupyDocumentScannerView.swift`); verify preview→photo coordinate mapping under aspect-fill + all orientations with fixture-image unit tests.
- On-still quad refinement (above).
- Session start/stop stays on the background queue; Vision on background queue (existing conventions, iOS 16 rectangles fallback preserved).

### WS2 — Dart scanner screen (Sprint 2)

- `SupyDocumentScannerScreen` (new, `lib/src/document/ui/`): full-bleed PlatformView + chrome; reuses in-flight hint copy, nudge arrows, `SupyScannerPalette` tokens; RTL/Arabic supported.
- Minimal review: thumbnail strip during capture, page-count badge, tap → preview sheet with retake/delete, quality badge from per-page score, Done → `SupyDocumentData`.
- `startMultiPage()` routing via the caller's `BuildContext` (`Navigator.maybeOf`) + graceful system-backend fallback; new additive `supy` value on `SupyDocumentScannerBackend` (existing wire values `gms`/`cameraX` remain the kill-switch).
- Cancel returns `[]` (pins existing QA D4 contract); backgrounding pauses/resumes the session; capture errors keep the session alive with a retry hint (precedent: `captureFullFrame` hardening commit 5a652f0).

### WS3 — Android parity (Sprint 3)

- Embedded view guidance switches from Dart FSM to C++ classifier via JNI (pending FQS item; bridge already exists for the CameraX activity path).
- On-still quad refinement via the C++ detector; warp already JNI-wired.
- `DocumentScannerLauncher` routes default → Flutter screen; GMS behind `preferredBackend: system`; `CameraXDocumentScannerActivity` remains as shipped (internal fallback), no longer the headline path.
- Grayscale/binarize output stages in `native/enhance/` + `filter` arg mapping in `PageReencoder.kt`.

### WS4 — Proof & removal (Sprint 4)

- Bench harness: extend `tools/perfgate` + an example-app A/B screen; fixture set + labeled corners checked into `example/`; metrics per the success-criteria table.
- New `docs/QA.md` scenarios: full supy scan flow, one per guidance state (staged glare/tilt/distance/shake/occlusion), review strip actions, kill-switch fallback, permission-denied, cancel, backgrounding.
- Retailer pilot build; feedback loop; on exit criteria met → flip retailer to supy scanner and delete the Scanbot dependency (`supy-scanner:cut-a-release` for the version cut).

## Error handling summary

| Case | Behavior |
|---|---|
| Camera permission denied | Same error codes as current launcher paths (unchanged contract) |
| Cancel mid-scan | Return `[]`, not an error (QA D4) |
| No `Navigator` reachable from caller's context | Warn once, fall back to system backend |
| Capture/decode failure | Stay in session, show retry hint (no silent drop, no crash) |
| Refinement quad implausible | Fall back to mapped preview quad |
| Manual shutter with no quad | `captureFullFrame` (unwarped page) |
| Backgrounded mid-scan | Pause session, resume on foreground, pages retained |

## Testing

- **Unit:** coordinate mapping (preview→photo) with fixture images per orientation; refinement accept/reject thresholds; filter arg mapping; `toConfigFloatArray` round-trip. C++ classifier scenarios already pinned in `document_guidance_classifier_test.cpp`.
- **Widget (Dart):** scanner screen states (hint per FSM state, countdown, review actions, cancel semantics) with a mocked channel.
- **Integration:** extend `example/integration_test/document_use_case_test.dart` for the supy path + kill-switch path.
- **Bench + QA + pilot:** per WS4; phase is *done* only when `docs/QA.md` scenarios pass on one Android + one iPhone (CLAUDE.md rule) and the bench table beats/meets Scanbot.

## Out of scope (deferred, logged as future phase entries)

- Manual crop-handle editor, rotate, page reorder (Scanbot RTU full-editor parity).
- ML/HED edge detection on Android — revisit only if the bench shows the classical detector losing on crop accuracy.
- Motion deconvolution / FSRCNN SR (v1.1 Sprint 3 stays deferred).
- Invoice extraction (Phase IXP) — unrelated lab feature.

## Docs to update in-phase

`docs/PLAN.md` (phase entry), `TODO.md` (CSU sprint checklist + two logged decisions), `docs/ARCHITECTURE.md` (filter arg row, backend routing diagram), `docs/MIGRATION.md` (default-backend change + kill-switch), `docs/QA.md` (new scenarios + bench results), `CHANGELOG.md`.
