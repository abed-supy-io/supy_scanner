# REPRODUCIBLE_BUILDS.md — supy_scanner

Reproducibility posture for the v1.0.x line. Tracks H3-08.

Last verified: **2026-06-14** (commit on `main`).

## 1. What "reproducible" means here

A build is reproducible when **two builds of the same commit, on the same toolchain, on different machines, produce byte-identical artifacts** — modulo timestamps, signing, and known-nondeterministic compiler outputs.

For a Flutter plugin like `supy_scanner` we don't ship a final binary — host apps embed us. So "reproducible" maps to four narrower claims:

1. **Source inputs are pinned** — a checkout of a given commit produces the same dependency graph everywhere.
2. **Toolchain inputs are pinned** — same Flutter, same Kotlin, same Swift, same NDK.
3. **Plugin build outputs are deterministic** — the same `.aar` / pod sources / Dart `.dart` files compile to the same bytecode given the same inputs.
4. **Test outputs are deterministic** — `flutter test`, `gradle test`, and `xcodebuild test` produce the same pass/fail set across machines.

What we **don't** claim: byte-identical final host APKs/IPAs. Those depend on the host app's signing, Flutter engine version pinning in the host repo, and per-builder timestamps in `.dex` / Mach-O layout.

## 2. Pinned inputs

### 2.1 Dart / Flutter

| Input | Pinned where | Value |
|---|---|---|
| Flutter SDK | `.github/workflows/ci.yml` `env.FLUTTER_VERSION` | `3.22.3` (channel: stable) |
| Dart SDK | inherited from Flutter SDK | matches Flutter 3.22.3 (Dart 3.4.x) |
| `pubspec.yaml` | committed | runtime: `meta ^1.15.0`; dev: `flutter_lints ^4.0.0` |
| `pubspec.lock` | committed | exact transitive versions |

A consumer who pins `flutter-version: 3.22.3` and runs `flutter pub get` against our committed `pubspec.lock` will get the same Dart graph we got.

### 2.2 Android

| Input | Pinned where | Value |
|---|---|---|
| Android Gradle Plugin | `android/build.gradle` | `8.3.2` |
| Kotlin | `android/build.gradle` | `1.9.24` |
| Kover plugin | `android/build.gradle` | `0.8.3` |
| `compileSdk` / `minSdk` | `android/build.gradle` | 34 / 24 |
| NDK | `android/build.gradle` | `26.1.10909125` |
| CMake | `android/build.gradle` | `3.22.1` |
| C++ standard | `android/build.gradle` | `c++17`, `-DANDROID_STL=c++_static` |
| Java target | `android/build.gradle` | `JavaVersion.VERSION_17` |
| Kotlin JVM target | `android/build.gradle` | `17` |
| ABI filters | `android/build.gradle` | `armeabi-v7a`, `arm64-v8a`, `x86_64` |
| Dependency versions | `android/build.gradle` | exact strings (no `+`, no ranges) — see `docs/DEPENDENCIES.md` |

The plugin does not declare an `applicationId`, signing config, or release-time obfuscation — host apps own all of those.

### 2.3 iOS

| Input | Pinned where | Value |
|---|---|---|
| Deployment target | `ios/supy_scanner.podspec` | `16.0` |
| Swift version | `ios/supy_scanner.podspec` | `5.9` |
| C++ language standard | `ios/supy_scanner.podspec` `pod_target_xcconfig` | `c++17`, `libc++` |
| Defines module | `ios/supy_scanner.podspec` | `YES` |
| CocoaPods deps | `ios/supy_scanner.podspec` | `Flutter` only |
| Xcode toolchain | CI `runs-on: macos-14` | system Xcode 15.x bundled with `macos-14` |

We do **not** pin the host's exact Xcode point version — the consuming app does. CI uses whatever `macos-14` ships at the moment a job runs, which is a known source of nondeterminism we accept (see §5).

### 2.4 Native C++ core (`native/`)

| Input | Where | Value |
|---|---|---|
| Sources | `native/src/` + `native/include/` | first-party only in v1.0.x |
| Android build path | `android/build.gradle` `externalNativeBuild` → `../native/CMakeLists.txt` | shared with iOS |
| iOS build path | `ios/Classes/nativecore/SupyNativeCoreImpl.mm` `#include`s the parent-dir `.cpp` | same sources |

Both platforms compile the **same source files** with the **same standard** (`c++17`) and **same libc++** linkage — so the C++ core is reproducible up to the host compiler version. v1.1's optional `SUPY_WITH_ZXING_CPP` flag is OFF in v1.0.x and stays gated by an explicit dep audit (V1-S2-01 in TODO).

## 3. Reproducibility procedure (manual)

A reviewer who wants to verify reproducibility runs these commands on two clean machines (or two clean checkouts) and diffs the listed outputs.

### 3.1 Dart graph

```sh
flutter pub get
sha256sum pubspec.lock
flutter pub deps --json > /tmp/deps.json
sha256sum /tmp/deps.json
```

Both `pubspec.lock` and the `flutter pub deps --json` output must match across machines given the same Flutter SDK version.

### 3.2 Android dependency graph

```sh
cd example
flutter create --platforms=android --project-name supy_scanner_example .
cd android
./gradlew :supy_scanner:dependencies > /tmp/android-deps.txt
sha256sum /tmp/android-deps.txt
```

The resolved Maven graph for the `releaseRuntimeClasspath` configuration must be identical across machines pinned to the same AGP/Kotlin/Gradle versions.

### 3.3 iOS pod graph

```sh
cd example
flutter build ios --config-only --no-codesign
cd ios
pod install
sha256sum Podfile.lock
```

`Podfile.lock` lists the resolved CocoaPods graph and must match across machines on the same Xcode major version.

### 3.4 Unit tests

`flutter test`, `gradle :supy_scanner:testDebugUnitTest`, and `xcodebuild test -scheme supy_scanner-Unit-Tests` are required to produce the same pass set on the same toolchain. CI runs all three on every PR (`.github/workflows/ci.yml`).

## 4. Determinism notes per output

| Artifact | Deterministic? | Notes |
|---|---|---|
| `pubspec.lock` | yes | with same Flutter SDK. |
| `.dart_tool/` cache | no | filesystem timestamps; ignore for repro. |
| Generated `_GeneratedLocalizations.dart` | no (we don't generate any) | not applicable. |
| Android `.class` files | yes | Kotlin compiler is deterministic on same toolchain. |
| Android `.dex` (when included in host APK) | mostly | d8 emits stable output for the same inputs, but APK packaging adds a build timestamp. |
| Android `.so` (native core) | yes-ish | NDK clang is deterministic given pinned `-DANDROID_STL=c++_static`; we don't strip in the plugin layer, host app strips during release packaging. |
| iOS object files | yes-ish | clang is deterministic on same Xcode; `__TEXT,__const` ordering may shift across Xcode patch versions. |
| `Podfile.lock` | yes | with same CocoaPods + same Xcode major. |

We intentionally do **not** add `-frandom-seed=…` or `--repro` flags — those are owned by the host app's release pipeline.

## 5. Known nondeterminism / accepted gaps

| Source | Why we accept it for v1.0.x |
|---|---|
| `macos-14` runner Xcode point version drift. | The host app re-builds iOS anyway; our podspec only ships sources. A pinned `xcode-select` step is an H3-FU candidate. |
| `subosito/flutter-action@v2` tag-pinning (not SHA). | Tracked in `docs/DEPENDENCIES.md` §8 follow-ups. |
| Embedded build timestamp in `dex`/APK by host signing. | Out of scope — host app owns release packaging. |
| Test report XML files contain timestamps. | They are observation artifacts, not shipped outputs. |
| Kover coverage report XML contains a timestamp. | Same. |
| GMS Document Scanner model fetch on first device run. | Runtime download, not a build input. Doesn't affect repro of source artifacts. |

## 6. CI as a reference build

`.github/workflows/ci.yml` is the canonical build environment for v1.0.x:

- Ubuntu-latest for Dart analyze/test, Android gradle test, Android example debug APK.
- `macos-14` for iOS unit tests + example iOS build (`--no-codesign`).
- Pinned `FLUTTER_VERSION: '3.22.3'` env var.

CI failures rooted in environment drift (toolchain bump, transitive resolution change) are treated as repro failures and bisected against the matrix. The CI matrix expansion item is **H4-05**, which will add a second Flutter point version to detect SDK-driven breakage earlier.

## 7. Verification log

| Date | Verifier | Commit | Outcome |
|---|---|---|---|
| 2026-06-14 | abed@supy.io (initial) | `main` @ pre-tag | `pubspec.lock` + podspec read & cross-referenced with `docs/DEPENDENCIES.md`. CI green on both linux + macos runners on the most recent push. |

Future verifications append a row here when they happen; older rows are immutable history.

## 8. Follow-ups (informal)

| Item | Owner candidate | Trigger |
|---|---|---|
| Pin `subosito/flutter-action@v2` to a commit SHA. | infra | next CI touch (H3-FU2). |
| Pin Xcode major+minor inside the macos-14 job (`sudo xcode-select -s /Applications/Xcode_15.4.app`). | infra | before v1.0.1 tag (H4 sprint). |
| Add a `tools/repro.sh` that runs §3.1–§3.3 and prints a deterministic digest. | infra | when first external reviewer reports a repro discrepancy. |
| Add `--no-daemon --offline` gradle pass after a warm-up build for tighter repro. | android | when a divergence is observed. |
| Add `--frozen` flag once `flutter pub` supports it. | dart | Flutter SDK upgrade. |

## 9. Re-verification triggers

Re-run §3 and append a row to §7 when any of these happen:

- Flutter SDK is bumped (`FLUTTER_VERSION` change).
- Any dep in `android/build.gradle` is bumped (matches `docs/DEPENDENCIES.md` cadence).
- CocoaPods or Xcode major bumps on the CI runner image.
- A new ABI is added to `abiFilters`.
- `pubspec.lock` is touched in a way other than a `flutter create --platforms` regen.

The point of this document is **not** byte-identical APKs — that's the host app's pipeline. It's that two reviewers can stand up the same plugin source tree and disagree only about things outside our control.
