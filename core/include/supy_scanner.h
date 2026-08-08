// supy_scanner native core — C ABI.
//
// Sprint 1 (v1.1 plan): version probe only.
// Sprint 2 (V1-S2-03): zxing-cpp decode surface (gated on SUPY_WITH_ZXING_CPP).
//
// The symbols here are the surface that Android JNI, iOS Swift, and dart:ffi
// all bind to.
//
// IMPORTANT: pixel buffers MUST NOT cross the dart:ffi boundary. Pixel data
// stays inside the native process: camera -> C++ core -> ML Kit / Vision /
// zxing-cpp. Only result structs (decoded payloads, doc page URIs) are
// allowed to traverse dart:ffi. The decode surface below is for use by the
// Android JNI bridge and the iOS Swift bridge, both of which run inside the
// same process as the camera capture.

#ifndef SUPY_SCANNER_CORE_H_
#define SUPY_SCANNER_CORE_H_

#include <stdint.h>

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

#define SUPY_CORE_ABI_VERSION 5

// ---------------------------------------------------------------------------
// Barcode decode (V1-S2-03)
// ---------------------------------------------------------------------------
//
// `supy_core_has_zxing()` returns 1 when the build linked zxing-cpp (CMake
// option SUPY_WITH_ZXING_CPP=ON). When 0, `supy_core_decode()` always returns
// NULL — callers MUST fall back to the platform decoder (ML Kit / Vision).
//
// Threading: decode is synchronous and CPU-bound. Callers must invoke it
// from a worker thread; never the platform UI thread. The implementation is
// reentrant — multiple threads may call `supy_core_decode` concurrently
// with independent input buffers.
//
// Buffer ownership: the `luma` pointer in the input struct must remain
// valid for the duration of the `supy_core_decode` call only. The returned
// `supy_core_decode_result_t*` owns its own storage and is independent of
// the input.

// Format bitmask — bit per zxing-cpp BarcodeFormat. The library translates
// to/from `ZXing::BarcodeFormat` in barcode/barcode_decoder.cpp. Adding a
// format here also requires touching docs/SYMBOLOGIES.md and both platform
// mappers (FormatMapper.kt + SymbologyMapper.swift). See CLAUDE.md.
#define SUPY_FORMAT_NONE              0u
#define SUPY_FORMAT_AZTEC             (1u << 0)
#define SUPY_FORMAT_CODABAR           (1u << 1)
#define SUPY_FORMAT_CODE_39           (1u << 2)
#define SUPY_FORMAT_CODE_93           (1u << 3)
#define SUPY_FORMAT_CODE_128          (1u << 4)
#define SUPY_FORMAT_DATA_MATRIX       (1u << 5)
#define SUPY_FORMAT_EAN_8             (1u << 6)
#define SUPY_FORMAT_EAN_13            (1u << 7)
#define SUPY_FORMAT_ITF               (1u << 8)
#define SUPY_FORMAT_PDF_417           (1u << 9)
#define SUPY_FORMAT_QR_CODE           (1u << 10)
#define SUPY_FORMAT_UPC_A             (1u << 11)
#define SUPY_FORMAT_UPC_E             (1u << 12)
#define SUPY_FORMAT_DATA_BAR          (1u << 13)
#define SUPY_FORMAT_DATA_BAR_EXPANDED (1u << 14)
#define SUPY_FORMAT_MICRO_QR          (1u << 15)
#define SUPY_FORMAT_RMQR              (1u << 16)
#define SUPY_FORMAT_MAXI_CODE         (1u << 17)
#define SUPY_FORMAT_ALL               0xFFFFFFFFu

typedef struct supy_core_decode_result_s supy_core_decode_result_t;

typedef struct {
  // Luminance plane (single byte per pixel). Must remain valid for the
  // lifetime of the supy_core_decode() call.
  const uint8_t* luma;
  int32_t width;
  int32_t height;
  // Bytes between consecutive rows (>= width). Cameras frequently pad rows.
  int32_t row_stride;
  // Bitmask of SUPY_FORMAT_*. Use SUPY_FORMAT_ALL to enable everything.
  // SUPY_FORMAT_NONE is treated as SUPY_FORMAT_ALL for forward compat —
  // callers that genuinely want zero formats should not call decode at all.
  uint32_t formats;
  // 1 = enable zxing-cpp "try harder" mode (slower, higher recall).
  int32_t try_harder;
  // 1 = also try 90/180/270deg rotations of the image. Independent of
  // try_harder; both can be set.
  int32_t try_rotate;
} supy_core_decode_input_t;

// Returns 1 if the build linked zxing-cpp, 0 otherwise. Safe to call from
// any thread, no allocation, O(1).
SUPY_CORE_EXPORT int supy_core_has_zxing(void);

// Runs zxing-cpp `ReadBarcodes` on the supplied luma frame. Returns an
// opaque handle the caller must free with `supy_core_decode_results_free`.
// Returns NULL if:
//   - `supy_core_has_zxing()` is 0 (build did not link zxing-cpp), or
//   - `input` is NULL or contains an invalid buffer (luma NULL, width or
//     height <= 0, row_stride < width), or
//   - allocation failed.
//
// A non-NULL handle with `supy_core_decode_count() == 0` means decode ran
// successfully but found nothing — this is the steady-state result for an
// empty viewfinder and is NOT an error.
SUPY_CORE_EXPORT supy_core_decode_result_t* supy_core_decode(
    const supy_core_decode_input_t* input);

// Number of decoded barcodes in the handle. 0 means "decode ran, nothing
// found" — see comment on supy_core_decode.
SUPY_CORE_EXPORT int32_t supy_core_decode_count(
    const supy_core_decode_result_t* handle);

// UTF-8 text payload of the result at `index`. Pointer is owned by the
// handle and stays valid until the handle is freed. Returns NULL on bounds
// error or NULL handle.
SUPY_CORE_EXPORT const char* supy_core_decode_text(
    const supy_core_decode_result_t* handle, int32_t index);

// Format of the result at `index` as a single SUPY_FORMAT_* bit. Returns
// SUPY_FORMAT_NONE on bounds error or NULL handle.
SUPY_CORE_EXPORT uint32_t supy_core_decode_format(
    const supy_core_decode_result_t* handle, int32_t index);

// Fills `out_xy8` (caller-owned, length 8) with the four detected corner
// coordinates in input-image pixel space, in TL,TR,BR,BL order:
//   [x0, y0, x1, y1, x2, y2, x3, y3]
// Returns 1 on success, 0 on bounds error / NULL handle / NULL out buffer.
SUPY_CORE_EXPORT int32_t supy_core_decode_corners(
    const supy_core_decode_result_t* handle, int32_t index, float* out_xy8);

// Frees a result handle. Safe to call with NULL.
SUPY_CORE_EXPORT void supy_core_decode_results_free(
    supy_core_decode_result_t* handle);

// ---------------------------------------------------------------------------
// Data Matrix locator (V1-S2-04)
// ---------------------------------------------------------------------------
//
// libdmtx is used as a *locator only* — it scans a luma frame for Data Matrix
// regions and returns the four perspective corners per region in pixel space.
// Actual payload decode still happens via zxing-cpp on the ROI crop (the
// caller is responsible for cropping and re-calling `supy_core_decode`).
// Rationale: zxing-cpp's own Data Matrix finder is conservative under
// motion/perspective; libdmtx's region search is the most permissive
// open-source DM locator and recovers symbols zxing-cpp misses on noisy
// backgrounds. Decode quality, however, is consistently better on zxing-cpp,
// hence the locator+decoder split.
//
// `supy_core_has_libdmtx()` returns 1 when the build linked libdmtx (CMake
// option SUPY_WITH_LIBDMTX=ON). When 0, `supy_core_locate_datamatrix` always
// returns NULL — callers MUST skip the assist hop and feed the full frame
// straight to `supy_core_decode`.
//
// Threading: locate is synchronous and CPU-bound. Each call constructs its
// own `DmtxDecode` so concurrent calls with independent input buffers are
// safe. Never call from the platform UI thread.

typedef struct supy_core_locate_result_s supy_core_locate_result_t;

typedef struct {
  // Luminance plane (single byte per pixel). Must remain valid for the
  // lifetime of the supy_core_locate_datamatrix() call.
  const uint8_t* luma;
  int32_t width;
  int32_t height;
  // Bytes between consecutive rows (>= width). libdmtx's image API takes
  // a `DmtxPropRowPadBytes` override; we forward `row_stride - width`.
  int32_t row_stride;
  // Maximum number of regions to return. Hard ceiling to keep the per-frame
  // wall-clock bounded — libdmtx will keep finding regions until timeout
  // otherwise. <= 0 is treated as 1.
  int32_t max_regions;
  // Timeout in milliseconds for the whole region search. <= 0 disables the
  // timeout (libdmtx will run until it has exhausted candidates). Cameras
  // should always pass a budget; suggested 30 ms for live preview.
  int32_t timeout_ms;
} supy_core_locate_input_t;

// Returns 1 if the build linked libdmtx, 0 otherwise. Safe to call from any
// thread, no allocation, O(1).
SUPY_CORE_EXPORT int supy_core_has_libdmtx(void);

// Scans the supplied luma frame for Data Matrix regions. Returns an opaque
// handle the caller must free with `supy_core_locate_results_free`. Returns
// NULL on the same conditions as `supy_core_decode` (build not linked,
// invalid input, allocation failure). A non-NULL handle with
// `supy_core_locate_count() == 0` means the search ran successfully and
// found no Data Matrix regions — the steady-state result for an empty
// viewfinder.
SUPY_CORE_EXPORT supy_core_locate_result_t* supy_core_locate_datamatrix(
    const supy_core_locate_input_t* input);

// Number of located regions. 0 means "locate ran, nothing found".
SUPY_CORE_EXPORT int32_t supy_core_locate_count(
    const supy_core_locate_result_t* handle);

// Fills `out_xy8` (caller-owned, length 8) with the four corner coordinates
// of the region at `index` in input-image pixel space. Order is TL,TR,BR,BL
// — same convention as `supy_core_decode_corners`. Returns 1 on success,
// 0 on bounds error / NULL handle / NULL out buffer.
SUPY_CORE_EXPORT int32_t supy_core_locate_corners(
    const supy_core_locate_result_t* handle, int32_t index, float* out_xy8);

// Frees a locate-result handle. Safe to call with NULL.
SUPY_CORE_EXPORT void supy_core_locate_results_free(
    supy_core_locate_result_t* handle);

// ---------------------------------------------------------------------------
// Perspective warp (V1-S6-02 / Sprint 4)
// ---------------------------------------------------------------------------
//
// Rectifies a detected document quad into a flat, axis-aligned page via a
// hand-rolled 8-DOF homography + bilinear inverse sampling — no OpenCV. Shared
// by Android (replaces the captureAndRectify stub) and, for parity, iOS.
//
// Pixel data stays native, per the boundary contract above: the input RGBA
// buffer is supplied by the platform JPEG decoder, the output is owned by the
// returned handle and re-encoded by the platform before any URI crosses
// dart:ffi.
//
// Threading: synchronous, CPU-bound, reentrant — call from a worker thread.

typedef struct supy_warp_result_s supy_warp_result_t;

typedef struct {
  // Straight (non-premultiplied) RGBA8888. Must remain valid for the call.
  const uint8_t* rgba;
  int32_t width;
  int32_t height;
  // Bytes between consecutive rows (>= width * 4).
  int32_t row_stride;
  // Source quad corners in INPUT-IMAGE PIXEL space, interleaved x,y in
  // TL,TR,BR,BL order: [x0,y0, x1,y1, x2,y2, x3,y3]. Callers scale a
  // normalized detector quad by width/height before passing it here.
  float src_corners[8];
  // Longest output side cap (aspect preserved). <= 0 means unbounded — the
  // output size is derived from the quad's edge lengths.
  int32_t max_long_side;
} supy_warp_input_t;

// Rectifies the quad. Returns an opaque handle the caller frees with
// `supy_core_warp_free`. Returns NULL on NULL input, invalid buffer (rgba
// NULL, w/h <= 0, row_stride < w*4), a degenerate quad, or allocation failure.
SUPY_CORE_EXPORT supy_warp_result_t* supy_core_warp(
    const supy_warp_input_t* input);

// Output pixels — packed (row_stride == width * 4). Owned by the handle;
// invalidated by `supy_core_warp_free`. NULL on NULL handle.
SUPY_CORE_EXPORT const uint8_t* supy_core_warp_rgba(
    const supy_warp_result_t* handle);
SUPY_CORE_EXPORT int32_t supy_core_warp_width(const supy_warp_result_t* handle);
SUPY_CORE_EXPORT int32_t supy_core_warp_height(const supy_warp_result_t* handle);
SUPY_CORE_EXPORT int32_t supy_core_warp_row_stride(
    const supy_warp_result_t* handle);

// Frees a warp-result handle. Safe to call with NULL.
SUPY_CORE_EXPORT void supy_core_warp_free(supy_warp_result_t* handle);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // SUPY_SCANNER_CORE_H_
