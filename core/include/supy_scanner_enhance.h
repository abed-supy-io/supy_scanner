// supy_scanner_enhance.h — public C ABI for the document image
// enhancement pipeline. Bound to from Android JNI and iOS Swift.
//
// JPEG IO stays in platform code (BitmapFactory on Android, UIImage /
// ImageIO on iOS); only raw RGBA8888 buffers cross this boundary. Mirrors
// the precedent of the YUV-luma decode surface in supy_scanner.h.
//
// Threading: synchronous, CPU-bound, reentrant. Callers must invoke it
// from a worker thread.
//
// Buffer ownership: the `rgba` pointer in the input must remain valid for
// the duration of the call only. The returned handle owns its output
// buffer and must be freed with `supy_core_enhance_free`.
#ifndef SUPY_SCANNER_ENHANCE_H_
#define SUPY_SCANNER_ENHANCE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define SUPY_ENHANCE_EXPORT __declspec(dllexport)
#else
#define SUPY_ENHANCE_EXPORT __attribute__((visibility("default")))
#endif

typedef enum {
  SUPY_ENHANCE_OFF      = 0,
  SUPY_ENHANCE_FAST     = 1,  // quality gate + tone
  SUPY_ENHANCE_BALANCED = 2,  // gate + illumination + tone + unsharp
  // gate + illumination + specular clamp + top-hat flatten + tone + CLAHE +
  // unsharp. The full dependency-free stack for dim/uneven captures.
  SUPY_ENHANCE_MAX      = 3,
} supy_enhance_mode_t;

// Applied-stage bitmask returned in the result.
#define SUPY_ENHANCE_STAGE_GATE         (1u << 0)
#define SUPY_ENHANCE_STAGE_ILLUMINATION (1u << 1)
#define SUPY_ENHANCE_STAGE_TONE         (1u << 2)
#define SUPY_ENHANCE_STAGE_UNSHARP      (1u << 3)
#define SUPY_ENHANCE_STAGE_SPECULAR     (1u << 4)
#define SUPY_ENHANCE_STAGE_TOPHAT       (1u << 5)
#define SUPY_ENHANCE_STAGE_CLAHE        (1u << 6)

// Quality verdict from the input gate.
typedef enum {
  SUPY_ENHANCE_VERDICT_OK       = 0,
  SUPY_ENHANCE_VERDICT_MARGINAL = 1,
  SUPY_ENHANCE_VERDICT_REJECT   = 2,
} supy_enhance_verdict_t;

typedef struct {
  // Input pixels. Straight (non-premultiplied) RGBA8888.
  const uint8_t* rgba;
  int32_t width;
  int32_t height;
  // Bytes between consecutive rows (>= width * 4).
  int32_t row_stride;
  supy_enhance_mode_t mode;
  // Optional override of the blur-rejection threshold. <= 0 uses default
  // (variance-of-Laplacian < 40 -> reject, < 120 -> marginal).
  float min_blur_score;
} supy_enhance_input_t;

typedef struct supy_enhance_result_s supy_enhance_result_t;

// Run the enhancement pipeline. Returns NULL on:
//   - NULL input,
//   - invalid buffer (rgba NULL, w/h <= 0, row_stride < w*4),
//   - allocation failure.
//
// A non-NULL handle whose `verdict == REJECT` means the input was too
// blurry to bother processing — `rgba` will be a pass-through copy of the
// input. Callers should re-prompt the user. `MARGINAL` runs the full
// pipeline but signals to the caller that quality is borderline.
//
// `OFF` produces a pass-through copy with `applied_stages == 0`; useful so
// callers can keep a single output path.
SUPY_ENHANCE_EXPORT supy_enhance_result_t* supy_core_enhance(
    const supy_enhance_input_t* input);

// Output pixels — same dimensions and stride as input. Owned by the
// handle; pointer is invalidated by `supy_core_enhance_free`.
SUPY_ENHANCE_EXPORT const uint8_t* supy_core_enhance_rgba(
    const supy_enhance_result_t* handle);

SUPY_ENHANCE_EXPORT int32_t supy_core_enhance_width(
    const supy_enhance_result_t* handle);
SUPY_ENHANCE_EXPORT int32_t supy_core_enhance_height(
    const supy_enhance_result_t* handle);
SUPY_ENHANCE_EXPORT int32_t supy_core_enhance_row_stride(
    const supy_enhance_result_t* handle);

// Bitmask of SUPY_ENHANCE_STAGE_* that actually ran.
SUPY_ENHANCE_EXPORT uint32_t supy_core_enhance_applied_stages(
    const supy_enhance_result_t* handle);

// Variance-of-Laplacian on the input luminance plane. 0 on NULL handle.
SUPY_ENHANCE_EXPORT float supy_core_enhance_quality_score(
    const supy_enhance_result_t* handle);

// One of supy_enhance_verdict_t. Returns SUPY_ENHANCE_VERDICT_REJECT on
// NULL handle so callers can treat NULL and reject identically.
SUPY_ENHANCE_EXPORT int32_t supy_core_enhance_verdict(
    const supy_enhance_result_t* handle);

// Wall-clock milliseconds spent inside `supy_core_enhance`.
SUPY_ENHANCE_EXPORT int32_t supy_core_enhance_processing_ms(
    const supy_enhance_result_t* handle);

// Safe to call with NULL.
SUPY_ENHANCE_EXPORT void supy_core_enhance_free(
    supy_enhance_result_t* handle);

// -----------------------------------------------------------------------------
// Lightweight per-page quality scorer.
//
// Separate entry point from the full enhance pipeline so callers can score a
// page without running illumination/tone/unsharp — used by the iOS document
// path where VisionKit already enhances and `enhanceMode == OFF` is the
// default, but a quality bucket still has to surface on the wire.
//
// Synchronous, CPU-bound, reentrant. Safe to call from any worker thread.

typedef struct {
  // Input pixels. Straight (non-premultiplied) RGBA8888.
  const uint8_t* rgba;
  int32_t width;
  int32_t height;
  // Bytes between consecutive rows (>= width * 4).
  int32_t row_stride;
} supy_score_input_t;

// 5-bucket quality grade. Order matches the Dart `SupyDocumentPageQuality` /
// Scanbot DocumentQuality (1..5) ordering.
typedef enum {
  SUPY_SCORE_BUCKET_VERY_POOR = 0,
  SUPY_SCORE_BUCKET_POOR      = 1,
  SUPY_SCORE_BUCKET_OK        = 2,
  SUPY_SCORE_BUCKET_GOOD      = 3,
  SUPY_SCORE_BUCKET_EXCELLENT = 4,
} supy_score_bucket_t;

typedef struct {
  // Raw variance-of-Laplacian on the luma plane. Typically in [0, ~1000].
  float blur_score;
  // Normalized 0..1 sharpness — clamp(blur_score / 600, 0, 1). Surfaced on
  // `SupyDocumentPage.qualityScore`.
  float quality_score;
  // One of supy_score_bucket_t.
  int32_t bucket;
} supy_score_result_t;

// Score a single page. Returns 0 on invalid input (any pointer NULL, w/h <= 0,
// row_stride < w*4) — caller must check before reading `out`. Returns 1 on
// success.
SUPY_ENHANCE_EXPORT int32_t supy_core_score_page(
    const supy_score_input_t* input, supy_score_result_t* out);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // SUPY_SCANNER_ENHANCE_H_
