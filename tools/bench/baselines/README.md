# DSQ bench baselines

Pinned `BenchSummary` JSONs the gate compares against
(`dart tools/bench/run_bench.dart --gate <name>`).

- `scanbot.json` — Scanbot's numbers on the corpus (pin once the real corpus
  with `scanbot.png` lanes lands: `run_bench.dart --pin scanbot` after a full
  run; this snapshots the `scanbot_*` metrics as the reference).
- `prev.json` — our own numbers from the last accepted phase. Re-pin at each
  DSQ phase merge (`--pin prev`), with the phase named in the commit message.

Pinning refuses to overwrite an existing file without `--force`. A PR that
moves a baseline must say why in its description — same policy as
`tools/perfgate/PROMOTION_CHECKLIST.md`.
