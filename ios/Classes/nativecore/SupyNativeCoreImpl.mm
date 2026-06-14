// Forces the shared C++ core implementation into the iOS pod's build
// phase. CocoaPods is unreliable about compiling source files via a
// parent-directory glob (`../native/src/*.cpp` in source_files), but a
// Classes-local file is always built — and #including the .cpp here
// keeps the single source of truth in native/src/ for Android + dart:ffi.
//
// Under Swift Package Manager the dedicated `supy_scanner_native_core`
// C target compiles the .cpp directly; including it again here would
// produce a duplicate-symbol link error.

#if !SWIFT_PACKAGE
#include "../../../native/src/supy_scanner_core.cpp"
#endif
