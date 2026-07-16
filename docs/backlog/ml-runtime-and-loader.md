# ml-runtime-and-loader

**Status:** planned · **Target:** v1.3.0 · **Effort:** M · **Trace:** prerequisite for all `ml-*` entries

## Problem
Every later ML feature needs the same plumbing: a runtime, a model loader, prewarm + governor + tier integration, and a per-model latency lane in the perfgate harness. Building it once avoids each ml-* ticket re-inventing it.

## Scope
- Recommend **TFLite + NNAPI on Android, Core ML on iOS** behind a thin `SupyMlRuntime` abstraction (cross-platform inference contract; per-platform delegate routing to NPU / Neural Engine).
- Model loader resolves `assets/models/<name>.v<n>.{tflite|mlmodelc}`; lazy by default, eager when `prewarm` requests it.
- Integrate with `SupyThermalGovernor` — when throttled, ML passes are skipped and decisions fall back to existing heuristics.
- Integrate with `SupyDeviceTier` and `debugForceTier` so a tier-low CI device can repro tier-mid model decisions.
- Extend perfgate (`tools/perfgate/`) with a per-model latency lane so model swaps are gated on cost, not just decoded outcome.

## Out of scope
- ONNX Runtime Mobile — slower cold-start vs. TFLite/Core ML for the model sizes we care about. Re-evaluate only if a model needs an op TFLite/Core ML can't run.
- GPU delegates as a default — opt-in per model.

## Acceptance
- [ ] `SupyMlRuntime` API typed and documented; no `dynamic` leaks per CLAUDE.md.
- [ ] Loader cold-load + warm-load latencies recorded in perfgate baselines.
- [ ] Governor skip path covered by an integration test (force throttle → ML pass bypassed).
- [ ] Adding a model = drop a file under `assets/models/` + register a `SupyModelDescriptor`; no native build change required.

## Dependencies
- [core-perf-gate-harness](core-perf-gate-harness.md), [infra-tier-debug-override](infra-tier-debug-override.md).

## Source
- This conversation's ML roadmap; CLAUDE.md "no cloud" + "no paid SDK" constraints (TFLite + Core ML are both first-party and free).
