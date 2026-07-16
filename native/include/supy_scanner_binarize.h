// supy_scanner native core — adaptive binarization C ABI.
//
// V1-S2-05.1: Sauvola (2D) and Wolf-Jolion (1D-favoured) adaptive
// binarization, computed via integral-image sum + sum-of-squares so the
// per-pixel cost is O(1) regardless of window radius.
//
// V1-S2-05.2 will swap the body of `supy_core_binarize_luma` for a Halide
// AOT-generated kernel behind the same ABI. Callers stay untouched.
//
// Scope: today this is wired exclusively into the libdmtx ROI assist path
// (BatchBarcodeScannerActivity + SupyBarcodeScannerView). The crop comes in
// as packed luma (row_stride == width); the implementation tolerates a
// padded stride for forward compatibility.

#ifndef SUPY_SCANNER_BINARIZE_H_
#define SUPY_SCANNER_BINARIZE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define SUPY_BINARIZE_EXPORT __declspec(dllexport)
#else
#define SUPY_BINARIZE_EXPORT __attribute__((visibility("default")))
#endif

// Sauvola: 2D windowed adaptive threshold tuned for matrix codes
//   (Data Matrix, QR). Best when the foreground modules are small and
//   illumination drifts across the symbol.
//
// Wolf-Jolion: variant of Sauvola that normalizes against the image-wide
//   minimum + max-stddev. Better recall on 1D barcodes (Code128, EAN-13)
//   where the dark/light stripes are wider and Sauvola can over-threshold
//   the wide black bars. Reserved for the 1D assist path (V1-S2-06+).
typedef enum {
  SUPY_BINARIZE_SAUVOLA_2D       = 0,
  SUPY_BINARIZE_WOLF_JOLION_1D   = 1,
} supy_binarize_mode_t;

// In-place adaptive binarization on a luma plane.
//   luma         — non-null, mutated in place. Output is 0 (black) or 255
//                  (white) per pixel, same layout (width / row_stride) as
//                  the input.
//   width, height — pixel dimensions. Must be >= 1.
//   row_stride   — bytes between consecutive rows. Must be >= width.
//   mode         — see supy_binarize_mode_t.
// Returns 1 on success, 0 on input validation failure or allocation error.
// Reentrant; no globals; CPU-bound. Callers must invoke from a worker
// thread (camera analyzer, not the platform UI thread).
SUPY_BINARIZE_EXPORT int supy_core_binarize_luma(
    uint8_t* luma,
    int32_t width,
    int32_t height,
    int32_t row_stride,
    supy_binarize_mode_t mode);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // SUPY_SCANNER_BINARIZE_H_
