# Baseline promotion — operator checklist

Mechanical sequence for replacing seeded LOW-tier baselines with measured ones. Tracks `V1-S2-07` close-out.

Run this once on the reference LOW device (Moto G Power 5th gen) with an operator. Estimate: ~40 min including fixture handling.

## Prereqs

- Moto G Power 5th gen, Android 13, debug-built example app, USB-debugging on.
- Physical fixtures: 20-SKU torture sheet (laminated), 10-page receipt fixture (matches `example/assets/test/receipt_10p.pdf`), printed QR set (≥10 distinct codes).
- Lux meter; staged 200 lux + 50 lux benches per `TODO.md` V1-S2-07.
- `flutter --version` matches CI's pinned `FLUTTER_VERSION` (currently `3.22.3` in `.github/workflows/ci.yml`).

## Step 1 — capture two bench logs

From the repo root, with the Moto G connected:

```sh
cd example
flutter test integration_test/perf_bench_test.dart --profile -d <device-id> 2>&1 | tee ../bench-run-1.log
# (cool device, repeat)
flutter test integration_test/perf_bench_test.dart --profile -d <device-id> 2>&1 | tee ../bench-run-2.log
```

Sanity-check distribution shape between the two runs (`min`/`max`/`p50` in the `BENCH_RESULT` JSON lines). If any metric's p95 swings >10% between runs, stop — the harness or device is noisy and the resulting baseline would be flaky.

## Step 2 — promote LOW baselines

For each of the four bench metrics (`qr_cold_detect_ms`, `preview_cold_start_ms`, `batch20_ms`, `doc10_ms`):

```sh
dart tools/perfgate/regen-baselines.dart --tier low --log bench-run-2.log \
  --force --justification "replacing seeded PLAN.md §6 ceiling with measured baseline from Moto G Power 5th gen run YYYY-MM-DD"
```

`regen-baselines.dart` writes both `baselines/low/<metric>.json` and a sibling `<metric>.justification.md`. Commit both. Do not touch `baselines/mid/` or `baselines/high/` — see `baselines/SEED_NOTES.md`.

For the enhance metrics (`enhance_*_ms`), capture a separate log via:

```sh
dart tools/perfgate/enhance/run_enhance_bench.dart --tier low --log enhance-low.log
dart tools/perfgate/regen-baselines.dart --tier low --log enhance-low.log \
  --force --justification "<same wording, enhance subsystem>"
```

## Step 3 — flip the CI gate

In `.github/workflows/ci.yml`:

- Drop `continue-on-error: true` from `perfgate-emulator` (line 280).
- Drop `continue-on-error: true` from `enhance-bench-low` (line 357).
- Strike the "Non-blocking on first PR" lines from the comment blocks at `ci.yml:271–274` and `ci.yml:350–351`.

**Do not flip until Step 2 has landed.** Otherwise the next push fails CI against still-seeded ceilings.

## Step 4 — record QA numbers

The same operator session captures the 20-SKU lux numbers V1-S2-07 promised. Repeat Step 1 at **200 lux** and **50 lux** against the 20-SKU sheet (the harness's `batch20_ms` covers this; just stage lighting). Fill in `docs/QA.md:222–225` Performance targets table — replace `_pending device run_` with measured p50/p95 + run date + device.

## Step 5 — close out backlog

- `docs/backlog/core-perf-gate-harness.md`: flip `Status: open` → `Status: done`; check the three acceptance boxes; add a "Closed YYYY-MM-DD via PR #…" trailer.
- `docs/backlog/infra-baseline-perf-publish.md`: same close-out for the LOW portion; keep open if it carries MID/HIGH scope.
- `docs/backlog/PRIORITY.md`: remove `core-perf-gate-harness` from the P0 section.
- `TODO.md` V1-S2-07: append the final "20-SKU lux numbers recorded" line.

## Negative test before merging

Before opening the PR with the gate flip, on a scratch branch bump one `baselines/low/*.json` `p95` down by 30% and re-run the bench. With `continue-on-error` removed, `perfgate-emulator` must fail. Revert before pushing the real PR.
