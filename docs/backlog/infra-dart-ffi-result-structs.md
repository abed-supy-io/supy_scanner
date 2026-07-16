# infra-dart-ffi-result-structs

**Status:** planned · **Target:** v1.4.0 · **Effort:** L · **Trace:** docs/ARCHITECTURE.md "eventually dart:ffi"

## Problem
Per-frame results currently cross MethodChannel/EventChannel as serialized maps. For high-throughput batch scanning the JSON-ish marshalling is non-trivial cost. ARCHITECTURE.md flags `dart:ffi` for native core result structs as the eventual path.

## Scope
- Expose `supy_core_decode_result` as an FFI-stable struct under `lib/src/ffi/`.
- Keep MethodChannel as the default; FFI is opt-in via a single flag.
- Iso-functional with the channel path (parity tests in the same suite).

## Out of scope
- Replacing the channel for control-plane methods (`prewarm`, `requestCameraPermission`, etc.).
- Live frame transport via FFI — that's a different epic.

## Acceptance
- [ ] FFI path returns ≥ 30% less per-result overhead measured by perfgate.
- [ ] Parity tests green vs. channel path.

## Dependencies
- ABI version bump or guard via `SUPY_CORE_ABI_VERSION`.

## Source
- `docs/ARCHITECTURE.md` — native core C ABI section.
