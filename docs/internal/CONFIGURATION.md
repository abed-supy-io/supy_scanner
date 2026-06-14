# supy_scanner — Project Configuration

Internal reference for how the package is wired across Dart, iOS, Android, and the shared C++ core. Not published to consumers. For the public migration guide see `docs/MIGRATION.md`; for architectural rationale see `docs/ARCHITECTURE.md` and `docs/V1.1_PLAN.md`.

---

## 1. Repo layout

```
supy-scanner/
├── lib/                              Dart public API (Supy* prefix)
│   ├── supy_scanner.dart             barrel export
│   └── src/
│       ├── channel/                  MethodChannel + EventChannel boundary
│       ├── models/                   sealed value types (@immutable)
│       ├── models/ui/                embedded-view UI configuration types
│       ├── permissions/              camera permission helper
│       └── widgets/                  embedded SupyBarcodeScannerView + sheets
├── ios/                              Flutter iOS plugin
│   ├── supy_scanner.podspec
│   └── Classes/
│       ├── SupyScannerPlugin.swift   FlutterPlugin entry, MethodCallHandler
│       ├── barcode/                  AVFoundation + Vision pipeline
│       ├── document/                 VNDocumentCameraViewController + OCR
│       └── nativecore/               Swift ↔ C++ bridge (see §5)
├── android/                          Flutter Android plugin
│   ├── build.gradle
│   └── src/main/
│       ├── kotlin/io/supy/scanner/   Plugin + barcode/document/permissions
│       ├── cpp/supy_scanner_core_jni.cpp   JNI bridge into the C++ core
│       └── AndroidManifest.xml
├── native/                           Shared C++ core (single source of truth)
│   ├── CMakeLists.txt
│   ├── include/supy_scanner_core.h   extern "C" ABI
│   └── src/supy_scanner_core.cpp
├── compat/supy_scanner_scanbot_compat/   Scanbot-named drop-in shim
├── example/                          runnable Flutter app + QA harness
├── docs/                             published docs (PLAN, ARCH, MIGRATION, …)
└── test/                             Dart unit tests (channel mocked)
```

## 2. Dart package

- **`pubspec.yaml`**: `name: supy_scanner`, `version: 0.1.0`, `publish_to: none` (consumed via git dep, not pub.dev).
- **SDK constraints**: Dart `>=3.4.0 <4.0.0`, Flutter `>=3.22.0`.
- **Runtime deps**: `flutter`, `meta` only. No `flutter_bloc` or state-management deps in the library.
- **Plugin manifest** (in `pubspec.yaml`):
  ```yaml
  flutter:
    plugin:
      platforms:
        android:
          package: io.supy.scanner
          pluginClass: SupyScannerPlugin
        ios:
          pluginClass: SupyScannerPlugin
  ```
- **Public API rule**: all exported types prefixed `Supy*`. No `Scanbot*` names in `lib/` — those live in `compat/`.
- **Channel hygiene**: no `dynamic` or `Map<String, dynamic>` leaks out of `lib/src/channel/`. Sealed classes for result variants. Value types override `==`/`hashCode`/`toString` and carry `@immutable`.

## 3. MethodChannel contract — `io.supy.scanner/v1`

The name is **versioned**. A v2 would be a parallel surface, not a breaking change. Method names and arg keys live in the table in `docs/ARCHITECTURE.md`; any new method must update that table and add a mocked unit test in the same PR. Errors surface as `PlatformException` → wrapped into a `SupyScanError` variant of the sealed result.

## 4. iOS plugin

- **Deployment target**: iOS 16. No `if #available(iOS 17, *)` branches without a fallback.
- **Swift version**: 5.9.
- **Module name**: `SupyScanner`.
- **Threading**:
  - `AVCaptureSession` start/stop on `DispatchQueue.global(qos: .userInitiated)` — never `.main`.
  - All `VNRequest` work on a background queue; results marshalled to main only at the FlutterResult boundary.
- **Podspec key fields** (`ios/supy_scanner.podspec`):
  - `source_files = 'Classes/**/*.{swift,h,m,mm}'`
  - `public_header_files = 'Classes/nativecore/SupyNativeCoreBridge.h'` (only the Obj-C bridge is umbrella-exposed)
  - `preserve_paths = '../native/include/*.h', '../native/src/*.cpp'`
  - `pod_target_xcconfig`:
    - `DEFINES_MODULE=YES`
    - `CLANG_CXX_LANGUAGE_STANDARD=c++17`, `CLANG_CXX_LIBRARY=libc++`
    - `HEADER_SEARCH_PATHS="$(PODS_TARGET_SRCROOT)/../native/include"`
    - `SWIFT_INCLUDE_PATHS="$(PODS_TARGET_SRCROOT)/../native/include"`

## 5. iOS ↔ C++ core bridge

CocoaPods has two reliability gaps when source files live in a parent directory (`../native/`):
1. C headers in `public_header_files` don't reliably land in the auto-generated umbrella module → Swift can't see C symbols.
2. `.cpp` files in `source_files` don't reliably end up in the build phase → linker errors at app link time.

Both are worked around with **Classes-local shim files** that CocoaPods always processes:

| File | Role |
|---|---|
| `Classes/nativecore/SupyNativeCoreBridge.h` | Obj-C `@interface SupyNativeCoreBridge` (umbrella-safe). |
| `Classes/nativecore/SupyNativeCoreBridge.mm` | Obj-C++ implementation; `#import "supy_scanner_core.h"` and calls the C ABI directly. |
| `Classes/nativecore/SupyNativeCoreImpl.mm` | `#include "../../../native/src/supy_scanner_core.cpp"` — forces the .cpp into the pod's build phase. |
| `Classes/nativecore/SupyNativeCore.swift` | Thin Swift facade that calls `SupyNativeCoreBridge` (never the C ABI directly). |

After any change to pod sources you **must** run `pod install` in `example/ios/` before the next device build — a stale `Pods.xcodeproj` will fail to link `_supy_core_*` symbols.

## 6. Android plugin

- **Package root**: `io.supy.scanner` (subpackages: `barcode/`, `document/`, `permissions/`, `nativecore/`).
- **Gradle**: AGP 8.3.2, Kotlin 1.9.24, `compileSdk 34`, `minSdk 24`, Java 17, NDK 26.1.10909125.
- **ABI filters**: `armeabi-v7a`, `arm64-v8a`, `x86_64` (x86_64 retained for emulator dev).
- **C++ build**: `externalNativeBuild { cmake { path '../native/CMakeLists.txt' } }` — points at the shared CMake project. `cppFlags '-std=c++17'`, `ANDROID_STL=c++_static`.
- **Native deps** (no paid SDKs, no network in scanning path):
  - `androidx.camera:camera-{core,camera2,lifecycle,view}:1.3.4`
  - `androidx.lifecycle:lifecycle-common:2.7.0`
  - `com.google.mlkit:barcode-scanning:17.3.0`
  - `com.google.android.gms:play-services-mlkit-document-scanner:16.0.0-beta1`
  - ML Kit Text Recognition v2 (Latin script only — Arabic OCR is **not** supported; see `docs/MIGRATION.md`).
- **Camera lifecycle**: `LifecycleCameraController` bound to the host `Activity` lifecycle. Never cast to `FragmentActivity` (would crash on AppCompat-less hosts).
- **ML Kit clients**: one instance per `PlatformView`; closed in `dispose()`.
- **Threading**: detection runs on the analyzer thread; main thread never blocks.

## 7. Shared native core (`native/`)

Single C++ source-of-truth shared by Android JNI, iOS Obj-C++, and (eventually) `dart:ffi`.

- `native/CMakeLists.txt`:
  - C++17, position-independent, `-fvisibility=hidden`, warnings as errors.
  - Builds `supy_scanner_core` as a `SHARED` library.
  - JNI bridge (`android/src/main/cpp/supy_scanner_core_jni.cpp`) is appended only when `ANDROID` is set.
  - Optional `SUPY_WITH_ZXING_CPP` (default OFF) gates the Sprint 2 zxing-cpp FetchContent at v2.2.1.
- ABI surface in `native/include/supy_scanner_core.h`:
  ```c
  extern "C" {
    SUPY_CORE_EXPORT const char* supy_core_version(void);
    SUPY_CORE_EXPORT int         supy_core_abi_version(void);
  }
  ```
  `SUPY_CORE_EXPORT = __attribute__((visibility("default")))` on non-Windows; ABI version macro currently `1`.

## 8. Scanbot-compat shim (`compat/supy_scanner_scanbot_compat/`)

Separate Dart package that re-exports `supy_scanner` under Scanbot-named symbols (`BarcodeScanbotView`, `BarcodeItem`, `BarcodeScannerController`, `InvoiceScannerService`). Lets the retailer app migrate import-only. The library itself never references these names — they live exclusively in this compat package.

## 9. Example app & QA

- `example/` is both a runnable demo and the QA harness — exercises every public surface.
- `docs/QA.md` lists the per-phase scenarios to walk on one Android and one iPhone before declaring a phase done.

## 10. Workflow rules

- Conventional commits: `feat(barcode): …`, `fix(ios): …`, `docs: …`.
- Tests next to code: `test/` (Dart), `androidTest/` + `Tests/` (native, when added).
- Sub-skills under `.claude/skills/`: `add-symbology`, `add-channel-method`, `cut-a-release`.
- Sprint progress tracked in `TODO.md`; phase scope in `docs/PLAN.md` and `docs/V1.1_PLAN.md`.

## 11. Non-negotiables

- **No paid SDK deps** — point of the rewrite.
- **No network in the scanning path** — on-device only.
- **Drop-in Scanbot API compat** — any breaking change to consumer-facing surface must be logged in `TODO.md`'s decisions section first.
- **No secrets** in commits, ever.
