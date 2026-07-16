# supy_scanner — 3-Year Backlog

Grounded backlog: every entry traces to a line in `docs/PLAN.md`, `TODO.md`, `docs/ARCHITECTURE.md`, or another doc under `docs/`. Nothing speculative — items either close out an open TODO, complete an explicitly-scoped Phase, or pick up a Post-v1.2 candidate already noted in PLAN.md §7.

## Conventions

- `core-*` — scanner pipeline (barcode, document, OCR, capture UI).
- `adj-*` — adjacent scanning capabilities flagged in PLAN.md §7 follow-ups.
- `infra-*` — native core, performance, CI, platform expansion, security tooling.
- `dx-*` — Dart API, compat shim, sample app, codegen, docs.
- `ml-*` — on-device ML track that augments the items above. Lifecycle, runtime, and per-axis models. All on-device per CLAUDE.md (no cloud).

Each file follows: **Problem · Scope · Out of scope · Acceptance · Dependencies · Source**.

> **Working priority lives in [PRIORITY.md](PRIORITY.md)** — tiered P0–P8 with the rationale per item. The horizon below is a rough year-bucket grouping; use `PRIORITY.md` when sequencing actual sprint work.

## Horizon at a glance

### Year 1 (close v1.1, ship v1.2) — H2 2026 → H1 2027
Finish open v1.1 Sprint 2 / perf tickets, complete Phase CXD (CameraX document fallback), and Phase DIE (document image enhancement) perf bench.

- [core-zxing-ios-bridge](core-zxing-ios-bridge.md)
- [core-libdmtx-android-roi](core-libdmtx-android-roi.md)
- [core-libdmtx-ios-bridge](core-libdmtx-ios-bridge.md)
- [core-adaptive-binarization](core-adaptive-binarization.md)
- [core-temporal-median-fusion](core-temporal-median-fusion.md)
- [core-perf-gate-harness](core-perf-gate-harness.md)
- [core-cxd-availability-gate](core-cxd-availability-gate.md)
- [core-cxd-camerax-activity](core-cxd-camerax-activity.md)
- [core-cxd-auto-snap](core-cxd-auto-snap.md)
- [core-document-image-enhance-bench](core-document-image-enhance-bench.md)
- [infra-tier-debug-override](infra-tier-debug-override.md)
- [infra-baseline-perf-publish](infra-baseline-perf-publish.md)
- [dx-compat-shim-retailer-pin](dx-compat-shim-retailer-pin.md)
- [dx-flutter-action-sha-pin](dx-flutter-action-sha-pin.md)

### Year 2 (ship v1.3 custom UI, perf + reliability) — H2 2027 → H1 2028
Phase CSU (custom scanner UI) end-to-end, reliability stress harness, image-filter pipeline, device-runner matrix.

- [core-csu-ios-avcapture](core-csu-ios-avcapture.md)
- [core-csu-android-camerax-default](core-csu-android-camerax-default.md)
- [core-csu-classifier-plumbing](core-csu-classifier-plumbing.md)
- [core-csu-options-plumbing](core-csu-options-plumbing.md)
- [core-csu-result-parity](core-csu-result-parity.md)
- [core-multi-page-review-sheet](core-multi-page-review-sheet.md)
- [core-image-filter-pipeline](core-image-filter-pipeline.md)
- [core-ocr-languages-expansion](core-ocr-languages-expansion.md)
- [infra-reliability-stress-ci](infra-reliability-stress-ci.md)
- [infra-device-runner-matrix](infra-device-runner-matrix.md)
- [infra-halide-aot-kernels](infra-halide-aot-kernels.md)
- [infra-sbom-cyclonedx](infra-sbom-cyclonedx.md)
- [infra-symbolication-pipeline](infra-symbolication-pipeline.md)
- [infra-on-demand-subsystems](infra-on-demand-subsystems.md)
- [dx-format-mapping-codegen](dx-format-mapping-codegen.md)
- [dx-example-batch-throughput](dx-example-batch-throughput.md)
- [dx-telemetry-sink-interface](dx-telemetry-sink-interface.md)
- [dx-sprint8-migration-cookbook](dx-sprint8-migration-cookbook.md)

### Year 3 (platform expansion, adjacencies) — H2 2028 → H1 2029
Adjacencies flagged as PLAN.md §7 follow-ups (MRZ, ID-card), platform expansion (web/macOS), FFI fast path.

- [adj-mrz-recognition](adj-mrz-recognition.md)
- [adj-id-card-recognition](adj-id-card-recognition.md)
- [infra-dart-ffi-result-structs](infra-dart-ffi-result-structs.md)
- [infra-macos-platform](infra-macos-platform.md)
- [infra-web-platform-wasm](infra-web-platform-wasm.md)

> Year buckets are rough; concrete priority comes from the live TODO sprint header. Whenever an item is pulled into a sprint, link the file from `TODO.md` and update its **Status** line.

## ML track

Cross-cuts the other tracks. Sequencing matters: runtime first, then per-axis models, then lifecycle hardening before retailer release. ~15 MB total bundled budget; OCR language packs are downloadable to keep base size near 5 MB.

- [ml-runtime-and-loader](ml-runtime-and-loader.md) — prerequisite. TFLite + Core ML behind `SupyMlRuntime`. Year 1 (v1.3).
- [ml-capture-classifiers](ml-capture-classifiers.md) — glare / blur / doc-presence / corners. Feeds [core-csu-classifier-plumbing](core-csu-classifier-plumbing.md) and [core-cxd-auto-snap](core-cxd-auto-snap.md). Year 1 (v1.3).
- [ml-doc-type-router](ml-doc-type-router.md) — picks enhance mode + filter automatically. Completes [core-image-filter-pipeline](core-image-filter-pipeline.md). Year 1–2 (v1.3).
- [ml-barcode-roi-proposer](ml-barcode-roi-proposer.md) — learned DM + 1D detector with optional super-resolution. Augments [core-libdmtx-android-roi](core-libdmtx-android-roi.md) / [core-libdmtx-ios-bridge](core-libdmtx-ios-bridge.md). Year 2 (v1.4).
- [ml-on-device-ocr-fallback](ml-on-device-ocr-fallback.md) — PaddleOCR-mobile fallback for low-confidence regions. Pairs with [core-ocr-languages-expansion](core-ocr-languages-expansion.md). Year 2 (v1.4).
- [ml-model-lifecycle](ml-model-lifecycle.md) — versioning, signed downloads, kill-switch, reproducible-builds guarantee. Hardens all of the above for retailer release. Year 2 (v1.4).
