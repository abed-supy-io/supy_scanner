---
name: cut-a-release
description: Use when tagging a new supy_scanner version — gates the release on QA sign-off, CHANGELOG accuracy, and pubspec version bump in a strict order.
---

# Cut a supy_scanner release

## Pre-flight

Stop and verify before tagging. Do not proceed if any of these are red.

1. **`TODO.md`** — every ticket for the target version is checked off. If anything is still open, surface it and stop.
2. **CI on `main`** — last build green: analyze, format, test, example builds for both platforms.
3. **`docs/QA.md` walkthrough** — every scenario for the target version has been walked on at least one Android device and one iPhone. Results recorded under a `## Sign-off (vX.Y.Z)` heading in `docs/QA.md`.

## Release steps (in order)

1. **Update `CHANGELOG.md`** — Keep-a-Changelog format. Group changes under `### Added / Changed / Fixed / Removed`. Reference ticket IDs from `TODO.md`.

2. **Bump `pubspec.yaml`** — change `version:` to the target. Semver:
   - Major: breaks the Scanbot-compat Dart API surface. Requires explicit retailer-team buy-in.
   - Minor: new symbology, new MethodChannel method, new public Dart symbol.
   - Patch: bug fix, perf improvement, native-side change with no Dart API impact.

3. **Commit** — `chore(release): vX.Y.Z`. Push to main via PR (no direct push).

4. **Tag** — `git tag vX.Y.Z && git push --tags`. Signed tags only.

5. **Publish** — internal pub server publish OR (interim) pin the commit SHA in the retailer cutover plan. Note the SHA / version in `TODO.md` decisions log.

6. **Announce** — Slack `#mobile-eng` with: version, what changed, what consumers need to do (if anything), link to CHANGELOG.

## What NOT to do

- **Don't tag from a dirty working tree.** `git status` must be clean.
- **Don't skip the QA walkthrough** even for "small" releases — the whole point of the package is parity with Scanbot, and parity bugs are subtle.
- **Don't amend a published tag.** If the tag is wrong, publish a new patch version.
- **Don't bump major without a written decision** in `TODO.md` decisions log — a major version means retailer has to do migration work.

## After release

- Open a follow-up issue tracking any QA findings from the sign-off walkthrough.
- Reset `TODO.md` for the next sprint.
