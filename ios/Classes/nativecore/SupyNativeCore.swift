// Thin Swift facade over the supy_scanner native core.
//
// Swift talks to the Obj-C `SupyNativeCoreBridge` class instead of calling
// the C ABI directly. CocoaPods' auto-generated umbrella module doesn't
// reliably expose C symbols from parent-directory headers to in-module
// Swift files, so an Obj-C wrapper in Classes/ is the portable path.

import Foundation

enum SupyNativeCore {
    static func version() -> String {
        return SupyNativeCoreBridge.version()
    }

    static func abiVersion() -> Int32 {
        return SupyNativeCoreBridge.abiVersion()
    }
}
