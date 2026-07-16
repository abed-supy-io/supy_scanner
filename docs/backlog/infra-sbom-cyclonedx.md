# infra-sbom-cyclonedx

**Status:** planned · **Target:** v1.3.0 · **Effort:** S · **Trace:** docs/DEPENDENCIES.md follow-up

## Problem
We vendor third-party native sources (zxing-cpp, libdmtx) and a Flutter/Gradle/CocoaPods dep tree. There's no SBOM artifact for compliance-conscious retailers.

## Scope
- Generate a CycloneDX SBOM at release time covering Dart pub deps, Gradle deps, CocoaPods deps, and the vendored C++ libraries with their pinned versions.
- Attach the SBOM to GitHub Releases.

## Out of scope
- SPDX format (CycloneDX is fine for retailer's compliance team).
- Continuous monitoring / vuln scanning — separate ticket once SBOM exists.

## Acceptance
- [ ] Release workflow produces `sbom.cdx.json`.
- [ ] Vendored versions match `native/barcode/*/VERSION` files.
- [ ] `docs/DEPENDENCIES.md` documents the artifact location.

## Dependencies
- `docs/RELEASE.md` workflow.

## Source
- `docs/DEPENDENCIES.md` SBOM follow-up note.
