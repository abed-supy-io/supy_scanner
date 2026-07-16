# core-perf-gate-harness

**Status:** open (harness landed 2026-06-16; awaiting first measured baseline run) · **Target:** v1.1.0 · **Effort:** M · **Trace:** TODO.md V1-S2-07

## Current state (2026-06-17)

Harness shipped — `tools/perfgate/{run.dart,regen-baselines.dart,lib/baseline_compare.dart}`, the `getDeviceTier` channel method, and CI jobs `perfgate-unit`, `perfgate-emulator`, `enhance-bench-low` all exist. Close-out is blocked on three sequential gates:

1. **First measured LOW-tier run.** Every `tools/perfgate/baselines/low/*.json` is still seeded from `docs/PLAN.md §6` ceilings, not measured. Reference device is Moto G Power 5th gen — requires an operator session with the 20-SKU torture sheet, 10-page receipt fixture, and 50 QR presentations. See `tools/perfgate/PROMOTION_CHECKLIST.md`.
2. **CI gate flip.** `.github/workflows/ci.yml` has `continue-on-error: true` on both `perfgate-emulator` (line 280) and `enhance-bench-low` (line 357). Must remain non-blocking until step 1 lands — otherwise CI fails against artificial ceilings.
3. **20-SKU lux numbers in QA.md.** `docs/QA.md:222–225` Performance targets table still reads `_pending device run_`. Same operator session as step 1 produces these.

MID/HIGH baselines stay seeded indefinitely; gated on `infra-device-runner-matrix` (P3).

## Problem
PLAN.md §6 sets the acceptance bench at QR p50<300 ms / p95<800 ms and ≤ 80 MB working set, but no automated harness fails CI when a change blows the budget. Every barcode-pipeline change since V1-S2-03 has had to be re-benched by hand.

## Scope
- Add `tools/perfgate/` runner that replays a fixture stream against the Dart channel.
- Emit a JSON report with p50/p95 per format + working-set delta.
- CI step compares against checked-in baselines per device tier; non-zero exit on regression beyond tolerance.

## Out of scope
- On-device fleet benchmarking — see [infra-device-runner-matrix](infra-device-runner-matrix.md).
- Memory leak hunting (Instruments / LeakCanary stay separate).

## Acceptance
- [ ] `flutter test integration_test/perfgate` runs on the example app and produces the JSON.
- [ ] CI job fails when p95 regresses > 15% vs. baseline.
- [ ] Baselines committed under `tools/perfgate/baselines/`.

## Dependencies
- Existing example integration tests; existing CI matrix in `.github/workflows/ci.yml`.

## Source
- `TODO.md` — V1-S2-07 "Perf-gate harness".
- `docs/PLAN.md` §6 acceptance bench.
