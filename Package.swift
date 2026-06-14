// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "supy_scanner",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "supy_scanner", targets: ["supy_scanner"])
    ],
    targets: [
        // C++ native core — C ABI only (extern "C"), no Swift-C++ interop needed.
        // Shared with Android via CMakeLists.txt; SPM compiles it independently.
        .target(
            name: "supy_scanner_native_core",
            path: "native",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        // Swift plugin sources
        .target(
            name: "supy_scanner",
            dependencies: ["supy_scanner_native_core"],
            path: "ios/Classes"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
