# Phase 1 — Track A1 (v1.0.1) + Track C Early Decisions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the `raise-flutter-floor` branch, close the v1.0.1 release train (S3-10 memory profile, H4-07 QA sign-off, H4-08 tag), and produce the three Track C commercial decision documents (licensing audit, distribution model, tier map).

**Architecture:** No new code — this phase is release engineering plus decision records. Engineering work flows through the existing gates (`flutter analyze --fatal-infos`, `flutter test`, compat snapshot suite, CI on GitHub Actions, `tools/release.sh`). Commercial decisions become committed markdown under a new `docs/commercial/` directory so later phases (tier gating in weeks 18–26) consume them as specs.

**Tech Stack:** Flutter 3.29 / Dart 3.7 (post-floor-raise), GitHub CLI (`gh`), `tools/release.sh`, Android Studio profiler / Xcode Instruments for the memory pass.

**Spec:** `docs/superpowers/specs/2026-07-17-v2-commercial-roadmap-design.md` (§3 Track A1, §5 Track C early decisions). Later roadmap phases (A2, A3, A4, B0+) get their own plans when they start — do not pull their work into this one.

## Global Constraints

- Scanbot-compat API surface and channel `io.supy.scanner/v1` must not change. Any surface change requires a logged decision in `TODO.md` — none is expected in this phase.
- No paid SDK dependencies. No cloud OCR or network calls in the scanning path (this rules out any online license check in the tier design).
- Conventional commit messages: `feat(...)`, `fix(...)`, `docs:`, `chore:`, `ci:`.
- Version sources bump only via `tools/release.sh` (pubspec.yaml + ios/supy_scanner.podspec + android/build.gradle in lock-step). Release script gates: branch `main`, clean tree, `CHANGELOG.md` has a `## [1.0.1]` heading (already present via H4-06), analyze + test pass.
- Never commit secrets, license keys, or tokens.
- Tasks 5 and 6 need physical devices (one Android, one iPhone) and Task 6 needs the mobile lead. If hardware isn't available when you reach them, complete Tasks 2–4 and stop with a clear "blocked on devices" report — do not fake numbers or sign-offs.

## File Structure

- Create: `docs/commercial/LICENSING-AUDIT.md` — redistribution audit of everything that ships in the artifact (Task 2).
- Create: `docs/commercial/DISTRIBUTION.md` — license + distribution channel decision record, plus owner-action slots for naming/pricing (Task 3).
- Create: `docs/commercial/TIERS.md` — feature→tier map and offline license-key enforcement decision (Task 4).
- Modify: `docs/QA.md` — memory-profile numbers under `## Performance targets` (~line 290) and the filled `## Sign-off (v1.0.1)` block (~line 330).
- Modify: `TODO.md` — tick S3-10 (line 40), S4-08 (line 51), H4-07 (line 182), H4-08 (line 183).
- Modify (via `tools/release.sh`, not by hand): `pubspec.yaml`, `ios/supy_scanner.podspec`, `android/build.gradle`.

---

### Task 1: Merge `raise-flutter-floor` into `main`

**Files:**
- No file edits. Branch `raise-flutter-floor` (4 commits ahead of `main`: CI Flutter pin, SDK floor raise, formatter sweep, roadmap spec) merges via PR.

**Interfaces:**
- Consumes: existing CI workflow `.github/workflows/ci.yml` (already updated on the branch).
- Produces: `main` at Flutter 3.29 / Dart 3.7 — the base every later task commits to.

- [ ] **Step 1: Run the local gates on the branch**

```bash
cd /Users/abdalqaderalnajjar/Projects/supy-projects/supy-scanner
git checkout raise-flutter-floor
flutter pub get
dart format --set-exit-if-changed lib test example/lib
dart analyze --fatal-infos
flutter test
```

Expected: format makes no changes (exit 0), analyze reports `No issues found!`, all tests pass.

- [ ] **Step 2: Run the compat snapshot suite**

```bash
cd compat/supy_scanner_scanbot_compat
flutter pub get
flutter test
cd ../..
```

Expected: all tests pass, including `api_signature_snapshot_test.dart` and `retailer_call_sites_test.dart`. If the snapshot test fails, STOP — that's a compat-surface change and needs a logged decision, not a snapshot regen.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin raise-flutter-floor
gh pr create --base main --title "chore(deps): raise SDK floor to Dart 3.7 / Flutter 3.29" --body "$(cat <<'EOF'
Raises the SDK/Flutter floor, pins CI to Flutter 3.44.2, reformats for the Dart 3.7 tall formatter, and adds the v2.0 commercial roadmap design spec.

No public API changes — compat snapshot suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed.

- [ ] **Step 4: Wait for CI, then merge**

```bash
gh pr checks --watch
gh pr merge --merge
git checkout main && git pull
git log --oneline -2
```

Expected: all checks pass; merge commit on `main` (this repo uses merge commits — see PR #14); `git log` shows the merge at HEAD. If any CI job fails, fix it on the branch (one commit per fix, conventional message) and re-watch — do not merge red.

---

### Task 2: Track C — licensing & redistribution audit

**Files:**
- Create: `docs/commercial/LICENSING-AUDIT.md`

**Interfaces:**
- Consumes: `docs/DEPENDENCIES.md` (H3-07 audit — the per-dep license table this task verifies and extends).
- Produces: the "redistribution is clean" conclusion Tasks 3–4 and the week-18+ packaging work rely on. Referenced by path from `DISTRIBUTION.md`.

- [ ] **Step 1: Verify the license claims against the actual dependency sources**

For each row in `docs/DEPENDENCIES.md`, confirm the license is what the table says. The graph is small; check it, don't trust it:

```bash
# Dart runtime dep (exactly one non-SDK dep by design):
dart pub deps --style=list | head -20
# Android side:
grep -n "implementation\|api " android/build.gradle
# Vendored C/C++ (v1.1, behind default-OFF flags):
ls native/third_party/ 2>/dev/null || grep -n "zxing-cpp\|libdmtx" docs/DEPENDENCIES.md
```

Expected: `meta` (BSD-3-Clause) as the only non-SDK Dart runtime dep; Android deps as listed in DEPENDENCIES.md §2; zxing-cpp v2.2.1 (Apache-2.0) and libdmtx v0.7.7 (BSD-2-Clause) as the two flag-gated vendored libs. For the vendored libs, open their pinned upstream tags on GitHub and confirm the LICENSE file matches. Note any mismatch in the audit doc — a mismatch is a finding, not a blocker to writing the doc.

- [ ] **Step 2: Write `docs/commercial/LICENSING-AUDIT.md`**

```markdown
# Commercial redistribution audit — supy_scanner

**Date:** <today's date>
**Audited against:** docs/DEPENDENCIES.md (H3-07, last audited 2026-06-14) + upstream LICENSE files at the pinned tags.
**Question answered:** can Supy redistribute supy_scanner under a commercial license (source-available or binary) without copyleft contamination or attribution problems?

## Verdict

**Yes.** Every dependency that ships in a published artifact is BSD/MIT/Apache-family. No GPL/LGPL/AGPL anywhere in the runtime graph. Obligations are attribution-only.

## Shipped-artifact dependency licenses (verified <date>)

| Dependency | Version | License | Verified how | Redistribution obligation |
|---|---|---|---|---|
| Flutter SDK / flutter | 3.29 line | BSD-3-Clause | flutter.dev LICENSE | Attribution in NOTICE |
| meta | ^1.15.0 | BSD-3-Clause | pub.dev license tab | Attribution in NOTICE |
| <each Android dep from DEPENDENCIES.md §2> | <pinned> | <license> | <upstream LICENSE at pin> | Attribution in NOTICE |
| zxing-cpp (flag-gated, default OFF) | v2.2.1 | Apache-2.0 | github.com/zxing-cpp/zxing-cpp LICENSE at v2.2.1 | Attribution + Apache NOTICE passthrough |
| libdmtx (flag-gated, default OFF) | v0.7.7 | BSD-2-Clause | github.com/dmtx/libdmtx LICENSE at v0.7.7 | Attribution in NOTICE |

(Fill every row with the verified value — no row may say "as documented"; each needs its own verification note.)

## Planned dependencies (not yet shipped — pre-cleared here)

| Dependency | Roadmap phase | License | Cleared? |
|---|---|---|---|
| HED edge-detection weights | B3 (DSQ2) | BSD-3-Clause (original HED release) | Yes — attribution only |
| FSRCNN weights | v2.1+ (DSQ4, deferred) | MIT | Yes — attribution only |

## Obligations checklist for the packaged SDK

- [ ] Ship a `NOTICE` file aggregating all attributions (create at packaging time, weeks 18–26).
- [ ] Apache-2.0 (zxing-cpp): include the Apache license text and any upstream NOTICE when the flag ships ON.
- [ ] Keep this audit in sync with docs/DEPENDENCIES.md — re-run when any dep is added (CI SBOM lands in Track A4).

## Findings

<List any mismatches found in Step 1, or "None — DEPENDENCIES.md claims verified exactly.">
```

Replace every `<...>` with verified values while writing — the committed file must contain zero angle-bracket placeholders.

- [ ] **Step 3: Verify the committed doc has no placeholders**

```bash
grep -n "<.*>\|TBD\|TODO" docs/commercial/LICENSING-AUDIT.md
```

Expected: no output (the obligations checklist's `- [ ]` boxes are fine; angle brackets and TBDs are not).

- [ ] **Step 4: Commit**

```bash
git add docs/commercial/LICENSING-AUDIT.md
git commit -m "docs(commercial): add redistribution licensing audit"
```

---

### Task 3: Track C — distribution & license model decision record

**Files:**
- Create: `docs/commercial/DISTRIBUTION.md`

**Interfaces:**
- Consumes: `docs/commercial/LICENSING-AUDIT.md` verdict (Task 2).
- Produces: the recorded distribution decision the week-18+ packaging work implements. Owner-action slots for naming/pricing live here.

- [ ] **Step 1: Write the decision document with the recommendation**

```markdown
# Distribution & license model — decision record

**Date:** <today's date>
**Status:** DECIDED — <filled in Step 2>
**Prerequisite:** docs/commercial/LICENSING-AUDIT.md — redistribution is clean.

## Decision 1: license model

| Option | What the customer gets | Pros | Cons |
|---|---|---|---|
| **A. Source-available commercial license (recommended)** | Full Dart+native source under a paid license forbidding redistribution | Debuggable by customers (big vs. Scanbot's binary), no binary-hosting infra, symbolication trivial | Source leakage risk (mitigated by license terms + watermarked releases) |
| B. Binary-only | Compiled AAR/XCFramework + Dart facade | Stronger IP protection | Doubles release engineering (per-arch binaries), hurts the "you can read it" sales angle, complicates customer crash triage |

Recommendation: **A.** The buyer persona (teams fleeing Scanbot's license cost) values inspectability; our moat is the bench numbers and maintenance, not source secrecy.

## Decision 2: distribution channel

| Option | Pros | Cons |
|---|---|---|
| **A. Self-hosted unpub (recommended)** | Full control, standard `hosted` pub syntax for customers, no per-seat vendor cost | We operate it (small: one VM + object storage) |
| B. Cloudsmith (managed pub registry) | Zero ops | Recurring vendor cost, vendor lock-in for the delivery path |
| C. Git-URL dependency + access tokens | Zero infra | No versioning UX, pub resolution quirks, token sprawl in customer CI |

Recommendation: **A**, with B as the fallback if operating unpub proves annoying during the design-partner pilot.

## Decision record

- License model: <A or B — recorded from owner answer>
- Distribution channel: <A, B, or C — recorded from owner answer>
- Decided by: <owner>, <date>

## Owner-action slots (roadmap reserves these; not blocking engineering)

- [ ] Naming/trademark check for the public product name (owner, before week 18 docs-site work).
- [ ] Pricing hypothesis anchored under Scanbot's per-app pricing (owner, before design-partner conversations, ~week 20).
```

- [ ] **Step 2: Get the owner's decision and record it**

This is a genuine owner decision. If executing as a subagent, return to the coordinator with the two questions; the coordinator asks the owner (AskUserQuestion): license model A/B, channel A/B/C. Write the answers into the `## Decision record` block and set the `Status:` line. Do not commit the file with `<...>` placeholders remaining.

- [ ] **Step 3: Verify and commit**

```bash
grep -n "<.*>" docs/commercial/DISTRIBUTION.md && echo "PLACEHOLDERS REMAIN — fix before commit" || true
git add docs/commercial/DISTRIBUTION.md
git commit -m "docs(commercial): record distribution and license model decision"
```

Expected: the grep prints nothing; commit succeeds.

---

### Task 4: Track C — tier map & offline license-key decision

**Files:**
- Create: `docs/commercial/TIERS.md`

**Interfaces:**
- Consumes: spec §5 tier names (Core / Smart Capture / Data & Identity); `docs/SYMBOLOGIES.md` and `docs/ENHANCEMENT.md` for the current feature inventory.
- Produces: the feature→tier table and key-format decision the gating implementation (weeks 18–26) and the docs-site feature matrix are built from. Tier names used here are final — later phases must not rename them.

- [ ] **Step 1: Write `docs/commercial/TIERS.md`**

```markdown
# Feature tiers & license enforcement — decision record

**Date:** <today's date>
**Status:** Decided (design-level; implementation lands weeks 18–26 per the roadmap spec)

## Tiers

| Feature | Core | Smart Capture | Data & Identity |
|---|---|---|---|
| Barcode scanning (all symbologies in docs/SYMBOLOGIES.md, single + batch + find-and-pick) | ✓ | ✓ | ✓ |
| Document scanning, classical detection, enhance modes off/fast/balanced/max | ✓ | ✓ | ✓ |
| Scanbot-compat facade (compat/ package) | ✓ | ✓ | ✓ |
| ML document detection (`detectorMode: auto\|ml`, DSQ2) | — | ✓ | ✓ |
| Shadow removal + grayscale/B&W output modes (DSQ3) | — | ✓ | ✓ |
| ≥300 DPI output policy + max-res capture path (DSQ1) | — | ✓ | ✓ |
| Invoice extraction (post promotion-gate; "beta" label if gate missed, per spec risk 4) | — | — | ✓ |
| MRZ recognition (TD1/TD2/TD3) | — | — | ✓ |

Tiers are strictly cumulative. `detectorMode: classical` stays in Core so the compat
surface never degrades for the retailer app, which runs Core-equivalent internally.

## Enforcement: offline signed license key

- Key = compact JSON claims `{licensee, appIds[], tier, expiry, issuedAt}` signed with Ed25519; the SDK embeds only the public key. Verified once at init, cached in memory.
- **No network anywhere** — verification is pure crypto, satisfying the repo's no-network-in-scan-path rule and making "works fully offline" a sales feature.
- Missing/invalid key → SDK runs in Core tier with a one-line log, never a crash or a nag dialog inside scan flows (the retailer app must be unaffected if a key is absent).
- Expired key → features keep working for the shipped app; expiry gates *SDK updates*, not runtime (perpetual-fallback licensing, the model devs hate least).
- Gating is flag-checked at feature entry points in the Dart layer (e.g. constructing an MRZ scanner without the tier throws `SupyLicenseError` at init-time, not mid-scan). No channel changes.
- Key issuance tooling: weeks 18–26, offline CLI in `tools/`; the Ed25519 private key never enters this repo (per house secret rules).

## Out of scope here

Implementation, key formats beyond claim names, and issuance workflows — deferred to the packaging phase plan.
```

Fill `<today's date>`. Cross-check the Core feature rows against `docs/SYMBOLOGIES.md` and `docs/ENHANCEMENT.md` while writing so the table names real, existing capabilities.

- [ ] **Step 2: Verify and commit**

```bash
grep -n "<.*>" docs/commercial/TIERS.md && echo "PLACEHOLDERS REMAIN" || true
git add docs/commercial/TIERS.md
git commit -m "docs(commercial): define feature tiers and offline license-key enforcement"
```

Expected: grep prints nothing; commit succeeds.

---

### Task 5: S3-10 — memory profile pass (device-gated)

**Files:**
- Modify: `docs/QA.md` (add subsection after the `## Performance targets` table, ~line 297)
- Modify: `TODO.md:40` (tick S3-10)

**Interfaces:**
- Consumes: example app (`example/`), one physical Android device + one physical iPhone.
- Produces: recorded steady-state and peak memory numbers in `docs/QA.md`. Note: per QA.md §~323, these numbers do NOT gate the v1.0.1 sign-off — Task 6 may proceed in parallel if devices are shared.

- [ ] **Step 1: Run the example app in profile mode on Android and capture numbers**

```bash
cd example && flutter run --profile -d <android-device-id>
```

Scenarios (2 minutes each, via the demo home screen): (a) idle home, (b) single-barcode scan running continuously, (c) batch barcode session, (d) document capture including one full capture+enhance cycle, (e) return to home after (d). After each scenario, in a second terminal:

```bash
adb shell dumpsys meminfo $(adb shell cmd package list packages | grep -o 'io.supy[^ ]*example[^ ]*') | grep "TOTAL PSS"
```

Record the PSS value per scenario. Expected: (e) within ~5 MB of (a) — that's the H1-era heap-return invariant; a large gap is a leak finding, file it in TODO.md rather than hiding it.

- [ ] **Step 2: Repeat on iPhone with Xcode Instruments**

Open `example/ios/Runner.xcworkspace` in Xcode, Product → Profile (⌘I) → Allocations template, run the same five scenarios, record "Persistent Bytes" (total) per scenario. Same invariant: (e) ≈ (a).

- [ ] **Step 3: Record the numbers in `docs/QA.md`**

Insert directly after the Performance targets table (before `### Bench run command`):

```markdown
### Memory profile (S3-10)

Recorded <date>, profile mode, examples app.

| Scenario | Android <device model> PSS | iPhone <model> persistent bytes |
|---|---|---|
| Idle home | <n> MB | <n> MB |
| Single-barcode continuous | <n> MB | <n> MB |
| Batch session | <n> MB | <n> MB |
| Document capture + enhance | <n> MB | <n> MB |
| Return to home | <n> MB (Δ vs idle: <n>) | <n> MB (Δ vs idle: <n>) |

Invariant checked: return-to-home within 5 MB of idle on both platforms.
```

All `<...>` replaced with measured values.

- [ ] **Step 4: Tick the TODO item and commit**

In `TODO.md:40` change `- [ ] S3-10` to `- [x] S3-10` and append a dated parenthetical noting the devices used, matching the existing house style on completed items.

```bash
git add docs/QA.md TODO.md
git commit -m "docs(qa): record S3-10 memory profile numbers"
```

---

### Task 6: H4-07 — QA walk + mobile-lead sign-off (device- and human-gated)

**Files:**
- Modify: `docs/QA.md` `## Sign-off (v1.0.1)` section (~line 330 — the pre-built 27-scenario checklist + decision block)
- Modify: `TODO.md:182` (H4-07) and `TODO.md:51` (S4-08)

**Interfaces:**
- Consumes: `main` post-Task-1, one Android device + one iPhone, the mobile lead.
- Produces: signed v1.0.1 QA record — the gate for Task 7.

- [ ] **Step 1: Build and install the example app from `main` on both devices**

```bash
git checkout main && git pull
cd example
flutter run --release -d <android-device-id>   # then again with -d <iphone-id>
```

Expected: app launches to the demo home on both devices.

- [ ] **Step 2: Walk the 27 in-scope scenarios**

Scope per QA.md's own per-release table: `B1–B12, NC1–NC2, D1–D11, Bt1–Bt2` (B13 and D12 are explicitly out of scope for v1.0.x). The tester (mobile lead, or owner with mobile lead reviewing) checks each box in the `## Sign-off (v1.0.1)` template's Android and iPhone columns. Patch-release criterion, verbatim from QA.md: "tester notices no behavioral change vs. prior tag." Any behavioral difference vs. v1.0.0 is a STOP — file it in TODO.md and fix before tagging; do not sign with known regressions.

- [ ] **Step 3: Complete the decision block and tick the TODO items**

Fill the decision block in `docs/QA.md` (tester name, devices, date, verdict). In `TODO.md`: tick H4-07 (line 182) and S4-08 (line 51), each with a dated parenthetical naming the signer and devices.

- [ ] **Step 4: Commit**

```bash
git add docs/QA.md TODO.md
git commit -m "docs(qa): complete v1.0.1 sign-off walk (H4-07, S4-08)"
```

---

### Task 7: H4-08 — tag v1.0.1

**Files:**
- Modify (script-driven): `pubspec.yaml`, `ios/supy_scanner.podspec`, `android/build.gradle` (0.1.0 → 1.0.1 in lock-step)
- Modify: `TODO.md:183` (tick H4-08)

**Interfaces:**
- Consumes: signed QA record (Task 6); `CHANGELOG.md` `## [1.0.1]` heading (already present, H4-06); `tools/release.sh` gates.
- Produces: annotated tag `v1.0.1` on `main` — Track A1 exit; the roadmap's first release-train stop.

- [ ] **Step 1: Pre-flight**

```bash
git checkout main && git pull
git status --short          # expected: empty
git tag -l v1.0.1           # expected: empty
grep -n "## \[1.0.1\]" CHANGELOG.md   # expected: one hit
```

- [ ] **Step 2: Run the release script**

```bash
tools/release.sh 1.0.1
```

Expected: version bump in all three files, `dart analyze --fatal-infos` and `flutter test` pass, release commit created, annotated tag `v1.0.1` created. The script does NOT push — that's deliberate.

- [ ] **Step 3: Review the release diff, then push**

```bash
git show --stat HEAD        # expect exactly the three version files (+CHANGELOG if the script touches it)
git push origin main --follow-tags
```

Expected: `main` and `v1.0.1` visible on origin; CI green on the release commit (`gh run watch` if you want to confirm).

- [ ] **Step 4: Tick H4-08 and commit**

Tick `TODO.md:183` with a dated parenthetical (tag SHA, date).

```bash
git add TODO.md
git commit -m "chore: tick H4-08 — v1.0.1 tagged"
git push
```

**Phase 1 exit:** v1.0.1 tagged and pushed; `docs/commercial/` holds three decision docs; TODO items S3-10, S4-08, H4-07, H4-08 ticked. Next plan: Track A2 (zxing iOS bridge et al.) — verify item-by-item what's truly left before writing it, per the spec.
