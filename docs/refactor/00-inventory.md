# 00 - Repository inventory (pre-restructure baseline)

Snapshot of `supy_scanner` as it existed at the start of the monorepo
restructure (branch `refactor/monorepo-restructure`). This is the factual
baseline the mapping in `01-mapping.md` is written against. It mirrors section
2.0 of `TODO.md`; if the two ever disagree, `TODO.md` section 2.0 is the source
of truth and this file should be reconciled to it.

## Top-level layout (tracked)

| Path | What it is |
|---|---|
| `lib/` | Flutter plugin Dart surface (public `Supy*` API, channel, licensing). |
| `android/` | Android plugin: Kotlin (`io.supy.scanner`) + JNI C++ bridge. |
| `ios/` | iOS plugin: Swift (`SupyScanner`) + Obj-C++ bridge, podspec, SPM manifest. |
| `native/` | Shared C++17 core (barcode, document, enhance, quality) + CMake build. |
| `test/` | Dart unit tests for the plugin. |
| `example/` | Example Flutter app that consumes the plugin via a path dependency. |
| `compat/supy_scanner_scanbot_compat/` | Scanbot drop-in compatibility shim package. |
| `tools/` | Dart bench harness (`bench/`), perfgate regression gate (`perfgate/`), the zxing xcframework build script. |
| `bench/corpus/` | DSQ bench corpus fixtures (Git LFS for binary scenes). |
| `supy-licensing-backend/` | Node/Express/Stripe licensing service that signs Ed25519 tokens. |
| `supy-scanner-website/` | Marketing / docs website. |
| `docs/` | PLAN, ARCHITECTURE, MIGRATION, SYMBOLOGIES, QA sources of truth. |
| `pubspec.yaml`, `analysis_options.yaml` | Root Flutter plugin manifest + lints. |
| `README.md`, `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`, `CLAUDE.md`, `TODO.md` | Repo-level docs. |

## Load-bearing invariants (must survive the restructure unchanged)

- **Dart package name** `supy_scanner` - retailer app depends on it by name.
- **Channel name** `io.supy.scanner/v1` - never bumped silently.
- **Android package root** `io.supy.scanner`; **iOS module** `SupyScanner`.
- **JNI library / CMake target** `supy_scanner_core`, source `supy_scanner_core.cpp`.
- **License token format** `supy-lic.v1.<b64url(payload)>.<b64url(sig)>` - must
  stay byte-compatible between the backend signer and the Dart verifier.
- **Scanbot-compat API surface** - no prop / arg / return-type changes.

## Build-system coupling web (why moves are not free)

- `native/CMakeLists.txt` pulls the Android JNI `.cpp` by a `../android/...`
  relative path, and (via `if(ANDROID)`) is invoked from Gradle.
- `android/build.gradle` points `externalNativeBuild` at `../native/CMakeLists.txt`.
- `ios/supy_scanner.podspec` reaches the core via `../native/...` and runs
  `../tools/build_zxing_xcframework.sh` as its `prepare_command`.
- `ios/supy_scanner/Package.swift` reaches the core through three relative
  symlinks under `Sources/`, one of which (`objc/native`) points at repo-root
  `native/`.
- `tools/build_zxing_xcframework.sh`, `tools/bench/run_bench.dart`, and
  `tools/perfgate/enhance/run_enhance_bench.dart` invoke CMake with `native/`
  as the source dir.
- `example/pubspec.yaml` and `compat/.../pubspec.yaml` depend on the plugin by
  relative path.
- `.gitattributes` LFS filters and CI (`.github/workflows/ci.yml`) hard-code
  `example`, `compat/...`, and `bench/corpus` paths.

A faithful move to the target layout requires rewiring every edge above in the
same change, or the Android / iOS / bench builds break.
