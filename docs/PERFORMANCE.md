# PERFORMANCE — Weak-Device Optimization Plan

Scope: make `supy_scanner` smooth, OCR-fast, cool, and battery-light on a Moto G Power-class Android (Android 13, Snapdragon 662 / 4GB RAM) without regressing flagship iOS. The Android floor sets the budget; iOS inherits the same disciplines so QA stays consistent.

This plan complements (does not replace) `docs/PLAN.md`. It is the v1.1 perf workstream and slots after Sprint 2 (barcode pipeline lift) and before v1.1 sign-off.

## Why now

The current pipeline was built for parity (Phase 1–5 of `docs/PLAN.md`). It runs ML Kit Barcode and Document Detector on every camera frame at preview resolution, with no thermal guards and no idle pause. On a Moto G Power that means:

- Continuous CPU + ISP at near-100% during a scan session.
- Thermal throttling kicks in after ~3 min, dropping camera FPS and detection latency.
- 10-page OCR runs serially per page, blocking the user behind a spinner.
- Battery drain during a 5-minute receipt-capture session is observably steep (no measurement yet — see Phase 0).

Goals below are concrete and bench-measurable.

## Goals & Non-Goals

**Goals (v1.1.x)**
1. Sustain a smooth preview (≥ 24 FPS effective render) on Moto G Power across a 5-minute scanning session — no thermal-driven FPS collapse.
2. Barcode detection p50 ≤ 250 ms, p95 ≤ 600 ms on Moto G Power (tightens current QA targets).
3. 10-page document OCR end-to-end ≤ 18 s on Moto G Power (currently unmeasured; iPhone SE 3 target is 12 s per QA.md).
4. Battery drain ≤ 9% per 10-minute continuous scanning session on Moto G Power, screen-on baseline subtracted.
5. Skin temperature stays in `NOMINAL` or `LIGHT` (`Build.VERSION.SDK_INT >= S` `PowerManager.getCurrentThermalStatus`) across the same 10-minute session.

**Non-Goals**
- GPU/NNAPI custom models (out of v1.1 scope).
- Replacing ML Kit with a hand-rolled decoder.
- iOS-specific thermal tuning beyond the cross-platform discipline (iOS thermals already comfortable on SE 3 in informal tests).
- Re-litigating the Scanbot-compat API surface.

## Device-class adaptive — flagships keep their power

The optimizations below are NOT a blanket clamp. They're a tiered policy that lets flagships run unrestricted while protecting weak devices. The library reads a runtime `DeviceTier` (computed once at first scan) and applies different ceilings per tier:

| Tier | Signals | Analyzer resolution (barcode) | FPS cap | OCR concurrency | Idle behavior |
|---|---|---|---|---|---|
| `high` | iOS: `processorCount ≥ 6` AND not `thermalState ≥ .fair`. Android: API ≥ 31 AND `PerformanceHintManager` reports nominal AND `ActivityManager.isLowRamDevice == false` AND total RAM ≥ 6 GB. | preview-native | 30 (uncapped) | `cpu` | aggressive idle pause OFF |
| `mid` | not `high`, not `low`. | 960×720 | 24 | `max(2, cpu/2)` | idle pause ON, 8s threshold |
| `low` | Android: `isLowRamDevice == true` OR total RAM < 4 GB. iOS: `processorCount ≤ 4`. | 640×480 | 20 (frame-skip on load) | 2 | idle pause ON, 4s threshold |

Thermal throttling (Phase 2) applies on ALL tiers — even a flagship downgrades if the OS reports `.serious` — but a flagship at nominal thermal state runs full-throttle. This is the rule "flagship parity check" enforces in every phase exit: Pixel 8 and iPhone 15 Pro must not regress.

## Baseline first — no optimizations land before measurement

CLAUDE.md rule: don't ship "while we're here" perf changes. Every change in Phases 2–5 must move at least one metric in Phase 0's baseline.

## Phased Roadmap

Six phases. Each phase has an exit metric. No phase ships unless its exit number is measured on a Moto G Power AND a Pixel 8 (flagship parity check — we must not have made the flagship slower).

### Phase 0 — Baseline harness (3 days)
The harness already exists in skeleton: `example/integration_test/perf_bench_test.dart`. We extend it.

- Wire **Android Battery Historian** capture into the example app: `dumpsys batterystats --reset` at scenario start, dump at end, post-process to mAh delta.
- Wire **thermal sampling** on Android: poll `PowerManager.getCurrentThermalStatus()` every 5 s during a scenario, emit `BENCH_RESULT {"metric":"thermal_max","status":...}`.
- Wire **frame-time logging** on Android (CameraX `analyze` latency histogram) and iOS (`AVCaptureVideoDataOutput` delivery timestamps).
- Add three new bench scenarios:
  - `barcode_session_5min` — open scanner, sweep 50 unique barcodes over 5 min, log p50/p95 detection latency, mean FPS, mAh delta, thermal peak.
  - `document_ocr_10p` — capture-then-OCR a 10-page fixture; log capture-to-result latency, mAh delta.
  - `idle_camera_30s` — preview only, no barcodes in frame; log mAh delta (this is what dominates battery for retailer users hovering over a shelf).
- Record baseline numbers in `docs/PERFORMANCE.md` under `## Baseline (v1.0.x)`.

**Exit:** baseline table populated for Moto G Power and Pixel 8.

### Phase 1 — Analyzer downscaling + frame throttling (1 week)
The biggest single lever on a low-end Android. Right now CameraX delivers preview-resolution frames (typically 1280×720) to ML Kit Barcode and Document Detector. Detection only needs ~640×480 to clear EAN-13 from a typical retailer aim distance.

- **Android:** set `ImageAnalysis.Builder().setTargetResolution(Size(640, 480))` (or `setResolutionSelector` on CameraX 1.3+) for the barcode analyzer. Document detector keeps preview resolution.
- **iOS:** set `AVCaptureVideoDataOutput.videoSettings` width/height to 720×540 for the barcode path; document detector unchanged.
- **Frame skip under load:** drop every other frame when the analyzer's rolling p95 latency exceeds 350 ms. Recompute over a 10-frame sliding window.
- **Cap analyzer FPS at 20** on both platforms — barcode detection doesn't need 30 FPS and the bottom 10 FPS are pure heat.

**Exit:**
- Barcode detection p50 down ≥ 30% vs. Phase 0 baseline on Moto G Power.
- No measurable regression in barcode detection rate per QA.md B1 scenario.
- Pixel 8 detection p95 unchanged (no flagship regression).

### Phase 2 — Thermal-aware throttling (1 week)
Today nothing in the library reacts to device thermal state. The fix is a small `ThermalGovernor` that adjusts analyzer FPS and the document detector's frame stride based on the OS thermal signal.

- **Android:** subscribe to `PowerManager.addThermalStatusListener` (API 29+). On `MODERATE` cap analyzer FPS at 15; on `SEVERE` cap at 10 and pause the document detector entirely (barcode still works); on `CRITICAL` stop the session and emit a `thermal_pause` event.
- **iOS:** subscribe to `ProcessInfo.thermalStateDidChangeNotification`. Same ladder, mapped to `.fair` / `.serious` / `.critical`.
- Surface `thermal_pause` and `thermal_resume` events on both `SupyBarcodeScannerView` and `SupyDocumentScannerView` EventChannels — retailer-side UI can show a toast instead of guessing why scans stopped.
- Update `docs/ARCHITECTURE.md` event table.

**Exit:** Moto G Power 10-minute continuous scan stays in `NOMINAL` or `LIGHT`; no `SEVERE` hits in 3 consecutive runs.

### Phase 3 — Idle pause + duty cycling (4 days)
Battery dominates when the user is hovering — preview is running but no barcode is in view. We can pause the analyzer (not the preview layer) after N seconds of "no detectable anything in frame."

- **Idle detector:** Cheap luma-variance check on the preview frame (no ML). If variance < threshold for 4 s continuously, drop analyzer FPS to 5. Resume to 20 the moment a barcode candidate is detected OR luma variance recovers.
- **Torch auto-off advisory**: when `IdleDetector` flips to idle and torch is on, native emits `{type: 'torch_idle_suggested'}` alongside `idle_pause`. Consumer decides whether to call `setTorch(false)`; library never toggles torch silently (Scanbot-compat preserves user agency). Fires on the first idle transition — the `idlePauseThresholdMs` gate is the dwell.
- **Camera release on background:** ensure `viewWillDisappear` / Android `onPause` releases the camera within 200 ms — verify no leaked AVCaptureSession / CameraX use case via QA B9.

**Exit:** mAh delta on `idle_camera_30s` scenario down ≥ 40% vs. Phase 0 baseline. No regression in B1 (open & first detect within 1 s).

### Phase 4 — Document OCR downscale + per-page memory budget (1 week)
OCR already runs concurrently per page on both platforms (Android: `Dispatchers.Default` pool; iOS: bounded `DispatchSemaphore`). The remaining lever is the **per-page memory and decode cost**: receipts captured at 4032×3024 force the recognizer to chew through ~36 MP of bitmap per page. The fix is downscale + tier-aware JPEG quality, not more parallelism.

- **Image downscaling for OCR (tier-tiered):** HIGH → no downscale (flagship keeps full resolution), MID → 1600 px long edge, LOW → 1280 px long edge. Applied before handing pages to the recognizer; the consumer's `pages` return value still carries the persisted JPEGs. Confirm with the D6/D7 QA scenarios.
- **JPEG-quality cap on LOW tier:** consumer-requested quality is capped at 75 on LOW; MID/HIGH pass through the request (default 85). Confirm D8 still passes (< 500KB per page on LOW).
- **Bound peak memory:** OCR pool size already caps concurrent decodes; with downscale this drops peak heap from ~360 MB (10×36 MP) to ~25 MB (10×2.5 MP) — meaningful on 4 GB-RAM Android.

**Exit:** 10-page OCR end-to-end ≤ 18 s on Moto G Power, ≤ 10 s on iPhone SE 3 (tightens QA.md current 12s target).

### Phase 5 — Hardening + sign-off (3 days)
- Re-run all baseline scenarios on Moto G Power, Pixel 8, iPhone SE 3, iPhone 15 Pro. Record `## Results (v1.1.x)` table.
- Re-run QA.md B1, B8, B9, B13, D1, D2, D3, D6 on Moto G Power — make sure nothing regressed.
- Document the `thermal`, `idle_pause`/`idle_resume`, and `torch_idle_suggested` events in `docs/ARCHITECTURE.md` and `docs/MIGRATION.md` (retailer consumer needs to know how to handle them — backwards-compatible: ignoring them is a valid choice).
- Bump version to `v1.1.x`, tag, ship.

**Exit:** all five goals at the top of this doc met or beaten on Moto G Power; flagship metrics unchanged or better.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Frame downscaling drops detection of small Code-128 / DataMatrix at the back of long aisles. | Medium | Phase 1 keeps document detector at preview resolution; barcode path gets a `setAnalyzerResolution()` knob the retailer can override per scan flow. |
| Thermal pause events confuse the retailer-side UX. | Low | Phase 2 events are advisory — library still works if the consumer ignores them. Update `docs/MIGRATION.md`. |
| Idle pause masks a real "user is aiming at a small/distant barcode" case. | Medium | Idle detector resumes the moment luma variance recovers (Phase 3) — re-arm latency budgeted at < 100 ms. Validate with B1 timing. |
| Parallel OCR causes OOM on 2GB-RAM devices. | Low | Pool size capped at `cpu/2`; OCR images downscaled before recognition. Add an OOM-handler that falls back to serial on `OutOfMemoryError`. |
| ML Kit model download competes with first-launch perf. | Existing | Out of scope — already covered by `prewarm()` in `docs/PLAN.md` Phase 5. |

## Verification

Each phase exits only when:

1. The exit metric is met on Moto G Power.
2. Pixel 8 / iPhone 15 Pro show no regression vs. Phase 0 numbers.
3. The relevant QA.md scenarios for that phase pass on both platforms.
4. CI green (`flutter analyze`, `flutter test`, `dart format`, example builds on both platforms).

The bench command remains:

```
cd example
flutter test integration_test/perf_bench_test.dart --profile -d <device-id>
```

## Baseline (v1.0.x)

_To be populated in Phase 0._

| Metric | Moto G Power | Pixel 8 | iPhone SE 3 | iPhone 15 Pro |
|---|---|---|---|---|
| `barcode_session_5min` p50 detection (ms) | _pending_ | _pending_ | _pending_ | _pending_ |
| `barcode_session_5min` p95 detection (ms) | _pending_ | _pending_ | _pending_ | _pending_ |
| `barcode_session_5min` mean analyzer FPS | _pending_ | _pending_ | _pending_ | _pending_ |
| `barcode_session_5min` mAh / minute | _pending_ | _pending_ | n/a (iOS) | n/a (iOS) |
| `barcode_session_5min` thermal peak | _pending_ | _pending_ | _pending_ | _pending_ |
| `document_ocr_10p` end-to-end (s) | _pending_ | _pending_ | _pending_ | _pending_ |
| `idle_camera_30s` mAh delta | _pending_ | _pending_ | n/a (iOS) | n/a (iOS) |

## Results (v1.1.x)

_Populate during P5 re-bench. One row per metric; cells stay `_pending_` until the device run lands. Deltas are vs. the Baseline table above — green if Δ ≤ 0 (lower is better) for latency/mAh, Δ ≥ 0 for FPS._

### Bench protocol (P5)

1. Charge each device to ≥ 80 %, unplug, set brightness to 50 %, airplane mode on (Wi-Fi off too — bench must not race ML Kit model downloads; ensure models are pre-warmed once before disabling network).
2. Cool device to ambient (room temp ~22 °C). Confirm thermal state `nominal` in the example app's debug overlay before each scenario.
3. Build the example app in profile mode: `cd example && flutter build apk --profile` / `flutter build ios --profile --no-codesign`.
4. Run `flutter test integration_test/perf_bench_test.dart --profile -d <device-id>` per scenario, three trials each. Record the **median** of the three.
5. Capture battery delta via `adb shell dumpsys batterystats` (Android) / Xcode Energy gauge (iOS, qualitative — table cell is `n/a (iOS)`).
6. Note thermal peak observed during the 5-minute scenario via the `thermal` event stream.
7. If any cell regresses vs. Baseline by > 10 %, file an issue and block the `v1.1.0` tag.

| Metric | Moto G Power | Pixel 8 | iPhone SE 3 | iPhone 15 Pro |
|---|---|---|---|---|
| `barcode_session_5min` p50 detection (ms) | _pending_ | _pending_ | _pending_ | _pending_ |
| `barcode_session_5min` p95 detection (ms) | _pending_ | _pending_ | _pending_ | _pending_ |
| `barcode_session_5min` mean analyzer FPS | _pending_ | _pending_ | _pending_ | _pending_ |
| `barcode_session_5min` mAh / minute | _pending_ | _pending_ | n/a (iOS) | n/a (iOS) |
| `barcode_session_5min` thermal peak | _pending_ | _pending_ | _pending_ | _pending_ |
| `document_ocr_10p` end-to-end (s) | _pending_ | _pending_ | _pending_ | _pending_ |
| `idle_camera_30s` mAh delta | _pending_ | _pending_ | n/a (iOS) | n/a (iOS) |
| **Tier resolved** (HIGH/MID/LOW) | _pending_ | _pending_ | _pending_ | _pending_ |
| **Idle pauses observed** (count / 5 min) | _pending_ | _pending_ | _pending_ | _pending_ |
| **Thermal throttle entered?** (Y/N) | _pending_ | _pending_ | _pending_ | _pending_ |

### Sign-off checklist

- [ ] All five top-of-doc goals met on Moto G Power.
- [ ] No regression > 5 % on Pixel 8 / iPhone 15 Pro vs. Baseline.
- [ ] QA.md B1, B8, B9, B13, D1, D2, D3, D6 re-run on Moto G Power — all pass.
- [ ] `thermal`, `idle_pause`/`idle_resume`, `torch_idle_suggested` events documented in `docs/MIGRATION.md`.
- [ ] CHANGELOG entry for `v1.1.0` lists tier-adaptive analyzer, thermal governor, idle pause, OCR downscale.
- [ ] Tag `v1.1.0`, push, update retailer-app consumer pin.

## Out-of-Scope Follow-ups

- GPU-accelerated analyzer (Vulkan compute / MetalPerformanceShaders) — only if Phase 1–4 don't hit the goals.
- NNAPI delegate for ML Kit on Android — depends on Google's ML Kit roadmap.
- A custom on-device barcode decoder — would remove ML Kit but is a large engineering bet; revisit if ML Kit becomes a binary-size or perf bottleneck we can't tune around.
