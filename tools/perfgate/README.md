# perfgate

CI perf-regression gate for `supy_scanner`. Wraps the existing
`example/integration_test/perf_bench_test.dart` harness, parses its
`BENCH_RESULT` / `BENCH_TIER` JSON lines, compares against checked-in
baselines under `baselines/<tier>/`, and exits non-zero if any metric's
**p95** has regressed by more than **15%**.

Backing ticket: `V1-S2-07` (see `docs/backlog/PRIORITY.md`).

## Running locally

```sh
# 1. Run the integration bench yourself and let perfgate parse the output:
dart tools/perfgate/run.dart

# 2. Or feed a pre-captured log:
dart tools/perfgate/run.dart --log path/to/bench.log

# 3. Or pipe via stdin:
flutter test example/integration_test/perf_bench_test.dart --machine \
  | dart tools/perfgate/run.dart --stdin
```

The runner writes `tools/perfgate/report.json` with:

```jsonc
{
  "tier": "low",
  "observed": [ /* BenchSample[] */ ],
  "results": [ /* CompareResult[] */ ],
  "regressed": false
}
```

Exit codes: `0` clean, `1` regression detected, `2` no samples parsed (bench
likely crashed or never reached the bench widgets).

## Baselines

Per-tier baseline JSON lives at `baselines/<tier>/<metric>.json` where:

- `<tier>` ∈ `low`, `mid`, `high` — matches `SupyDeviceTier` reported by the
  native side via the `getDeviceTier` MethodChannel call.
- `<metric>` is the `metric` field of the `BENCH_RESULT` line
  (e.g. `qr_cold_detect_ms`, `preview_cold_start_ms`).

Each file is a single `BenchSample` JSON literal:

```json
{
  "metric": "qr_cold_detect_ms",
  "runs": 50,
  "min": 80,
  "max": 850,
  "p50": 250,
  "p95": 600
}
```

`p95` is the only field the gate compares. The rest is preserved so reviewers
can sanity-check distribution shape.

### When to regenerate

A PR that *intentionally* moves a baseline must:

1. Run `dart tools/perfgate/regen-baselines.dart --tier=<tier> --force --justification "<reason>"` on the relevant tier's reference device.
2. Commit both the regenerated `<metric>.json` **and** the auto-written
   `<metric>.justification.md` next to it.
3. Link the justification in the PR description.

Drive-by baseline edits without a justification will not be approved.

### Reference devices

- `low` — Moto G Power (5th gen) / Pixel 4a class. Emulator approximation
  acceptable for CI.
- `mid` — iPhone SE (3rd gen) / Pixel 7a class.
- `high` — iPhone 15 Pro / Pixel 8 Pro class.

See `docs/PLAN.md §6` for the canonical target table.

## CI wiring

The `perfgate-emulator` job in `.github/workflows/ci.yml` runs on
`ubuntu-latest` against the `low` tier baseline. iOS device-class perf
runs are deferred to `infra-device-runner-matrix` (P3 backlog item).

## Source map

| File | Purpose |
|---|---|
| `lib/baseline_compare.dart` | Pure-Dart comparator. No Flutter imports — unit-testable on the host. |
| `run.dart` | CLI entry point. Spawns flutter, parses the stream, writes the report. |
| `regen-baselines.dart` | Records new baselines. Refuses to overwrite without `--force --justification`. |
| `test/baseline_compare_test.dart` | Unit tests for the comparator. |
| `baselines/<tier>/<metric>.json` | Checked-in baselines. |
| `baselines/<tier>/<metric>.justification.md` | Why a baseline moved. |
