// JNI bridge for io.supy.scanner.nativecore.SupyNativeCore.
//
// Sprint 1 (v1.1 plan): version probe.
// Sprint 2 (V1-S2-03a): zxing-cpp barcode decode wire-through.

#include <jni.h>
#include <cstdint>
#include <cstring>
#include "supy_scanner_binarize.h"
#include "supy_scanner_core.h"
#include "supy_scanner_enhance.h"
#include "supy_scanner_temporal.h"
#include "document/document_edge_detector.h"
#include "document/document_guidance_classifier.h"

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

JNIEXPORT jint JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeHasZxing(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(supy_core_has_zxing());
}

// Decodes a luma frame and returns a packed result:
//   Object[3] = { String[N] texts, int[N] formats, float[8*N] corners }
// Returns null when:
//   - the buffer can't be addressed,
//   - the underlying decode returns NULL (no zxing, invalid input, OOM),
//   - the result is empty AND there's nothing useful to surface — callers
//     treat null the same as "no detections".
JNIEXPORT jobjectArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeDecodeBarcodes(
    JNIEnv* env, jclass /*clazz*/,
    jobject yBuffer, jint width, jint height, jint rowStride,
    jint formats, jint tryHarder, jint tryRotate) noexcept {
  try {
    auto* ptr = static_cast<uint8_t*>(env->GetDirectBufferAddress(yBuffer));
    if (!ptr || width <= 0 || height <= 0 || rowStride < width || rowStride > 65536) {
      return nullptr;
    }
    supy_core_decode_input_t in{};
    in.luma       = ptr;
    in.width      = width;
    in.height     = height;
    in.row_stride = rowStride;
    in.formats    = static_cast<uint32_t>(formats);
    in.try_harder = tryHarder;
    in.try_rotate = tryRotate;

    auto* handle = supy_core_decode(&in);
    if (!handle) return nullptr;

    const jint count = supy_core_decode_count(handle);
    jclass stringClass = env->FindClass("java/lang/String");
    jclass objectClass = env->FindClass("java/lang/Object");
    if (!stringClass || !objectClass) {
      supy_core_decode_results_free(handle);
      return nullptr;
    }

    jobjectArray texts = env->NewObjectArray(count, stringClass, nullptr);
    jintArray fmtArr   = env->NewIntArray(count);
    jfloatArray cornersArr = env->NewFloatArray(count * 8);
    if (!texts || !fmtArr || !cornersArr) {
      supy_core_decode_results_free(handle);
      return nullptr;
    }

    for (jint i = 0; i < count; ++i) {
      const char* utf = supy_core_decode_text(handle, i);
      if (utf) {
        jstring s = env->NewStringUTF(utf);
        env->SetObjectArrayElement(texts, i, s);
        env->DeleteLocalRef(s);
      }
      jint fmtBit = static_cast<jint>(supy_core_decode_format(handle, i));
      env->SetIntArrayRegion(fmtArr, i, 1, &fmtBit);

      jfloat xy[8] = {};
      if (supy_core_decode_corners(handle, i, xy) == 1) {
        env->SetFloatArrayRegion(cornersArr, i * 8, 8, xy);
      }
    }

    supy_core_decode_results_free(handle);

    jobjectArray out = env->NewObjectArray(3, objectClass, nullptr);
    if (!out) return nullptr;
    env->SetObjectArrayElement(out, 0, texts);
    env->SetObjectArrayElement(out, 1, fmtArr);
    env->SetObjectArrayElement(out, 2, cornersArr);
    return out;
  } catch (...) {
    return nullptr;
  }
}

JNIEXPORT jint JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeHasLibdmtx(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return static_cast<jint>(supy_core_has_libdmtx());
}

// Locates Data Matrix regions in a Y-plane direct ByteBuffer. Returns a flat
// float[] of length 8*N (TL,TR,BR,BL per region in input-image pixel space).
// Returns null when the locator isn't linked, input is invalid, or no regions
// were found (callers treat null and length==0 the same — "no DM in frame").
JNIEXPORT jfloatArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeLocateDatamatrix(
    JNIEnv* env, jclass /*clazz*/,
    jobject yBuffer, jint width, jint height, jint rowStride,
    jint maxRegions, jint timeoutMs) noexcept {
  try {
    auto* ptr = static_cast<uint8_t*>(env->GetDirectBufferAddress(yBuffer));
    if (!ptr || width <= 0 || height <= 0 || rowStride < width || rowStride > 65536) {
      return nullptr;
    }
    supy_core_locate_input_t in{};
    in.luma        = ptr;
    in.width       = width;
    in.height      = height;
    in.row_stride  = rowStride;
    in.max_regions = maxRegions;
    in.timeout_ms  = timeoutMs;

    auto* handle = supy_core_locate_datamatrix(&in);
    if (!handle) return nullptr;

    const jint count = supy_core_locate_count(handle);
    if (count <= 0) {
      supy_core_locate_results_free(handle);
      return env->NewFloatArray(0);
    }

    jfloatArray out = env->NewFloatArray(count * 8);
    if (!out) {
      supy_core_locate_results_free(handle);
      return nullptr;
    }
    for (jint i = 0; i < count; ++i) {
      jfloat xy[8] = {};
      if (supy_core_locate_corners(handle, i, xy) == 1) {
        env->SetFloatArrayRegion(out, i * 8, 8, xy);
      }
    }
    supy_core_locate_results_free(handle);
    return out;
  } catch (...) {
    return nullptr;
  }
}

JNIEXPORT jfloatArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeDetectQuad(
    JNIEnv* env, jclass /*clazz*/, jobject yBuffer, jint w, jint h, jint stride) noexcept {
  try {
    auto* ptr = static_cast<uint8_t*>(env->GetDirectBufferAddress(yBuffer));
    if (!ptr || w <= 0 || h <= 0 || stride < w || stride > 65536) return nullptr;
    supy::scanner::document::DetectionInput in{ptr, w, h, stride};
    auto result = supy::scanner::document::detectDocument(in);
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
  } catch (...) {
    return nullptr;
  }
}

// Enhances an in-place RGBA8888 direct ByteBuffer.
// Returns null on failure; otherwise returns int[4]:
//   [0] appliedStages bitmask, [1] verdict, [2] processingMs,
//   [3] quality score (raw float bits — caller decodes via Float.intBitsToFloat).
JNIEXPORT jintArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeEnhanceRgba(
    JNIEnv* env, jclass /*clazz*/,
    jobject rgbaBuffer, jint width, jint height, jint rowStride,
    jint mode, jfloat minBlurScore) noexcept {
  try {
    auto* ptr = static_cast<uint8_t*>(env->GetDirectBufferAddress(rgbaBuffer));
    if (!ptr || width <= 0 || height <= 0 || rowStride < width * 4) return nullptr;

    supy_enhance_input_t in{};
    in.rgba       = ptr;
    in.width      = width;
    in.height     = height;
    in.row_stride = rowStride;
    in.mode       = static_cast<supy_enhance_mode_t>(mode);
    in.min_blur_score = minBlurScore;

    auto* handle = supy_core_enhance(&in);
    if (!handle) return nullptr;

    // Copy the (packed) enhanced bytes back into the caller's possibly-padded
    // buffer row-by-row so the original Bitmap stride is preserved.
    const uint8_t* outRgba = supy_core_enhance_rgba(handle);
    const int32_t outStride = supy_core_enhance_row_stride(handle);
    for (int32_t y = 0; y < height; ++y) {
      std::memcpy(ptr + static_cast<size_t>(y) * rowStride,
                  outRgba + static_cast<size_t>(y) * outStride,
                  static_cast<size_t>(width) * 4);
    }

    const jint applied = static_cast<jint>(supy_core_enhance_applied_stages(handle));
    const jint verdict = supy_core_enhance_verdict(handle);
    const jint ms = supy_core_enhance_processing_ms(handle);
    const float score = supy_core_enhance_quality_score(handle);
    jint scoreBits;
    std::memcpy(&scoreBits, &score, sizeof(jint));

    supy_core_enhance_free(handle);

    jintArray out = env->NewIntArray(4);
    if (!out) return nullptr;
    jint values[4] = {applied, verdict, ms, scoreBits};
    env->SetIntArrayRegion(out, 0, 4, values);
    return out;
  } catch (...) {
    return nullptr;
  }
}

// Scores a single page from an RGBA8888 direct ByteBuffer. Returns null on
// invalid input; otherwise float[3]: [blurScore, qualityScore(0..1), bucket].
// Buffer is NOT mutated.
JNIEXPORT jfloatArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeScorePage(
    JNIEnv* env, jclass /*clazz*/,
    jobject rgbaBuffer, jint width, jint height, jint rowStride) noexcept {
  try {
    auto* ptr = static_cast<uint8_t*>(env->GetDirectBufferAddress(rgbaBuffer));
    if (!ptr || width <= 0 || height <= 0 || rowStride < width * 4) return nullptr;

    supy_score_input_t in{};
    in.rgba       = ptr;
    in.width      = width;
    in.height     = height;
    in.row_stride = rowStride;

    supy_score_result_t r{};
    if (supy_core_score_page(&in, &r) != 1) return nullptr;

    jfloatArray out = env->NewFloatArray(3);
    if (!out) return nullptr;
    jfloat values[3] = {r.blur_score, r.quality_score, static_cast<jfloat>(r.bucket)};
    env->SetFloatArrayRegion(out, 0, 3, values);
    return out;
  } catch (...) {
    return nullptr;
  }
}

// Adaptive binarization (V1-S2-05.1): in-place over a packed luma direct
// ByteBuffer (the libdmtx assist crop). Returns 1 on success, 0 on failure
// — caller is expected to fall through to a non-binarized decode pass on
// failure rather than treat it as fatal.
JNIEXPORT jint JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeBinarizeLumaCrop(
    JNIEnv* env, jclass /*clazz*/,
    jobject yBuffer, jint width, jint height, jint rowStride, jint mode) noexcept {
  try {
    auto* ptr = static_cast<uint8_t*>(env->GetDirectBufferAddress(yBuffer));
    if (!ptr || width <= 0 || height <= 0 || rowStride < width || rowStride > 65536) {
      return 0;
    }
    const auto m = static_cast<supy_binarize_mode_t>(mode);
    return supy_core_binarize_luma(ptr, width, height, rowStride, m);
  } catch (...) {
    return 0;
  }
}

// Temporal median-of-3 luma fusion (V1-S2-06.1). Inputs are three same-geometry
// packed-luma direct ByteBuffers; output is written into a fourth direct buffer
// that callers allocate (the alias check in the C ABI catches honest mistakes).
// Returns 1 on success, 0 on validation failure — callers fall back to a raw
// current-frame decode rather than treat 0 as fatal.
JNIEXPORT jint JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeTemporalMedianLuma3(
    JNIEnv* env, jclass /*clazz*/,
    jobject f0Buffer, jobject f1Buffer, jobject f2Buffer, jobject outBuffer,
    jint width, jint height, jint rowStride) noexcept {
  try {
    const auto* f0 = static_cast<const uint8_t*>(env->GetDirectBufferAddress(f0Buffer));
    const auto* f1 = static_cast<const uint8_t*>(env->GetDirectBufferAddress(f1Buffer));
    const auto* f2 = static_cast<const uint8_t*>(env->GetDirectBufferAddress(f2Buffer));
    auto* out      = static_cast<uint8_t*>(env->GetDirectBufferAddress(outBuffer));
    if (!f0 || !f1 || !f2 || !out) return 0;
    if (width <= 0 || height <= 0 || rowStride < width || rowStride > 65536) {
      return 0;
    }
    return supy_core_temporal_median_luma(f0, f1, f2, out, width, height, rowStride);
  } catch (...) {
    return 0;
  }
}

// CXD auto-snap (Phase 4) — opaque GuidanceState lifecycle. State must persist
// across frames; Kotlin owns the handle, JNI allocates/frees on demand.
JNIEXPORT jlong JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeGuidanceCreate(
    JNIEnv* /*env*/, jclass /*clazz*/) noexcept {
  try {
    return reinterpret_cast<jlong>(new supy::scanner::document::GuidanceState());
  } catch (...) {
    return 0;
  }
}

JNIEXPORT void JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeGuidanceDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) noexcept {
  if (handle == 0) return;
  delete reinterpret_cast<supy::scanner::document::GuidanceState*>(handle);
}

JNIEXPORT void JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeGuidanceReset(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) noexcept {
  if (handle == 0) return;
  reinterpret_cast<supy::scanner::document::GuidanceState*>(handle)->reset();
}

// Classifies a single frame. `config` is packed as a float[19] mirroring the
// C++ `GuidanceConfig` field order: 9 floats, 4 ints-as-floats, then 6 CQG
// values (maxGlareRatio, glareExitMargin, maxCornerVelocity,
// minPerCornerStability, edgeClipBlocking-as-0/1, maxCenterOffset).
// `perCornerStability` is a
// length-0 or length-4 array — length 0 signals "no per-corner signal this
// frame", matching the Dart contract (the classifier holds its prior
// occlusion judgement). Returns a float[2] of [stateOrdinal, liveQualityScore]
// on success, null on failure.
JNIEXPORT jfloatArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeGuidanceClassify(
    JNIEnv* env, jclass /*clazz*/,
    jlong handle,
    jboolean hasDocument, jboolean clipsEdge,
    jfloat coverage, jfloat tilt, jfloat luma, jfloat blur,
    jfloat stability, jfloat interior,
    jfloat glareRatio, jfloat cornerVelocity,
    jfloat centerOffsetX, jfloat centerOffsetY,
    jfloatArray perCornerArr,
    jfloatArray configArr) noexcept {
  try {
    if (handle == 0 || !configArr) return nullptr;
    if (env->GetArrayLength(configArr) < 19) return nullptr;
    jfloat cfg[19];
    env->GetFloatArrayRegion(configArr, 0, 19, cfg);

    supy::scanner::document::FrameMetrics raw{};
    raw.hasDocument      = hasDocument == JNI_TRUE;
    raw.clipsEdge        = clipsEdge == JNI_TRUE;
    raw.coverageRatio    = coverage;
    raw.tiltDegrees      = tilt;
    raw.meanLuma         = luma;
    raw.blurScore        = blur;
    raw.quadStability    = stability;
    raw.interiorVariance = interior;
    raw.glareRatio       = glareRatio;
    raw.cornerVelocity   = cornerVelocity;
    raw.centerOffsetX    = centerOffsetX;
    raw.centerOffsetY    = centerOffsetY;
    if (perCornerArr && env->GetArrayLength(perCornerArr) == 4) {
      jfloat pc[4];
      env->GetFloatArrayRegion(perCornerArr, 0, 4, pc);
      raw.perCornerStability = {pc[0], pc[1], pc[2], pc[3]};
      raw.hasPerCornerStability = true;
    } else {
      raw.hasPerCornerStability = false;
    }

    supy::scanner::document::GuidanceConfig config{};
    config.minCoverageRatio        = cfg[0];
    config.maxCoverageRatio        = cfg[1];
    config.maxTiltDegrees          = cfg[2];
    config.minMeanLuma             = cfg[3];
    config.minBlurScore            = cfg[4];
    config.readyStabilityFloor     = cfg[5];
    config.interiorVarianceFloor   = cfg[6];
    config.exitMargin              = cfg[7];
    config.smoothingAlpha          = cfg[8];
    config.readyStableFrames       = static_cast<int>(cfg[9]);
    config.holdSteadyFrames        = static_cast<int>(cfg[10]);
    config.lostDocumentGraceFrames = static_cast<int>(cfg[11]);
    config.minDwellFrames          = static_cast<int>(cfg[12]);
    config.maxGlareRatio           = cfg[13];
    config.glareExitMargin         = cfg[14];
    config.maxCornerVelocity       = cfg[15];
    config.minPerCornerStability   = cfg[16];
    config.edgeClipBlocking        = cfg[17] != 0.0f;
    config.maxCenterOffset         = cfg[18];

    auto* state = reinterpret_cast<supy::scanner::document::GuidanceState*>(handle);
    auto result = supy::scanner::document::classify(raw, config, *state, nullptr);

    jfloatArray out = env->NewFloatArray(2);
    if (!out) return nullptr;
    jfloat packed[2] = {
        static_cast<jfloat>(static_cast<int>(result)),
        state->liveQualityScore,
    };
    env->SetFloatArrayRegion(out, 0, 2, packed);
    return out;
  } catch (...) {
    return nullptr;
  }
}

// Perspective warp (V1-S6-02). Rectifies the document quad in a full-res RGBA8888
// direct ByteBuffer into a flat page. The output size is derived from the quad
// edge lengths, so it can't be returned in-place: the packed RGBA bytes come back
// as a byte[] and the [width, height] pair is written into the caller-provided
// outWh int[2]. `srcCorners` is float[8] interleaved x,y in TL,TR,BR,BL pixel
// space. Returns null on invalid input / degenerate quad — the caller then falls
// back to persisting the un-rectified still. Input buffer is NOT mutated.
JNIEXPORT jbyteArray JNICALL
Java_io_supy_scanner_nativecore_SupyNativeCore_nativeWarpPerspective(
    JNIEnv* env, jclass /*clazz*/,
    jobject rgbaBuffer, jint width, jint height, jint rowStride,
    jfloatArray srcCorners, jint maxLongSide, jintArray outWh) noexcept {
  try {
    auto* ptr = static_cast<const uint8_t*>(env->GetDirectBufferAddress(rgbaBuffer));
    if (!ptr || width <= 0 || height <= 0 || rowStride < width * 4) return nullptr;
    if (!srcCorners || env->GetArrayLength(srcCorners) != 8) return nullptr;
    if (!outWh || env->GetArrayLength(outWh) < 2) return nullptr;

    supy_warp_input_t in{};
    in.rgba = ptr;
    in.width = width;
    in.height = height;
    in.row_stride = rowStride;
    in.max_long_side = maxLongSide;
    env->GetFloatArrayRegion(srcCorners, 0, 8, in.src_corners);

    auto* handle = supy_core_warp(&in);
    if (!handle) return nullptr;

    const int32_t outW = supy_core_warp_width(handle);
    const int32_t outH = supy_core_warp_height(handle);
    const int32_t outStride = supy_core_warp_row_stride(handle);
    const uint8_t* outRgba = supy_core_warp_rgba(handle);
    if (!outRgba || outW <= 0 || outH <= 0) {
      supy_core_warp_free(handle);
      return nullptr;
    }

    // Packed (outStride == outW * 4) — copy straight into a Java byte[].
    const jsize byteCount = static_cast<jsize>(outW) * outH * 4;
    jbyteArray out = env->NewByteArray(byteCount);
    if (!out) {
      supy_core_warp_free(handle);
      return nullptr;
    }
    env->SetByteArrayRegion(
        out, 0, byteCount, reinterpret_cast<const jbyte*>(outRgba));

    jint wh[2] = {outW, outH};
    env->SetIntArrayRegion(outWh, 0, 2, wh);

    supy_core_warp_free(handle);
    (void)outStride;  // always outW*4 for warp output; asserted by the C++ tests.
    return out;
  } catch (...) {
    return nullptr;
  }
}

}  // extern "C"
