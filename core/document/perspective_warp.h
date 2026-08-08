// perspective_warp.h — OpenCV-free perspective rectification of a detected
// document quad into a flat, axis-aligned page.
//
// Shared by both platforms so Android and iOS produce identical geometry.
// JPEG IO stays in platform code; only raw RGBA8888 buffers cross this
// surface (mirrors enhance/). No network, no exceptions in the warp path.
//
// Threading: synchronous, CPU-bound, reentrant. Call from a worker thread.
#pragma once
#include <array>
#include <cstdint>
#include <optional>
#include <vector>

#include "document_edge_detector.h"  // supy::scanner::document::Point

namespace supy::scanner::document {

// Row-major 3x3 homography. Maps homogeneous (x, y, 1) -> (x', y', w').
struct Mat3 {
    std::array<float, 9> m;  // [m0 m1 m2; m3 m4 m5; m6 m7 m8]
};

struct WarpInput {
    const uint8_t* rgba;  // straight (non-premultiplied) RGBA8888
    int width;
    int height;
    int rowStride;  // bytes per row (>= width * 4)
    // Source quad corners in INPUT-IMAGE PIXEL space, TL, TR, BR, BL order
    // (callers scale normalized detector quads by width/height first).
    std::array<Point, 4> srcCorners;
};

struct WarpResult {
    std::vector<uint8_t> rgba;  // packed (rowStride == width * 4)
    int width = 0;
    int height = 0;
    int rowStride = 0;
};

#if defined(_WIN32)
#  define SUPY_WARP_EXPORT __declspec(dllexport)
#else
#  define SUPY_WARP_EXPORT __attribute__((visibility("default")))
#endif

// Solve the 8-DOF homography from 4 point correspondences mapping the
// destination rectangle corners (0,0),(dstW,0),(dstW,dstH),(0,dstH) onto
// `src` (TL, TR, BR, BL). The result maps DESTINATION -> SOURCE so callers
// can inverse-sample. Returns nullopt if the system is degenerate (collinear
// or coincident corners).
SUPY_WARP_EXPORT std::optional<Mat3> computeHomography(
    const std::array<Point, 4>& src, float dstW, float dstH);

// Derive the output rectangle size from the quad's edge lengths: width is the
// longer of the two horizontal edges, height the longer of the two vertical
// edges. The longest side is clamped to `maxLongSide` (aspect preserved) to
// bound memory; both dimensions are floored at 1.
SUPY_WARP_EXPORT void rectifiedSize(
    const std::array<Point, 4>& srcPx, int maxLongSide, int* outW, int* outH);

// Rectify the quad into a flat page via inverse-map + bilinear sampling.
// Output size is derived via rectifiedSize() with `maxLongSide`. Returns
// nullopt on invalid input (null/short buffer, non-positive dims, degenerate
// quad). Pixels sampled outside the source are left transparent-black.
SUPY_WARP_EXPORT std::optional<WarpResult> warpToRect(
    const WarpInput& in, int maxLongSide);

}  // namespace supy::scanner::document
