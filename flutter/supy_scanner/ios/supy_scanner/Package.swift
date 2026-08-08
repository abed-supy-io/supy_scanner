// swift-tools-version: 5.9
// Swift Package Manager manifest for the supy_scanner iOS plugin.
//
// This is a SECOND build path that lives alongside ios/supy_scanner.podspec —
// both compile the same sources from a single source of truth. Flutter picks
// SPM when `flutter config --enable-swift-package-manager` is on and falls
// back to CocoaPods otherwise; neither file may drift from the other.
//
// Layout (Sources/ holds only symlinks — real files stay in ios/Classes and
// the repo-root core/ tree, which is shared with Android and dart:ffi):
//
//   Sources/
//     objc/                         -> clang target root (real dir)
//       bridge  -> ../../../Classes/nativecore   (Obj-C++ bridge .mm/.h)
//       native  -> ../../../../../../core            (shared C++ core)
//     swift     -> ../../Classes                 (Swift plugin sources)
//
// SPM cannot mix Swift and Obj-C/C++ in one target, so we split into two:
//   * supy_scanner_objc — the Obj-C++ bridge PLUS the C++ core compiled
//     directly (SupyNativeCoreImpl.mm's `#if !SWIFT_PACKAGE` include-shim is
//     therefore skipped under SPM, avoiding duplicate symbols).
//   * supy_scanner — the Swift surface; reaches the core only through the
//     bridge module via a guarded `#if SWIFT_PACKAGE import supy_scanner_objc`.
//
// Names are load-bearing: Flutter's generated umbrella references this package
// as `supy_scanner` and its product as `supy-scanner`, and the plugin
// registrant does `import supy_scanner` / `SupyScannerPlugin`. Do not rename.

import PackageDescription

let package = Package(
    name: "supy_scanner",
    platforms: [
        .iOS("16.0"),
    ],
    products: [
        .library(name: "supy-scanner", targets: ["supy_scanner"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        // Obj-C++ bridge + shared C++ core. Mirrors the podspec's
        // Classes/** + ../../../core compile and header search paths. zxing-cpp /
        // libdmtx stay gated off here (no SUPY_WITH_ZXING_CPP define), matching
        // the default `pod install` path; enabling them under SPM is a
        // separate follow-up.
        .target(
            name: "supy_scanner_objc",
            path: "Sources/objc",
            // Explicit list: the target dir also contains *_test.cpp, bench
            // sources, and SupyNativeCoreImpl.mm (a CocoaPods-only shim) that
            // must NOT be compiled here.
            sources: [
                "bridge/SupyNativeCoreBridge.mm",
                "native/src/supy_scanner_core.cpp",
                "native/barcode/barcode_decoder.cpp",
                "native/barcode/binarize.cpp",
                "native/barcode/temporal.cpp",
                "native/barcode/datamatrix_locator.cpp",
                "native/document/document_guidance_classifier.cpp",
                "native/document/perspective_warp.cpp",
                "native/quality/frame_scorer.cpp",
                "native/enhance/pipeline.cpp",
                "native/enhance/illumination.cpp",
                "native/enhance/tone.cpp",
                "native/enhance/unsharp.cpp",
                "native/enhance/quality_gate.cpp",
                "native/enhance/morphology.cpp",
                "native/enhance/tophat.cpp",
                "native/enhance/clahe.cpp",
            ],
            // Only SupyNativeCoreBridge.h is public; the C++ headers under
            // native/ stay private so they never leak into the Swift module.
            publicHeadersPath: "bridge",
            cxxSettings: [
                .headerSearchPath("native/include"),
                .headerSearchPath("native/barcode"),
                .headerSearchPath("native/document"),
                .headerSearchPath("native/quality"),
                .headerSearchPath("native/enhance"),
            ]
        ),
        // Swift plugin surface. Depends on the bridge module and on Flutter.
        .target(
            name: "supy_scanner",
            dependencies: [
                "supy_scanner_objc",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/swift",
            // The Obj-C++ bridge lives here too (Classes/nativecore) but belongs
            // to the other target; a Swift target may only contain Swift files.
            exclude: ["nativecore"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
