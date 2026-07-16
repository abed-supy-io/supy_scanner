# dx-telemetry-sink-interface

**Status:** planned · **Target:** v1.3.0 · **Effort:** S · **Trace:** TODO.md H4-01 follow-up

## Problem
`SupyLogSink` / `SupyLog` exists for log lines. Retailer wants structured perf + outcome telemetry (decode latency, fail reasons, tier) without the library taking a dependency on a specific analytics SDK.

## Scope
- `SupyTelemetrySink` interface with typed events: `BarcodeDecoded`, `DocumentCaptured`, `ScanCancelled`, `ScanFailed`.
- Default no-op sink; retailer installs a forwarder to their analytics.
- No PII in events — payload values are hashed at the sink boundary if the host needs them.

## Out of scope
- Bundling an analytics SDK (rules out a paid dep per CLAUDE.md).

## Acceptance
- [ ] Sink interface stable + documented.
- [ ] Compat shim emits the same events when the legacy Scanbot path is hit.
- [ ] Event field schema versioned (`schemaVersion: 1`).

## Dependencies
- `SupyLogSink` (already shipped).

## Source
- `TODO.md` — H4-01 native→Dart sink follow-up.
