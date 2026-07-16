# infra-halide-aot-kernels

**Status:** planned · **Target:** v1.3.0 · **Effort:** L · **Trace:** TODO.md V1-S2-05 follow-up

## Problem
Adaptive binarization and unsharp kernels in `supy::scanner::enhance` are hand-rolled separable C++. On tier-low devices the per-frame cost is right at the budget. Halide AOT would give vectorized + tiled variants per arch without hand-tuning.

## Scope
- Add Halide AOT build step under `native/enhance/halide/`.
- Compile schedules for arm64-v8a (NEON) and arm64 (ARMv8.4) Apple silicon.
- Keep the C++ reference path as the fallback.

## Out of scope
- GPU schedules (Metal/Vulkan).
- Adding Halide to the runtime — AOT only.

## Acceptance
- [ ] ≥ 1.5× speedup on the bench fixtures at tier-mid.
- [ ] Native binary size delta within +500 KB per ABI.
- [ ] Reference path still tested in CI.

## Dependencies
- [core-adaptive-binarization](core-adaptive-binarization.md).

## Source
- `TODO.md` — V1-S2-05.
