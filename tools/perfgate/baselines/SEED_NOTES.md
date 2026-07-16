# Seeded baselines — read this before adjusting

These `<tier>/<metric>.json` files were **seeded from the perf target ceilings**
in `docs/PLAN.md §6` and the V1-S2-07 ticket, not measured on a reference
device. Tracks `infra-baseline-perf-publish` (H3-04).

| Metric | Target ceiling (PLAN.md §6) | Reference device class |
|---|---|---|
| `qr_cold_detect_ms` (p95) | 800 ms | Moto G Power (low) |
| `preview_cold_start_ms` (p95) | 400 ms | Pixel 8 (high) |
| `batch20_ms` (p95) | 30 000 ms | Any mid+ |
| `doc10_ms` (p95) | 12 000 ms | iPhone SE 3 (mid) |

Tier multipliers used for the seed values, applied to the low-tier ceiling:

- `low` = 1.0× (Moto G Power class)
- `mid` = 0.7× (iPhone SE 3 / Pixel 7a class)
- `high` = 0.5× (Pixel 8 / iPhone 15 Pro class)

**These values must be replaced with real measured values** the first time
the perfgate-emulator job has run cleanly twice in CI — or, equivalently,
on the LOW reference device (Moto G Power 5th gen) when no CI remote
is configured. After that, follow the regen flow in `../README.md`. Use
`--justification "replacing seeded ceiling with measured baseline"` for
that transition.

Operator-facing close-out checklist: `../PROMOTION_CHECKLIST.md`. That
file owns the full sequence (capture → regen → CI gate flip → QA table →
backlog close-out).

Until then: the `+15%` regression tolerance is computed against an
artificial ceiling — a "regression" really means "you've blown past the
target ceiling by 15%", which is the right semantics for a v1 ship gate.
