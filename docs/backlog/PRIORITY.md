# supy_scanner — Backlog Priority

Tier order = order of risk to the retailer cutover and dependency chain, not effort. Year buckets in `README.md` are rough horizons; this file is the working priority.

Whenever an item is pulled into a sprint, link it from `TODO.md` and update its **Status** line in its own backlog file. When priorities shift, edit this file rather than reordering `README.md`.

---

## P0 — Ship-blockers for any retailer release
*Without these, we can't responsibly ship anything that touches perf or compat.*

- **[core-perf-gate-harness](core-perf-gate-harness.md)** — every barcode/enhance change after this is otherwise unverified vs. PLAN.md §6's bench (QR p50<300 ms, ≤80 MB). Foundation for every later perf claim.
- **[infra-baseline-perf-publish](infra-baseline-perf-publish.md)** — pairs with perfgate. Without committed baselines, "regression" has no meaning.
_Closed 2026-06-17:_
- `dx-flutter-action-sha-pin` — verified all third-party Actions SHA-pinned and dependabot bumps them weekly.
- `dx-compat-shim-retailer-pin` — wired the compat shim's retailer-pin + API-snapshot tests into CI's `analyze-and-test` job; inventory + tests already existed but didn't execute.

## P1 — Close open v1.1 Sprint 2 commitments
*Already promised in TODO.md. Finish what we started before opening new phases.*

- **[core-zxing-ios-bridge](core-zxing-ios-bridge.md)** (V1-S2-03b) — Android already gets native decode; iOS parity is a half-built bridge.
- **[core-libdmtx-android-roi](core-libdmtx-android-roi.md)** (V1-S2-04a.2) — small/damaged DM on packaging is a known retailer pain; we vendored libdmtx specifically for this.
- **[core-libdmtx-ios-bridge](core-libdmtx-ios-bridge.md)** (V1-S2-04b) — iOS parity for the above.
- **[core-adaptive-binarization](core-adaptive-binarization.md)** (V1-S2-05) — low-light 1D scans (cold rooms, shadowed shelves) — real-world retail scenes.
- **[core-temporal-median-fusion](core-temporal-median-fusion.md)** (V1-S2-06) — hand-jitter is the dominant cause of "scan failed but it looks fine".
- **[infra-tier-debug-override](infra-tier-debug-override.md)** — small, but without it tier-low bugs can't be reproed on the CI device. Unblocks the four items above.

## P2 — Complete v1.2 (CXD + DIE) for non-GMS markets
*Huawei and unbranded ROMs are real retailer markets. Today they fall through.*

- **[core-cxd-availability-gate](core-cxd-availability-gate.md)** — the gate that lets the CameraX fallback exist at all.
- **[core-cxd-camerax-activity](core-cxd-camerax-activity.md)** — the actual fallback. Without it, non-GMS devices have no document path.
- **[core-document-image-enhance-bench](core-document-image-enhance-bench.md)** (DIE6) — the only thing keeping DIE from being declared done.
- **[core-cxd-auto-snap](core-cxd-auto-snap.md)** — non-GMS gets worse UX than GMS until this lands. Acceptable for v1.2.0, not for v1.2.x.

## P3 — Hardening before retailer goes live at scale
*Once retailer rolls out, these decide how fast we learn about problems.*

- **[infra-symbolication-pipeline](infra-symbolication-pipeline.md)** — native crash with no stack = blind debugging. Mandatory before any native ML or C++ change goes wide.
- **[infra-reliability-stress-ci](infra-reliability-stress-ci.md)** — the only way to catch leaks and thermal cliffs before retailer hits them in production.
- **[infra-sbom-cyclonedx](infra-sbom-cyclonedx.md)** — compliance ask retailer will make anyway. Better to land it before they ask.
- **[infra-device-runner-matrix](infra-device-runner-matrix.md)** — emulators don't have thermal behavior; emulator perfgate is a partial signal. Real silicon closes the loop.

## P4 — v1.3 owned UI (Phase CSU)
*Branding parity with Scanbot. Big surface, gated on P0–P3 being solid.*

Dependency order:

1. **[core-csu-options-plumbing](core-csu-options-plumbing.md)** — options first so the channel contract is stable.
2. **[core-csu-ios-avcapture](core-csu-ios-avcapture.md)** + **[core-csu-android-camerax-default](core-csu-android-camerax-default.md)** — capture surfaces.
3. **[core-csu-classifier-plumbing](core-csu-classifier-plumbing.md)** — classifiers only have a home once CSU exists.
4. **[core-csu-result-parity](core-csu-result-parity.md)** — parity gate before flipping the default.
5. **[core-multi-page-review-sheet](core-multi-page-review-sheet.md)** — only if V1-S8-DECISION says "build owned"; additive on the owned surface.
6. **[core-image-filter-pipeline](core-image-filter-pipeline.md)** — last in CSU because it's additive on the owned surface.

## P5 — ML foundation that pays back across CSU + enhance
*High signal-to-cost ML; lands inside the CSU window.*

- **[ml-runtime-and-loader](ml-runtime-and-loader.md)** — prereq for anything ML. Must land before any model.
- **[ml-model-lifecycle](ml-model-lifecycle.md)** — must land **with or before** the first shipped model. No model ships to retailer without kill-switch + versioning.
- **[ml-capture-classifiers](ml-capture-classifiers.md)** — directly improves `core-cxd-auto-snap` quality; replaces hand-tuned thresholds that won't generalize across retailer scenes.
- **[ml-doc-type-router](ml-doc-type-router.md)** — completes `core-image-filter-pipeline` by making it auto. Without this, the filter pipeline shifts work to the consumer.

## P6 — v1.4 lift on the hard tail
*Pure quality improvements; nothing breaks if delayed.*

- **[ml-barcode-roi-proposer](ml-barcode-roi-proposer.md)** — real lift on small/damaged DM on top of the libdmtx ROI gains.
- **[ml-on-device-ocr-fallback](ml-on-device-ocr-fallback.md)** — lifts the low-confidence tail that ML Kit / Vision leave on the table.
- **[core-ocr-languages-expansion](core-ocr-languages-expansion.md)** — market expansion (FR/ES/DE). Drives revenue, not stability.
- **[infra-halide-aot-kernels](infra-halide-aot-kernels.md)** — performance polish; only worth it if perfgate flags adaptive-binarization as a budget risk.
- **[infra-on-demand-subsystems](infra-on-demand-subsystems.md)** — APK/IPA size scales with what retailer actually uses. Becomes the dominant size complaint once the ML track lands; same gating discipline as perfgate, applied to bytes.

## P7 — DX / observability / future-proofing
*Maintainability and reach. Not urgent, but each one removes a recurring tax.*

- **[dx-telemetry-sink-interface](dx-telemetry-sink-interface.md)** — needed once retailer asks "how is the scanner doing in the wild?" Also a hard prereq for `ml-model-lifecycle`.
- **[dx-format-mapping-codegen](dx-format-mapping-codegen.md)** — four-touchpoint drift is a recurring tax. One-shot fix.
- **[dx-example-batch-throughput](dx-example-batch-throughput.md)** — QA repro aid; speeds every perf investigation.
- **[dx-sprint8-migration-cookbook](dx-sprint8-migration-cookbook.md)** — gated on the Sprint 8 decision.
- **[infra-dart-ffi-result-structs](infra-dart-ffi-result-structs.md)** — only worth doing once batch throughput is the bottleneck.

## P8 — Opt-in / opportunistic
*Should only move when there's an explicit retailer ask or strategic call.*

- **[adj-mrz-recognition](adj-mrz-recognition.md)** + **[adj-id-card-recognition](adj-id-card-recognition.md)** — gated on a concrete retailer KYC ask. Not speculative work.
- **[infra-macos-platform](infra-macos-platform.md)** + **[infra-web-platform-wasm](infra-web-platform-wasm.md)** — v2 candidates. Move only when desktop/web becomes a Supy product target.

---

## Cross-cutting rules

- **Never break P0 to ship a higher-P item.** Perfgate + compat shim are the safety net.
- **Lifecycle ships with the first model**, not after. ML release without kill-switch is a one-way door.
- **Anything in P4 onwards waits for P3 hardening** to be solid in production for ≥ 1 retailer release.
