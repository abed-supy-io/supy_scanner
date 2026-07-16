# dx-compat-shim-retailer-pin

**Status:** done (CI gate wired 2026-06-17) · **Target:** v1.1.0 · **Effort:** M · **Trace:** TODO.md H2-06

## Resolution (2026-06-17)

All three scope items + both acceptance criteria are now met:

- **Inventory** — `docs/MIGRATION.md` §"Snapshot of the exact retailer files…" (line 289+) enumerates the four in-shim retailer files (`scanbot_index.dart`, `barcode_scanbot_view.dart`, `scan_barcode_counting_page.dart`, `invoice_scanner_service.dart`) and the "Out-of-shim retailer references" subsection (line 301+) names the two intentionally not mirrored (`scanbot_sdk_manager.dart`, `scanning_bot.dart`).
- **Call-site tests** — `compat/supy_scanner_scanbot_compat/test/retailer_call_sites_test.dart` has one group per in-shim retailer file with comments naming the exact line ranges the shape was lifted from; 11 tests pass locally.
- **Signature gate** — `compat/supy_scanner_scanbot_compat/test/api_signature_snapshot_test.dart` diffs the parsed `lib/src/*.dart` symbols against the checked-in `test/api_snapshot.txt`. Drift fails the test and prints the regen command.
- **CI wiring (today's fix)** — `.github/workflows/ci.yml` `analyze-and-test` now runs `flutter pub get` + `flutter test` inside `compat/supy_scanner_scanbot_compat/` after the main library tests. Before this step, the snapshot test existed but didn't execute in CI — acceptance #2 was nominal, not real.

## Problem
`supy_scanner_scanbot_compat` exposes Scanbot-shaped type aliases, but it's not pinned to the retailer call sites. The shim could silently drift away from what retailer actually invokes.

## Scope
- Inventory retailer's real call sites (`grep` the retailer repo for Scanbot symbols).
- For each, add a compat-shim test that imports through the shim path and exercises the call shape.
- Document the inventory under `docs/MIGRATION.md`.

## Out of scope
- Modifying retailer code.
- Adding new compat surfaces that retailer doesn't use.

## Acceptance
- [x] Every retailer-used Scanbot symbol has a passing compat-shim test.
- [x] CI fails if a shim function changes signature.

## Dependencies
- Read access to the retailer repo (coordinate with retailer team).

## Source
- `TODO.md` — H2-06 "compat-shim pinned to retailer".
