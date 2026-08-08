# 01 - Move mapping (the contract)

Per-path disposition for the monorepo restructure toward the `TODO.md` section
5.5.2 target layout. This is the contract: every physical `git mv` and every
build-config rewire in this pass is listed here, and nothing outside this table
is moved. Verify the diff against this file.

## Guiding rule

Preserve the load-bearing invariants in `00-inventory.md`. The package name,
channel name, native package roots, and Scanbot-compat surface do **not**
change. This restructure is a relocation + build rewire, not an API change.

## Directory / file moves

| Current path | Disposition | Target path | Rationale |
|---|---|---|---|
| `native/` | move | `core/` | Section 4.2 names the shared core `core/`; header renamed to `supy_scanner.h` to match. |
| `lib/` | move | `flutter/supy_scanner/lib/` | Flutter plugin becomes a package under `flutter/`. |
| `android/` | move | `flutter/supy_scanner/android/` | Plugin platform dir must resolve relative to its own `pubspec.yaml`; stays inside the package this pass (see deviation 1). |
| `ios/` | move | `flutter/supy_scanner/ios/` | Same as android. Carries podspec + SPM manifest + symlinks. |
| `test/` | move | `flutter/supy_scanner/test/` | Dart tests live next to the package. |
| `example/` | move | `flutter/supy_scanner/example/` | Example app keeps its `path: ../` dep, which still resolves to the plugin. |
| `pubspec.yaml` | move | `flutter/supy_scanner/pubspec.yaml` | Plugin manifest. |
| `analysis_options.yaml` | move | `flutter/supy_scanner/analysis_options.yaml` | Lints apply to the moved Dart tree. |
| `compat/supy_scanner_scanbot_compat/` | move | `flutter/supy_scanner_scanbot_compat/` | Sibling Flutter package under `flutter/`. Path dep rewired `../..` -> `../supy_scanner`. |
| `supy-licensing-backend/` | move | `licensing/` | Fold the licensing service into the monorepo per the restructure scope. |
| `supy-scanner-website/` | move | `website/` | Fold the marketing/docs site into the monorepo. |
| `native/include/supy_scanner_core.h` | rename | `core/include/supy_scanner.h` | Matches section 4.2 header name. All `#include`s, the JNI `.cpp`, the `.mm` bridge, CMake, and docs updated. |
| `tools/` | stay | `tools/` | Already a target-shaped top-level dir. Internal `native/` CMake source refs rewired to `core/`. |
| `docs/`, `README.md`, `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`, `CLAUDE.md`, `TODO.md`, `.github/`, `.gitattributes`, `.gitignore` | stay | (unchanged path) | Repo-level; describe the whole monorepo. CI + LFS path strings rewired in place. |

## Build-config rewires (same change)

| File | Edit |
|---|---|
| `core/CMakeLists.txt` | JNI ref `../android/...` -> `../flutter/supy_scanner/android/src/main/cpp/supy_scanner_core_jni.cpp`. |
| `flutter/supy_scanner/android/build.gradle` | `../native/CMakeLists.txt` -> `../../../core/CMakeLists.txt`. |
| `flutter/supy_scanner/ios/supy_scanner.podspec` | `../native` -> `../../../core`; `../tools` -> `../../../tools`; `$(PODS_TARGET_SRCROOT)/../native` -> `.../../../../core`. |
| `flutter/supy_scanner/ios/supy_scanner/Sources/objc/native` (symlink) | retarget `../../../../native` -> `../../../../../../core`. Other two symlinks are plugin-internal and unchanged. |
| `flutter/supy_scanner_scanbot_compat/pubspec.yaml` | path dep `../..` -> `../supy_scanner`. |
| `tools/build_zxing_xcframework.sh` | `NATIVE_DIR="${REPO_ROOT}/native"` -> `"${REPO_ROOT}/core"`. |
| `tools/bench/run_bench.dart` | cmake `-S native` -> `-S core`. |
| `tools/perfgate/enhance/run_enhance_bench.dart` | cmake `-S ${repoRoot}/native` -> `/core`. |
| `.github/workflows/ci.yml` | `working-directory: example` -> `flutter/supy_scanner/example`; `compat/supy_scanner_scanbot_compat` -> `flutter/supy_scanner_scanbot_compat`; `dart format` paths retargeted. |

## Deviations from the 5.5.2 target (this pass)

1. **android/ and ios/ stay inside `flutter/supy_scanner/`** rather than
   becoming standalone top-level `android/` + `ios/` SDKs. A Flutter plugin
   resolves its platform dirs relative to its own `pubspec.yaml`; extracting
   them into independent published SDKs is a multi-phase effort (own Gradle /
   Maven and Pod / SPM packaging, consumer wiring) tracked separately. Moving
   them now would break the plugin build for no interim benefit.
2. **`bench/corpus/` is NOT moved to `conformance/corpus/` this pass.** The
   corpus path is hard-coded in ~11 places across the bench tooling, its tests,
   the LFS filters, and CI, and it has zero build-system coupling to the
   relocation. Moving it is pure churn that risks destabilizing the bench gate,
   so it is deferred to a dedicated follow-up. `conformance/` is therefore not
   created yet.
3. **`design/` is not created.** No design-token/asset content exists to place
   in it yet; it is a later-phase concern.

## Downstream (out of repo, cannot be done here)

- The retailer app's path/git dependency on this plugin must repoint from the
  repo root to `flutter/supy_scanner/`. This is a dependency-path change, not an
  API change - no prop, arg, or return type moves. It is called out in the
  final summary and the `TODO.md` decisions log.
