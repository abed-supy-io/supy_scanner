# ml-model-lifecycle

**Status:** planned · **Target:** v1.4.0 · **Effort:** M · **Trace:** hardens every ml-* entry for retailer release

## Problem
Once any model ships, retailer needs answers to: what version is on the device, can we update without a plugin release, how do we roll back, and do reproducible builds still hold? Without this, each ml-* feature becomes a one-off liability.

## Scope
- **Versioning** — every model carries a `name@version` tuple alongside `SUPY_CORE_ABI_VERSION`. Loader rejects mismatched versions.
- **Signed downloads** — optional packs (e.g. OCR languages) fetched from a retailer-owned bucket; bytes verified against a pinned public key before load.
- **Telemetry** — `SupyTelemetrySink` (`dx-telemetry-sink-interface`) emits which model fired, version, confidence, tier, latency — no PII.
- **Reproducible builds** — every bundled model checksum lives in `docs/REPRODUCIBLE_BUILDS.md` and is reproduced at build time.
- **Rollback** — a single Dart flag `SupyMlConfig.disableAll` short-circuits every ML path back to heuristics. Used as a kill-switch for retailer if a model misbehaves in production.

## Out of scope
- A custom model registry / OTA backend (use retailer's existing bucket + CDN).
- Per-user model personalization.

## Acceptance
- [ ] Loader refuses to load a model whose declared version doesn't match the registered descriptor.
- [ ] Signature-verification integration test covers good-sig, bad-sig, missing-sig.
- [ ] Kill-switch flag exercised in an integration test and documented in `docs/MIGRATION.md`.
- [ ] Reproducible build still bit-identical with bundled models included.

## Dependencies
- [ml-runtime-and-loader](ml-runtime-and-loader.md), [dx-telemetry-sink-interface](dx-telemetry-sink-interface.md), [infra-sbom-cyclonedx](infra-sbom-cyclonedx.md).

## Source
- This conversation's ML roadmap; `docs/REPRODUCIBLE_BUILDS.md`, `docs/SECURITY.md`.
