# dx-example-batch-throughput

**Status:** planned · **Target:** v1.3.0 · **Effort:** S · **Trace:** docs/PLAN.md §6 acceptance bench

## Problem
The example app's barcode demo is the single-scan flow. Retailer needs to validate high-throughput batch scanning (10+ unique codes / second). No demo to repro the bench scenario.

## Scope
- Add a `BatchThroughputScreen` to the example app that streams unique reads with a live count + p50/p95 chart.
- Reuse the existing `BatchBarcodeScannerActivity` plumbing.

## Out of scope
- Production telemetry — this is for QA repro only.

## Acceptance
- [ ] Demo runs on the example app for both platforms.
- [ ] Numbers match the perfgate harness within ± 5%.

## Dependencies
- [core-perf-gate-harness](core-perf-gate-harness.md).

## Source
- `docs/PLAN.md` §6 acceptance bench (10-page invoice, QR p50/p95).
