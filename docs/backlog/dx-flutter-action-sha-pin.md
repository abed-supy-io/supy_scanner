# dx-flutter-action-sha-pin

**Status:** done (verified 2026-06-17) · **Target:** v1.1.x · **Effort:** XS · **Trace:** docs/SECURITY.md follow-up

## Resolution (2026-06-17)

Both acceptance criteria met by changes already in tree:

- `.github/workflows/ci.yml` — every third-party and first-party Action is referenced by 40-char commit SHA with a `# vX.Y.Z` trailing comment (`actions/checkout`, `actions/setup-java`, `actions/upload-artifact`, `subosito/flutter-action`, `dart-lang/setup-dart`, `reactivecircus/android-emulator-runner`). `grep -nE 'uses: [^@]+@v[0-9]' .github/workflows/*.yml` returns zero hits.
- `.github/dependabot.yml` — `package-ecosystem: github-actions` runs weekly with `open-pull-requests-limit: 5`, which bumps the SHA pins automatically.

## Problem
`.github/workflows/ci.yml` references `subosito/flutter-action@v2` by tag. A tag can be moved; SHA pins can't. Supply-chain hygiene per `docs/SECURITY.md`.

## Scope
- Pin all third-party GitHub Actions to commit SHAs with a comment of the tag they came from.
- Add a Dependabot config (or equivalent) so SHAs stay current.

## Out of scope
- First-party Actions (`actions/checkout@v4` etc.) — same treatment but separate trivial PR.

## Acceptance
- [x] No remaining `@v` tag refs for third-party Actions.
- [x] Dependabot bumps the SHAs on a schedule.

## Dependencies
- None.

## Source
- `docs/SECURITY.md`.
