# RELEASE — Cutting a `supy_scanner` Version

The release runbook. Pairs with [`tools/release.sh`](../tools/release.sh) and [`docs/REPRODUCIBLE_BUILDS.md`](REPRODUCIBLE_BUILDS.md).

This library ships **source plus native code** — `supy_scanner` does not produce a shippable binary on its own. The actual APK/IPA is built by the retailer app. That means symbolication discipline is split:

- **Library side (this repo):** preserve and tag the native + Dart sources at known commits, so any frame from a crash report can be resolved to a source line by `git checkout <tag>`.
- **App side (retailer repo):** retain the Android R8 mapping, native `.so` debug symbols, iOS dSYMs, and Flutter split-debug-info per build, and feed them to the retailer's crash reporter.

Both sides are required to fully symbolicate a stack from production. Neither side alone is sufficient.

---

## 1 — Pre-release gates

Every release tag must satisfy, in order:

1. **CHANGELOG entry written.** `## [X.Y.Z]` heading added in `CHANGELOG.md`, with the date as `YYYY-MM-DD` and entries grouped under the same headings used in prior entries (`Added`, `Fixed`, `Hardened`, `Docs`, `Channel`).
2. **QA walk passed.** `docs/QA.md` scenarios re-walked on one Android + one iPhone from the matrix. Sign-off recorded in `TODO.md`.
3. **Phase scope clean.** No `[ ]` items in `TODO.md` for the sprint this release closes out (or, if any remain, each is explicitly deferred to a named follow-up sprint).
4. **Re-run the gates locally**: `flutter analyze --fatal-infos`, `flutter test`, and a clean `flutter pub get` on the `example/` app.
5. **No uncommitted changes.** On `main`. Tag `vX.Y.Z` does not already exist.

`tools/release.sh <version>` enforces (1) and (5), then runs the analyze + test gate. (2)–(4) are operator responsibility.

---

## 2 — Cutting the release

```sh
tools/release.sh 1.0.1
# Review the commit + tag:
git show v1.0.1
# Push:
git push origin main
git push origin v1.0.1
```

Publishing to pub.dev is **not automated**. Only run after the retailer cut-over plan is signed off:

```sh
flutter pub publish --dry-run
flutter pub publish
```

If `dry-run` lists files that should not ship (build artifacts, `.dart_tool/`, personal notes), fix the publish-time excludes in `pubspec.yaml` and CHANGELOG-note it; do not work around with `--force`.

---

## 3 — Symbolication discipline

### 3.1 Why this matters

The retailer app's crash reporter (Sentry / Crashlytics / etc.) captures stacks that cross three layers:

```
[Dart frames]  ← Flutter / supy_scanner Dart
[JNI / ObjC]   ← supy_scanner Kotlin + Swift glue
[Native .so]   ← v1.1+: native C++ core (zxing-cpp, libdmtx, perf kernels)
```

The Dart and Kotlin/Swift layers are tractable with normal app-side mapping. The native `.so` frames are the trap: without per-build debug symbols **and** a matching source checkout, a crash in our C++ core symbolicates as a bare offset and triage stops.

### 3.2 What the library guarantees

For every tag `vX.Y.Z`:

- The native source state is recoverable via `git checkout vX.Y.Z`.
- `native/` source tree is fully committed — no vendored binaries, no out-of-tree includes.
- `android/src/main/cpp/CMakeLists.txt` and `ios/Classes/native/SupyNativeCoreImpl.mm` reference only paths inside the repo.
- The set of pinned toolchain versions in [`docs/REPRODUCIBLE_BUILDS.md`](REPRODUCIBLE_BUILDS.md) §2 is honored by the tag's `android/build.gradle` and `ios/supy_scanner.podspec`.

This is what lets a retailer engineer with only a crash report and a tag rebuild a symbol-equivalent binary for re-symbolication.

### 3.3 What the retailer build must retain — per release

| Artifact | Source | Where to put it | Retention |
|---|---|---|---|
| R8 mapping (`mapping.txt`) | Android release build (`./gradlew :app:assembleRelease`) | Retailer's crash-reporter upload + app-side artifact bucket | ≥ 12 months past tag deprecation |
| Native debug `.so`s (Android) | `app/build/intermediates/merged_native_libs/release/out/lib/<abi>/*.so` (un-stripped) | Same bucket, keyed by `applicationId`+`versionCode`+`abi` | Same |
| iOS dSYM bundles | Xcode archive → `.xcarchive/dSYMs/*.dSYM` | Crash-reporter dSYM upload | ≥ 12 months |
| Flutter split-debug-info | `flutter build apk --split-debug-info=<dir> --obfuscate` (or `appbundle`/`ipa`) | Same bucket, keyed by `versionCode`/`CFBundleVersion` | Same |

The library does **not** dictate the retailer's storage layout — it dictates that all four artifact classes must be retained per build, keyed to a recoverable build identifier.

### 3.4 Build flags the retailer must use

Document the following in the retailer app's release runbook (not in this repo, but called out here so the contract is explicit):

- **Flutter build flag set:** `--obfuscate --split-debug-info=build/symbols/<versionCode>` is mandatory for production. Forgetting `--split-debug-info` strips Dart frames into hex offsets that cannot be recovered after-the-fact.
- **Android NDK:** `ndk { debugSymbolLevel "FULL" }` in the app's `android/app/build.gradle` to ensure the un-stripped `.so` ends up in `merged_native_libs/release/out/lib/<abi>/`. Play Console requires this for native crash mapping.
- **iOS:** `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` on the Release configuration (Xcode default), `STRIP_INSTALLED_PRODUCT = YES`, **dSYMs uploaded to the crash reporter at archive time** (Run Script phase or Fastlane).
- **R8:** keep R8 enabled (it ships now). Upload `mapping.txt` to the crash reporter on every release build; never disable shrinking to avoid mapping work.

### 3.5 Symbolicating a crash post-hoc

When a crash report lands and a stack frame from `libsupy_native_core.so` or `SupyScanner.framework` is unresolved:

1. **Identify the library version** in the report (app `versionCode`/`CFBundleVersion` → retailer build → embedded `supy_scanner` version). The retailer build manifest is the source of truth for the supy_scanner version, not the library repo.
2. **Check out the matching tag**: `git checkout vX.Y.Z` in this repo.
3. **Resolve native frames**:
   - **Android (`.so`):** `${NDK}/toolchains/llvm/prebuilt/<host>/bin/llvm-addr2line -e path/to/libsupy_native_core.so -f -C -p <offset>`. Use the un-stripped `.so` from §3.3.
   - **iOS (dSYM):** `atos -arch arm64 -o SupyScanner.framework.dSYM/Contents/Resources/DWARF/SupyScanner -l <loadAddr> <addr>`.
4. **Resolve Dart frames** with `flutter symbolize -i <stack.txt> -d <split-debug-info-dir>/app.android-arm64.symbols` (or the matching iOS / arm-v7 symbol file).

If a frame cannot be resolved because the retailer build did not retain its mapping files: that is a retailer-side runbook violation, not a library bug. Open a follow-up ticket with retailer mobile team.

### 3.6 Symbol parity for v1.1+ native core

The v1.1 C++ core (`native/`) compiles with `-g -O2 -fno-omit-frame-pointer` in both pipelines. Optimization level is fixed at `-O2` — do not lower for "easier debugging," because that would diverge the production binary from the symbol-correlated one. If a specific incident requires `-O0`, build a tagged hot-fix and ship through the normal release path; never publish an `-O0` artifact to retailer production.

---

## 4 — Hot-fix flow

For a vX.Y.(Z+1) hot-fix off a shipped vX.Y.Z:

```sh
git checkout -b hotfix/vX.Y.Z+1 vX.Y.Z
# … apply minimal fix, run QA for the affected scenario only …
# Update CHANGELOG with a [X.Y.Z+1] entry — date today.
# Cherry-pick / forward-port the fix onto main in a separate PR.
tools/release.sh X.Y.Z+1
git push origin hotfix/vX.Y.Z+1
git push origin vX.Y.Z+1
```

Hot-fix branches stay alive until the forward-port lands on `main`; do not delete prematurely.

---

## 5 — Deprecating a version

When a tag is retired (e.g. retailer no longer ships any build embedding it):

- Add an entry under a `### Retired` heading in `CHANGELOG.md` for the *current* version's entry, listing which prior versions are retired and when.
- The retailer is responsible for purging their symbol bucket after the retention window in §3.3.
- The library never deletes a tag.

---

## 6 — Release-time risks (run through these before pushing)

| Risk | Detection |
|---|---|
| Version drift between `pubspec.yaml` / podspec / `build.gradle` | `tools/release.sh` post-bump grep |
| CHANGELOG entry missing or stale | `tools/release.sh` heading grep |
| Retailer build pipeline strips native debug symbols | App-side runbook §3.4 audit |
| dSYM upload step silently failing | Crash reporter dSYM-presence health check |
| Forgot `--obfuscate --split-debug-info` on Flutter build | Crash report shows Dart frames as `???` / hex offsets |
| Tag pushed before CI green | `git tag --contains` check before publishing |

If you can't tick every box in §1 + §3.4 in under five minutes, do not push.
