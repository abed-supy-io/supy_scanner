# infra-reliability-stress-ci

**Status:** planned · **Target:** v1.3.0 · **Effort:** M · **Trace:** PLAN.md §7 Post-v1.2 candidate

## Problem
PLAN.md §7 lists "reliability stress harness in CI" as an explicit post-v1.2 candidate. H3 sprints landed perf-regression but not the long-running stress harness that would catch leaks and thermal-cliff bugs before retailer hits them.

## Scope
- Long-form integration test that loops capture + decode for N minutes on the example app, then asserts working-set ceiling and FPS floor.
- Run on a nightly CI lane (matrix entry, not blocking PRs).
- Publish a trend artifact so regressions are visible.

## Out of scope
- 24h soak — that's a separate manual H3 task.

## Acceptance
- [ ] 30-min loop runs nightly on Android + iOS.
- [ ] Working-set ceiling assertion fires when broken.
- [ ] Trend page (JSON + simple chart) committed under `tools/perfgate/`.

## Dependencies
- [core-perf-gate-harness](core-perf-gate-harness.md), [infra-baseline-perf-publish](infra-baseline-perf-publish.md).

## Source
- `docs/PLAN.md` §7 Post-v1.2 candidates.
