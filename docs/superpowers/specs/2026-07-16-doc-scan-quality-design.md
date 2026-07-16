# DSQ — Document Scan Quality: Beat Scanbot

**Date:** 2026-07-16
**Status:** Approved design, pending implementation plan
**Approach:** A — "Bench-first quality ladder" (user-approved)

## Goal

Make `supy_scanner`'s document scanning measurably beat Scanbot SDK on detection cleverness and output image quality, on the **embedded first-party path** (`SupyDocumentScannerView` + custom activities — the CSU track), proven by a labeled side-by-side bench, not by eyeball.

User-locked scope decisions:

- **Target path:** embedded first-party scanner path (not the system VisionKit/GMS path — though several improvements reach it for free).
- **Detection:** add ML detection on both platforms (build the model infra; sourcing per the locked 2026-06-17 decision in `docs/V1.1_PLAN.md` §9).
- **Image quality:** all four capabilities — (a) max-res capture + full enhance, (b) shadow & glare removal, (c) grayscale + B&W binarization output modes, (d) multi-frame / super-res capture.
- **Success gate:** measured side-by-side bench vs. Scanbot (quad IoU, detection rate, OCR CER, latency, sharpness).

## Program structure

Five phases, DSQ0–DSQ4. Every phase is flag-gated and bench-gated: it merges dark, and its default flips only when the DSQ0 scoreboard shows a win on the target subset with no regression >±2% elsewhere and size/latency budgets holding (≤22 MB/ABI Android, ≤25 MB iOS).

| Phase | Ships | Gate metric |
|---|---|---|
| DSQ0 | Bench harness + labeled corpus + Scanbot baseline | n/a (infrastructure) |
| DSQ1 | Max-res capture, enhance in embedded path, unified warp, ≥300 DPI policy | Sharpness / DPI / CER on full corpus |
| DSQ2 | ML detection + classical fusion + temporal tracking | Quad IoU + detection rate, esp. hard subsets |
| DSQ3 | Shadow removal, grayscale + B&W output modes | CER on shadowed/glossy subsets |
| DSQ4 | Multi-frame: sharpest-of-N → fusion → ROI super-res (each rung conditional) | CER on low-light / small-text subsets |

## DSQ0 — Scoreboard first

**Corpus.** `bench/corpus/` in Git LFS, ~120 scenes: thermal/crumpled receipts, A4 invoices, glossy menus × cluttered/plain backgrounds × good light / dim / shadow / glare. Each scene: raw frame + hand-labeled normalized quad JSON + ground-truth text + Scanbot output image (captured once via the retailer app; user-owned, ~half a day of manual work — the only manual dependency in the program).

**Harness.** `tools/bench/` host Dart CLI, following the existing perfgate pattern:

- **Detection bench:** runs the native detector (host-built `supy_scanner_core`) over corpus frames → quad IoU vs. labels, detection rate, per-category breakdown. Runs in CI via the existing host native build.
- **Output bench:** OCR character error rate (macOS Vision via a small Swift CLI), sharpness (variance-of-Laplacian), illumination uniformity, effective DPI. Full runs on device via integration tests; CI runs a host "pipeline replay" mode (decode → warp → enhance → encode on corpus stills).
- Emits `bench_report.md` with deltas vs. pinned baselines (Scanbot's numbers and our own previous phase).

**"Beats Scanbot" definition:** win the gate metric on the relevant subset, no regression >±2% on any other metric, within size budgets.

## DSQ1 — Max-res capture + enhance in the embedded path

The embedded path today captures at default photo settings and applies **zero enhancement** (iOS warps and JPEG-encodes at 0.95; Android runs `PageReencoder` but iOS default is OFF). This phase closes the gap with the cheapest wins.

- **(a) Max-res stills.** iOS: `maxPhotoDimensions` = device max, `photoQualityPrioritization = .quality` on the photo output (analyzer stream unchanged); re-verify `PreviewPhotoQuadMapper`'s centered-crop FOV model at the new dimensions. Android: `CAPTURE_MODE_MAXIMIZE_QUALITY` behind the flag, tier-gated via `DeviceTier` if latency blows the budget.
- **(b) Enhance on iOS embedded.** Wire `SupyNativeCoreBridge.enhanceImage`/`scoreImage` into `DocumentRectifyPipeline` post-warp, exactly as the system-scanner path (`DocumentScannerPresenter`) already does. Embedded-iOS default `enhanceMode` becomes `balanced` (matching Android) — **behavior change, logged in `TODO.md` decisions section**.
- **(c) Unified warp + DPI policy.** iOS switches from `CIPerspectiveCorrection` to the shared `supy_core_warp` (flag-gated; kills the documented iOS/Android divergence, `ARCHITECTURE.md:212`). New ≥300 DPI output-size policy in C++: physical-size prior from the quad, clamp to source resolution, never upscale.
- **(d) Metadata parity.** Android gains `quadSource`; both platforms emit `enhancedStages` bitmask + quality score on `SupyDocumentCapture`.

**Error handling:** enhance failure → un-enhanced warp + `quality: unknown`; max-res capture failure → one retry at default settings. No new error codes; every failure falls back to current behavior.

## DSQ2 — ML detection ("ML proposes, geometry disposes")

**Model.** HED-int8 per the locked sourcing decision: base weights `s9xie/hed` (BSD-3), Caffe→ONNX→CoreML (iOS) / TFLite int8 (Android), quantized in-house, blobs pinned in-repo, no runtime downloads, ≤4 MB combined iOS. Trimmed to ≤3 MB; input 256×256 letterboxed grayscale → edge-probability map. Fine-tuning is decision-gated by bench results: synthetic compositor in `tools/models/synth/` (documents composited over cluttered backgrounds with shadows/perspective) first, SmartDoc-2015 as fallback. Escape hatch if edge maps underperform on receipts: a compact document-mask segmentation net under the same architecture-agnostic infra.

**Runtime.** CoreML on iOS; bundled TFLite-XNNPACK int8 on Android (~1.5 MB). Shared C++ pre/post-processing: new C ABI `supy_core_ml_pre` (letterbox/normalize) and `supy_core_ml_quads` (edge map → contour → quad candidates + confidences). The conv engine is per-platform; everything around it is shared and unit-testable.

**Fusion pipeline.**

1. ML proposes coarse quads (every Nth analyzer frame, N by `DeviceTier`; every still).
2. Classical refinement snaps edges: band-limited Sobel/Hough search in a narrow band around the ML boundary (reuses `document_edge_detector` machinery).
3. Temporal tracker: IoU-gated identity across frames, confidence-weighted quad smoothing, tolerance for partial visibility (hand over document edge).
4. Still capture: preview quad seeds `DocumentStillRefiner` as a prior instead of blind re-detection.
5. iOS keeps `VNDetectDocumentSegmentationRequest`/`VNDetectRectanglesRequest` as a parallel proposal source into the same fusion scorer.

**Fallback & API.** Model load/inference failure → classical path exactly as today. `quadSource` gains additive values `ml`, `mlRefined`. New `SupyDocumentScanOptions.detectorMode`: `auto | classical | ml`, default `auto`.

**Testing.** GoogleTest golden edge-maps + NULL-safety for the new ABIs; CoreML/TFLite-vs-ONNX parity harness on 20 corpus frames (max per-pixel drift threshold); detection bench is the CI phase gate.

## DSQ3 — Shadow removal + output modes

**Shadow removal (color-preserving), OpenCV-free:**

- Low-resolution shadow **gain map** on luma via the existing large-kernel morphological-closing background estimator (`morphology.cpp`), tuned at a coarser scale for soft cast shadows.
- Edge-aware refinement with a small hand-rolled **guided filter** (guided by luma) to prevent halos at shadow boundaries — the piece the current illumination flatten lacks.
- Chroma-preserving application: scale RGB by luma-gain ratio, clamp paper toward white; colored logos/stamps keep their color.
- New stage bit `0x80 SUPY_ENHANCE_STAGE_SHADOW`, on in `balanced`+ for the embedded path, tier-budgeted. Finlayson-Drew-Lu stays deferred per the 2026-06-26 ruling; revisit only if the shadowed-subset CER gate fails.

**Output modes cross-platform** (today `filter` is iOS-only Swift; Android ignores it). Implement once in the C++ core, post-enhance / pre-encode:

- `grayscale`: BT.601 luma from enhanced RGBA → single-channel JPEG.
- `blackAndWhite`: Sauvola adaptive binarization via the existing `supy_core_binarize_luma` ABI (Halide-AOT swap from V1-S2-05.2 slots in later under the same contract), window ≈3× estimated glyph height (from the top-hat SE math) → **PNG** output (JPEG ringing destroys binarized pages).
- iOS Swift `DocumentEnhancer` filter code retires in favor of the native implementation (flag-gated one release, then removed). The VisionKit path gets cross-platform filters for free.
- **OCR guard:** `OcrRunner` always consumes the pre-binarization enhanced image, even when the user requests `blackAndWhite` output.

**API:** no new Dart types — `SupyDocumentFilter` already has the values; Android stops ignoring it. `blackAndWhite` → PNG page files documented in `MIGRATION.md` + `ARCHITECTURE.md`. Multi-output URIs per page (color + B&W from one capture) stays deferred (v2 list).

**Testing:** synthetic soft-shadow gradient flattened ≥70% with chroma delta ≤ threshold on colored patches; guided-filter edge-preservation test; Sauvola golden images on synthetic text; NULL-safety. Phase gate: CER on shadowed + glossy subsets beats Scanbot's shadow-removal output. `docs/QA.md` gains shadow/B&W scenarios.

## DSQ4 — Multi-frame capture & super-res (conditional)

Runs only if the DSQ0–3 bench still shows a gap on low-light / small-text subsets. Three rungs, each bench-gated before the next:

1. **Sharpest-of-N** (ships first, low risk): burst of N=3 on shutter (iOS sequential `AVCapturePhotoOutput` stills; Android CameraX `takePicture` ×3), score each with the existing frame scorer, keep the sharpest. ~300–500 ms budgeted latency, tier-gated (high tier by default). Pure reuse.
2. **Aligned temporal fusion** (conditional): warp all N frames to the document plane via per-frame quads, per-pixel median/weighted-average merge in a new C++ `temporal_fuse` stage. Frames with quad IoU < 0.95 vs. the best frame are rejected → graceful degradation to rung 1.
3. **FSRCNN ROI super-res** (conditional, last): FSRCNN-int8 per locked sourcing (`Saafke/FSRCNN_Tensorflow`, MIT), second consumer of the DSQ2 model infra — zero new runtime. Rectified-document ROI only, ×2, never full-frame. Model ≈40 KB int8.

**API:** `SupyDocumentScanOptions.captureStrategy`: `single | burst`, default `single` until the bench proves the win. Fusion/super-res are internal stages behind the same flag. Any burst-path failure → silent fallback to single-shot; quality metadata reports `captureStrategy: single`.

**Testing:** fusion determinism + misalignment-rejection goldens; scorer-picks-sharpest synthetic; low-light bench subset is the phase gate; device latency in the perf bench (`perf_bench_test.dart` pattern).

## Cross-cutting

**Public API summary (all additive, channel stays `io.supy.scanner/v1`):**

| Surface | Change | Phase |
|---|---|---|
| `SupyDocumentScanOptions.detectorMode` | new: `auto \| classical \| ml` | DSQ2 |
| `SupyDocumentScanOptions.captureStrategy` | new: `single \| burst` | DSQ4 |
| `enhanceMode` embedded-iOS default | `off` → `balanced` (behavior change) | DSQ1 |
| `SupyDocumentFilter` | honored on Android; native impl both platforms | DSQ3 |
| `SupyDocumentCapture.quadSource` | Android gains it; new values `ml`, `mlRefined` | DSQ1/DSQ2 |
| `SupyDocumentCapture` quality metadata | `enhancedStages` bitmask + score, both platforms | DSQ1 |

Every new channel arg key / value gets its `docs/ARCHITECTURE.md` table row in the same PR (house rule). Scanbot compat: zero breaking changes; the one observable behavior change (embedded-iOS enhancement default) gets a `TODO.md` decisions-log entry + `MIGRATION.md` note.

**Top risks & mitigations:**

- ML model quality on receipts → fine-tune path + segmentation escape hatch + full classical fallback (DSQ2).
- iOS warp switch changes output pixels → flag-gated, bench parity check before default flip (DSQ1).
- Corpus labeling effort → Scanbot capture is user-owned (~half day); all other corpus tooling is scripted.

**House rules honored throughout:** no paid SDKs, no cloud OCR / network in the scan path, OpenCV-free hand-rolled C++ core, iOS 16 deployment target, `AVCaptureSession` work off-main, ML Kit clients closed in `dispose()`, conventional commits, QA.md walked on one Android + one iPhone per phase.
