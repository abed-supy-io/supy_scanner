# core-document-image-enhance-bench

**Status:** landed (Unreleased, 2026-06) · **Target:** v1.2.0 · **Effort:** S · **Trace:** PLAN.md Phase DIE6, TODO.md DIE6

## Problem
`supy::scanner::enhance` (blur gate → morphological closing → gamma + S-curve → unsharp) shipped behind off/fast/balanced/max modes, but the perf bench gate that PLAN.md DIE6 calls for is not in CI. We don't catch when a kernel change blows the tier-mid budget.

## Scope
- Add a fixture-driven bench under `tools/perfgate/enhance/` that times each mode on tier-low / tier-mid / tier-high reference frames.
- Publish a per-mode budget JSON and gate CI on regressions.

## Out of scope
- Adding a new enhance mode.
- GPU/Halide acceleration — see [infra-halide-aot-kernels](infra-halide-aot-kernels.md).

## Acceptance
- [ ] Bench runs in CI for both Android and iOS native test specs.
- [ ] Budget regressions fail the build with a clear diff vs. baseline.
- [ ] `docs/ENHANCEMENT.md` updated with the published per-mode numbers.

## Dependencies
- [core-perf-gate-harness](core-perf-gate-harness.md) for the harness scaffolding.

## Source
- `docs/PLAN.md` — Phase DIE6.
- `TODO.md` — DIE6 perf bench.
