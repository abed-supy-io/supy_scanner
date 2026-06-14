// JNI bridge for io.supy.scanner.nativecore.SupyNativeCore.
//
// Sprint 1 (v1.1 plan): version probe only. New native methods land
// here as they're added in later sprints.

#include <jni.h>
#include "supy_scanner_core.h"
#include "document/document_edge_detector.h"

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

JNIEXPORT jfloatArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeDetectQuad(
    JNIEnv* env, jclass, jobject yBuffer, jint w, jint h, jint stride) {
  using namespace supy::scanner::document;
  auto* ptr = static_cast<uint8_t*>(env->GetDirectBufferAddress(yBuffer));
  if (!ptr || w <= 0 || h <= 0 || stride < w) return nullptr;
  DetectionInput in{ptr, w, h, stride};
  auto result = detectDocument(in);
  if (!result) return nullptr;
  jfloatArray arr = env->NewFloatArray(10);
  if (!arr) return nullptr;
  jfloat buf[10] = {
    result->corners[0].x, result->corners[0].y,
    result->corners[1].x, result->corners[1].y,
    result->corners[2].x, result->corners[2].y,
    result->corners[3].x, result->corners[3].y,
    result->coverageRatio, result->tiltDegrees,
  };
  env->SetFloatArrayRegion(arr, 0, 10, buf);
  return arr;
}

}  // extern "C"
