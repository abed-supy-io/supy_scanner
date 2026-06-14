// JNI bridge for io.supy.scanner.nativecore.SupyNativeCore.
//
// Sprint 1 (v1.1 plan): version probe only. New native methods land
// here as they're added in later sprints.

#include <jni.h>
#include "supy_scanner_core.h"

extern "C" {

JNIEXPORT jstring JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeVersion(
    JNIEnv* env, jclass /*clazz*/) {
  return env->NewStringUTF(supy_core_version());
}

JNIEXPORT jint JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeAbiVersion(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(supy_core_abi_version());
}

}  // extern "C"
