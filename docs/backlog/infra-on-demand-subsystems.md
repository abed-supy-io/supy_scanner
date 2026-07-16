# infra-on-demand-subsystems

**Status:** planned · **Target:** v1.4.0 · **Effort:** L · **Trace:** binary-size hygiene; pairs with [ml-model-lifecycle](ml-model-lifecycle.md) and [ml-on-device-ocr-fallback](ml-on-device-ocr-fallback.md)

## Problem
Today every consumer pays the size cost of every subsystem: zxing-cpp, libdmtx, ML Kit Text Recognition, GMS Document Scanner, all ML models. A retailer host that only scans QR codes pays for OCR + DM + document enhance it never invokes. As the ML track lands (~15 MB bundled budget) this becomes the dominant size complaint.

The goal: APK/IPA size should scale with the `SupyScanOptions` surface the host actually configures, not with the union of everything `supy_scanner` can do.

## Scope
- **Subsystem registry** — each native subsystem (libdmtx, zxing-cpp Aztec, OCR engine, doc-enhance, each ML model) declares: bundled-or-downloaded, size, trigger condition.
- **Lazy native load** — `dlopen`-style deferred load on Android (split native libs per ABI per feature), weak-linked frameworks on iOS. First-use latency goes to a warm-up call, not the scan path.
- **Symbology pruning** — at build time, the host declares which formats it uses (`SupySymbologySet`); unused zxing-cpp / ML Kit format decoders are gated out of the final binary.
- **Optional downloads** — ML models, OCR language packs, and the doc-enhance Halide kernels (`infra-halide-aot-kernels`) become install-time / `prewarm` downloads instead of bundled bytes. Reuses the signed-download path from `ml-model-lifecycle`.
- **Size budget gate** — CI step measures the example app's APK/IPA size against a baseline; fails PR if a change inflates either by >X%, mirroring how `core-perf-gate-harness` guards latency.
- **Migration story** — defaults bundle everything (no surprise size loss for current retailer); host opts into trimming via `SupyBuildConfig.lean = true` + format whitelist.

## Out of scope
- A plugin-per-feature split (e.g. `supy_scanner_barcode` / `supy_scanner_document` packages) — bigger surface change, separate decision.
- Dynamic feature delivery (Play Feature Delivery / iOS On-Demand Resources) — followup if app stores complain about base size.

## Acceptance
- [ ] Example app built with `lean = true` + QR-only symbology set is ≥ 40% smaller than the default build.
- [ ] First-use of a lazy subsystem adds ≤ 200 ms to the warm-up call on tier-mid; zero added latency to the scan path itself.
- [ ] Size-gate CI step lives next to the perfgate harness and runs on every PR.
- [ ] `docs/MIGRATION.md` documents the trimming opt-in with copy-paste config for retailer.
- [ ] Reproducible-build invariant still holds with lazy load and downloaded packs.

## Dependencies
- [core-perf-gate-harness](core-perf-gate-harness.md) — the gating harness pattern this reuses.
- [ml-runtime-and-loader](ml-runtime-and-loader.md), [ml-model-lifecycle](ml-model-lifecycle.md) — model lazy-load and signed-download path.
- [dx-compat-shim-retailer-pin](dx-compat-shim-retailer-pin.md) — default-on bundling must keep the shim's pinned tests green.

## Source
- This conversation; CLAUDE.md "drop-in for Scanbot" constraint (size is part of the value prop); PLAN.md §6 acceptance bench (working-set budget already exists for memory — this extends the discipline to binary size).
