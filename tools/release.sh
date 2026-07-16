#!/usr/bin/env bash
# tools/release.sh <version>
#
# Bumps the three version sources in lock-step, runs the gates, and creates a
# release commit + annotated tag. Does NOT push and does NOT publish — the
# operator runs those manually after reviewing the diff.
#
# Version sources kept in sync:
#   - pubspec.yaml          `version: X.Y.Z`
#   - ios/supy_scanner.podspec  `s.version = 'X.Y.Z'`
#   - android/build.gradle      `version = 'X.Y.Z'`
#
# Pre-flight gates:
#   - semver shape `X.Y.Z` (no prerelease/build suffix — keep release flow simple)
#   - branch is `main`
#   - working tree clean
#   - tag `vX.Y.Z` does not exist
#   - `CHANGELOG.md` contains a `## [X.Y.Z]` heading
#   - `flutter analyze --fatal-infos` passes
#   - `flutter test` passes
#
# Idempotent re-runs: if every version file already matches X.Y.Z the bump step
# is a no-op; the gate + commit + tag flow still runs.
#
# Usage:
#   tools/release.sh 1.0.1
#   SKIP_TESTS=1 tools/release.sh 1.0.1   # skip `flutter test` (CI runs it)

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: tools/release.sh <version>" >&2
  exit 64
fi

VERSION="$1"
TAG="v${VERSION}"

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: '${VERSION}' is not a bare semver (X.Y.Z required)" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

PUBSPEC="pubspec.yaml"
PODSPEC="ios/supy_scanner.podspec"
GRADLE="android/build.gradle"
CHANGELOG="CHANGELOG.md"

for f in "${PUBSPEC}" "${PODSPEC}" "${GRADLE}" "${CHANGELOG}"; do
  if [[ ! -f "${f}" ]]; then
    echo "error: required file missing: ${f}" >&2
    exit 65
  fi
done

# Gate: branch.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${BRANCH}" != "main" ]]; then
  echo "error: must release from 'main' (current: ${BRANCH})" >&2
  exit 65
fi

# Gate: working tree clean.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree has uncommitted changes" >&2
  git status --short >&2
  exit 65
fi

# Gate: tag doesn't exist.
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "error: tag ${TAG} already exists" >&2
  exit 65
fi

# Gate: CHANGELOG entry exists.
if ! grep -qE "^## \[${VERSION}\]" "${CHANGELOG}"; then
  echo "error: ${CHANGELOG} has no '## [${VERSION}]' heading — write the entry first" >&2
  exit 65
fi

echo "==> Bumping versions to ${VERSION}"

# pubspec.yaml — single-line version: X.Y.Z
sed -i.bak -E "s/^version:[[:space:]]+.+$/version: ${VERSION}/" "${PUBSPEC}"
rm "${PUBSPEC}.bak"

# podspec — s.version = 'X.Y.Z' (preserve indentation + quote style)
sed -i.bak -E "s/^([[:space:]]*s\.version[[:space:]]*=[[:space:]]*')[^']+(')/\1${VERSION}\2/" "${PODSPEC}"
rm "${PODSPEC}.bak"

# build.gradle — version = 'X.Y.Z'
sed -i.bak -E "s/^(version[[:space:]]*=[[:space:]]*')[^']+(')/\1${VERSION}\2/" "${GRADLE}"
rm "${GRADLE}.bak"

# Verify every file now contains the target version exactly once on its bump line.
verify_line() {
  local file="$1" pattern="$2"
  if ! grep -qE "${pattern}" "${file}"; then
    echo "error: post-bump verification failed in ${file} (pattern: ${pattern})" >&2
    exit 70
  fi
}
verify_line "${PUBSPEC}" "^version: ${VERSION}$"
verify_line "${PODSPEC}" "s\\.version[[:space:]]*=[[:space:]]*'${VERSION}'"
verify_line "${GRADLE}"  "^version[[:space:]]*=[[:space:]]*'${VERSION}'"

# Gate: analyze + test.
echo "==> flutter analyze --fatal-infos"
flutter analyze --fatal-infos

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo "==> flutter test"
  flutter test
else
  echo "==> skipping flutter test (SKIP_TESTS=1)"
fi

# Diff preview.
echo "==> git diff (release commit will contain):"
git --no-pager diff --stat

# Stage exactly the files we touched — never `git add -A`.
git add "${PUBSPEC}" "${PODSPEC}" "${GRADLE}"

if git diff --cached --quiet; then
  echo "==> no version changes to commit (already at ${VERSION}); skipping commit"
else
  git commit -m "release: ${TAG}"
  echo "==> committed release: ${TAG}"
fi

echo "==> tagging ${TAG}"
git tag -a "${TAG}" -m "Release ${TAG}"

cat <<EOF

Release ${TAG} prepared locally.

Next steps (run manually after reviewing the commit + tag):

  git show ${TAG}
  git log --oneline -n 5
  git push origin main
  git push origin ${TAG}

  # Pub.dev publish (only when retailer cut-over plan is signed off):
  flutter pub publish --dry-run
  flutter pub publish

EOF
