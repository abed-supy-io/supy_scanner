// Temporal luma fusion — V1-S2-06.1.
//
// The libdmtx assist path locates Data Matrix regions on a noisy live-preview
// frame. When the same region is matched across three consecutive frames
// (IoU-gated by the Kotlin/Swift caller), this kernel fuses the per-pixel
// median across the three crops to suppress per-frame shot noise before
// adaptive binarization (see supy_scanner_binarize.h) sees it.
//
// Median-of-three is preferred over mean because it discards single-frame
// outliers (specular flashes, sensor speckle) without softening edges.
//
// Threading: synchronous, CPU-bound, reentrant, no globals. Callers run from
// the analyzer thread. Input buffers must remain valid for the call duration;
// the kernel reads only — `out` is the sole writable buffer.

#ifndef SUPY_SCANNER_TEMPORAL_H_
#define SUPY_SCANNER_TEMPORAL_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define SUPY_TEMPORAL_EXPORT __declspec(dllexport)
#else
#define SUPY_TEMPORAL_EXPORT __attribute__((visibility("default")))
#endif

// Per-pixel median across three same-geometry luma crops.
//
// All four buffers MUST share width, height, and row_stride. `out` may not
// alias any of the input frames. Layout is packed-or-padded single-channel
// luma (row_stride >= width). Returns 1 on success, 0 on validation failure
// (NULL pointer, non-positive dimension, row_stride < width, or aliasing
// caught by trivial pointer equality with `out`).
SUPY_TEMPORAL_EXPORT int supy_core_temporal_median_luma(
    const uint8_t* frame0,
    const uint8_t* frame1,
    const uint8_t* frame2,
    uint8_t* out,
    int32_t width, int32_t height, int32_t row_stride);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // SUPY_SCANNER_TEMPORAL_H_
