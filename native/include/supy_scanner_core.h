// supy_scanner native core — C ABI.
//
// Sprint 1 (v1.1 plan): version probe only. The symbols here are the
// surface that Android JNI, iOS Swift, and dart:ffi all bind to.
//
// IMPORTANT: pixel buffers MUST NOT cross this ABI from the Dart side.
// Pixel data stays inside the native process: camera -> C++ core -> ML
// Kit / Vision. Only result structs (decoded payloads, doc page URIs)
// are allowed to traverse dart:ffi.

#ifndef SUPY_SCANNER_CORE_H_
#define SUPY_SCANNER_CORE_H_

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define SUPY_CORE_EXPORT __declspec(dllexport)
#else
#define SUPY_CORE_EXPORT __attribute__((visibility("default")))
#endif

// Returns the semver string of the native core, e.g. "1.1.0-dev.1".
// Pointer is to a static string with program lifetime — do not free.
SUPY_CORE_EXPORT const char* supy_core_version(void);

// Returns 1 if this build matches the channel surface the Dart side
// expects; 0 otherwise. The expected value is `SUPY_CORE_ABI_VERSION`.
SUPY_CORE_EXPORT int supy_core_abi_version(void);

#define SUPY_CORE_ABI_VERSION 1

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // SUPY_SCANNER_CORE_H_
