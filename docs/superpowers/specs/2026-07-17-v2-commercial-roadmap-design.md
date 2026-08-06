# supy_scanner v2.0 Commercial Roadmap — Design

**Date:** 2026-07-17
**Status:** Approved section-by-section in brainstorming; pending final spec review
**Horizon:** ~6 months (26 weeks), small team (owner + 1–2 engineers; devices and mobile lead arrive during the roadmap)
**Related specs:** [2026-07-16-doc-scan-quality-design.md](2026-07-16-doc-scan-quality-design.md) (DSQ — adopted as-is as Track B's backbone)

---

## 1. Goal and success criteria

Ship **supy_scanner v2.0** in ~6 months as a commercially licensable, fully on-device Flutter scanning SDK — a drop-in Scanbot replacement sold to third parties, distributed via private pub / source license.

v2.0 is done when all five hold:

1. **Proven quality.** The DSQ0 scoreboard beats Scanbot on its headline metrics (quad IoU, detection rate, OCR CER proxy, sharpness). Perfgate is green on real devices across all three device tiers. 24-hour soaks pass on both reference devices (Moto G Power, iPhone SE 2).
2. **Zero open ship-blockers.** Backlog priorities P0–P3 are empty: v1.1 Sprint-2 commitments landed, CXD6 non-GMS sign-off done, crash symbolication live, stress CI and SBOM in place.
3. **Smart features shipped behind the ML foundation.** `SupyMlRuntime` + model lifecycle (versioned descriptors, kill-switch, reproducible-build checksums) land **before** any model ships. On top of it: DSQ2 ML document detection, invoice extraction (post promotion-gate), and MRZ recognition.
4. **Sellable package.** License decision applied, versioned docs site live, public benchmark report published, demo app polished, tiered feature gating implemented (Core / Smart Capture / Data & Identity), and private pub distribution proven end-to-end with one non-Supy consumer.
5. **Compat inviolate.** The Scanbot-compat API surface and channel `io.supy.scanner/v1` are unbroken. The retailer app upgrades v1.x → v2.0 with zero call-site changes.

## 2. Roadmap structure — two parallel tracks + a thin thread

Chosen approach (B of three considered): **Track A (ship-quality)** and **Track B (smart)** run in parallel with explicit dependencies between them; **Track C (commercial packaging)** is a thin continuous thread that thickens in the final six weeks. Alternatives rejected: strictly serial (wastes the weeks Track A spends waiting on devices) and smart-first (ships intelligence on an unproven floor).

Team shape: Track A is mostly the incoming mobile lead + owner review; Track B is owner-led; Track C is decision work early, artifact work late.

## 3. Track A — Ship-quality (weeks 1–12, serialized)

Follows the existing `docs/backlog/PRIORITY.md` ladder. Serial by design — only the calendar-bound device block overlaps. Timeline was deliberately de-risked from an earlier 8-week draft.

- **A1 (weeks 1–3): land what's in flight.** Merge the `raise-flutter-floor` branch (~91 staged files). S3-10 memory profile. H4-07 QA walk. Tag **v1.0.1** via `tools/release.sh`.
- **A2 (weeks 3–7): v1.1 S2 barcode commitments, one at a time.** zxing iOS bridge (V1-S2-03b), libdmtx iOS bridge, libdmtx Android ROI deltas — each followed by a perfgate run before the next starts. The implementation plan verifies item-by-item what is truly left vs. already done. **Halide AOT (V1-S2-05.2–05.5) is deferred to a perf-triggered stretch**: it re-enters only if device perfgate shows the tier-low binarization budget failing.
- **A3 (weeks 5–10, calendar-driven, overlaps A2):** the device block, gated on hardware arrival. H1-11 reliability re-run → H3-02/03 24h soaks → H3-05 / V1-PERF-P5 4-device re-bench with baselines promoted via `regen-baselines.dart` → tag **v1.1.0**. Then CXD6 non-GMS sign-off → tag **v1.2.0**.
- **A4 (weeks 8–12): P3 infrastructure.** Symbolication **first** (it gates Track B model shipping), then stress CI, CycloneDX SBOM, device-runner matrix.

**Exit gate:** three tags shipped (v1.0.1, v1.1.0, v1.2.0), P0–P3 empty, symbolication live.

## 4. Track B — Smart (weeks 5–24, one phase in flight at a time)

Backbone is the approved DSQ spec; ML foundation inserted at the right seam; extraction and identity stacked after.

- **B0 (weeks 5–8): DSQ0 scoreboard.** Bench harness, ~120-scene labeled corpus (Git LFS), Scanbot baseline captured by the owner (~half a day with the retailer app). Host tooling — no devices needed. Doubles as the marketing benchmark's data source. Gate for every later phase: beat the phase metric, regress nothing >±2%.
- **B1 (weeks 7–10): DSQ1 cheap wins, no ML.** Max-res capture path, iOS embedded-enhance default `off`→`balanced`, unified `supy_core_warp`, ≥300 DPI output policy.
- **B2 (weeks 9–13): ML foundation.** `SupyMlRuntime` (TFLite+NNAPI / Core ML behind one contract) + model lifecycle (`name@version` descriptors, `SupyMlConfig.disableAll` kill-switch, reproducible-build checksums). **Design decision:** this *is* DSQ2's native plumbing, extracted as the shared abstraction with HED as its first client — built once, not twice. Kill-switch is mandatory before the first model ships. Gated on Track A symbolication (A4).
- **B3 (weeks 12–17): DSQ2 ML document detection.** HED-int8 ≤3 MB, "ML proposes, geometry disposes" fusion, `detectorMode: auto|classical|ml`, C ABIs `supy_core_ml_pre`/`supy_core_ml_quads`.
- **B4 (weeks 16–19): DSQ3 shadow removal + output modes.** Gain-map + guided filter (stage bit `0x80`), grayscale/B&W via `supy_core_binarize_luma`, B&W→PNG.
- **B5 (weeks 17–21): invoice extraction promotion.** Close IXP1–6; promotion gate: ≥20 labeled invoices at >80% header / >70% line-item accuracy; then public API **with Android parity** (ML Kit text feeding the shared heuristic extractors, C++ where practical).
- **B6 (weeks 20–24): MRZ recognition.** OCR-B + ICAO 9303 parser, sealed `SupyMrzResult` (TD1/TD2/TD3), ≥95% on the ICAO sample set. MRZ leads the identity work because it is standards-based (no training-data pipeline needed), Scanbot charges for it separately, and it demos well.

**Explicit v2.1 deferrals** (pre-agreed pressure valve): ID-card templates, capture classifiers (DSQ2's corner regression covers the highest-value piece), barcode ROI proposer (no training-data pipeline yet), DSQ4 multi-frame capture (conditional by design in the DSQ spec).

## 5. Track C — Commercial packaging (thin weeks 2–18, thickens 18–26)

Decisions early, artifacts late.

**Early decisions (weeks 2–6; days of work):**
- **License + distribution model:** source-available commercial license vs. binary-only; delivery channel (private pub server — self-hosted unpub or Cloudsmith). Redistribution audit of the vendored stack (zxing-cpp Apache-2.0, libdmtx BSD, HED weights BSD-3, FSRCNN MIT — `docs/DEPENDENCIES.md` says the graph is copyleft-free; this confirms it).
- **Tier map:** **Core** (barcode + document scanning) / **Smart Capture** (DSQ intelligence: ML detection, shadow removal, output modes) / **Data & Identity** (invoice extraction, MRZ). Enforced by an **offline signed license key** — a network license check in the scan path would violate the repo's no-network rule, and offline operation is itself a selling point.
- Naming/trademark check and a pricing hypothesis anchored under Scanbot's pricing (owner-owned; the roadmap only reserves the slot).

**Continuous thread (near-zero marginal cost, CI-enforced):** dartdoc coverage on public API, CHANGELOG discipline, demo app kept sale-presentable as features land, every DSQ bench run archives its `bench_report.md` as whitepaper raw material.

**Thickening (weeks 18–26):**
- Versioned docs site: getting-started, migration-from-Scanbot guide (reusing `docs/MIGRATION.md`), API reference, per-tier feature matrix.
- **Benchmark whitepaper** generated from the DSQ0 harness: "supy_scanner vs. Scanbot, measured" — the single most persuasive sales artifact.
- License-key issuance tooling + gating implementation (flag-checked at feature entry points; additive; no channel change).
- **Design-partner pilot:** one friendly external company on v2.0.0-rc before GA — the first non-Supy consumer exercising private pub, docs, and the support path end-to-end.
- v2.0 GA with a support/SLA statement (response times, LTS policy for the v1.x line the retailer sits on).

## 6. Release train

| Week | Tag | Contents |
|---|---|---|
| ~3 | v1.0.1 | Flutter floor raise merged, memory profile, H4 QA walk closed |
| ~10 | v1.1.0 | S2 barcode wins (zxing iOS, libdmtx ROI), device re-bench, baselines promoted |
| ~12 | v1.2.0 | CXD non-GMS sign-off; Track A exit (P0–P3 empty, symbolication live) |
| ~14 | v1.3.0 | DSQ0 scoreboard + DSQ1 cheap wins + ML runtime/lifecycle (no models shipped yet) |
| ~19 | v1.4.0 | DSQ2 ML detection (`detectorMode: auto`) + DSQ3 shadow removal / output modes |
| ~24 | v2.0.0-rc | Invoice extraction public API, MRZ, tier gating, docs site; design partner starts |
| ~26 | v2.0.0 GA | Benchmark whitepaper published, pilot feedback folded in |

Every tag keeps the compat suite green, so the retailer app can hop forward from whichever tag it last QA'd — the drop-in guarantee proving itself continuously.

## 7. Risks (ordered) and mitigations

1. **Small-team fan-out** (two tracks + packaging, 2–3 people). Structural mitigation: Track B strictly one phase in flight; the v2.1 deferral list is the pre-agreed pressure valve; a weekly 15-minute cut-line review decides slips by policy, not in a panic.
2. **The bench says Scanbot wins.** The whitepaper can't claim "beats Scanbot." Mitigation: DSQ phases carry escape hatches (in the DSQ spec); the commercial story degrades gracefully to "matches Scanbot at zero license cost, fully on-device, source-available."
3. **Devices / mobile lead slip.** A3 is calendar-bound; tags v1.1.0/v1.2.0 slip but feature work merges dark behind flags. v2.0 GA absorbs ~3 weeks of device slip before the date moves.
4. **Invoice promotion gate fails** (<80% header / <70% line-item). Ships in v2.0 as "beta, lab flag" instead of a tiered feature; MRZ carries the Data & Identity tier alone. Pre-agreed here.
5. **Compat regression** — the one unrecoverable sin. Compat snapshot + retailer call-site tests run on every PR; any intentional surface change requires a logged decision in `TODO.md`.

## 8. Quality gates (all pre-existing infrastructure; the roadmap enforces them)

- Perfgate on every PR; device lanes per tag.
- DSQ bench per DSQ phase: beat the phase metric, no >±2% regression elsewhere.
- Compat snapshot suite on every PR.
- Binary-size ceilings per tag: ≤22 MB per ABI (Android), ≤25 MB (iOS).
- 24h soaks before v1.1.0 and v2.0.0-rc.
- Every ML model: behind the kill-switch, versioned descriptor, reproducible-build checksum — no exceptions.

## 9. Supy Fit Assessment

This repo is a Flutter library with C++/Swift/Kotlin natives — most Supy backend standards don't apply; flagged honestly rather than force-fit:

- **nx-nestjs patterns / architecture.md:** N/A (no Nx, no NestJS). The repo's own layering discipline (Dart API → channel → native, sealed types, no `dynamic` past `lib/src/channel/`) is the equivalent standard and this roadmap preserves it.
- **NATS event patterns:** N/A — no message bus. The nearest analogue, the versioned MethodChannel `io.supy.scanner/v1`, follows the same contract-stability principle: v2.0 ships on v1 of the channel; a v2 channel would be a parallel surface, not a break.
- **Cerbos / security model:** N/A for request authorization. The security-relevant commitments here: offline signed license keys (no secrets in the repo, no network in the scan path), signed optional model packs, and SBOM (CycloneDX, A4) for supply-chain transparency — appropriate for a distributed SDK.
- **Commit conventions:** applies fully. Conventional commits are already house style; each roadmap phase decomposes into `feat(...)`/`fix(...)`/`docs:`-scoped PRs, and tags follow the existing `tools/release.sh` flow.
- **Supy scope rule:** the commercial-SDK goal is a Supy business decision confirmed by the owner in this brainstorm, not a personal tangent; the retailer app remains the first-class consumer via the compat guarantee.

## 10. Next step

Hand this spec to `superpowers:writing-plans` to produce the implementation plan, starting with Track A1 (merge `raise-flutter-floor`, v1.0.1) and the Track C early decisions, since both start at week 1–2.
