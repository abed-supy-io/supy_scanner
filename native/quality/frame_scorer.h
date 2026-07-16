// frame_scorer.h — pure-C++ per-frame luma quality scorer.
//
// Phase FQS (Frame Quality Score). The iOS `DocumentDetector` used to compute
// `meanLuma` + variance-of-Laplacian (`blurScore`) over the Y plane in Swift,
// and Android does the same in Kotlin. Both are now thin wrappers around this
// function — single source of truth, identical numbers on both platforms, so
// the C++ `document_guidance_classifier` sees the same metric stream
// regardless of host.
//
// Algorithm contract (must match the Swift impl bit-for-bit on the same
// pixel buffer — pinned by `frame_scorer_test.cpp`):
//   1. Crop to the central 60% of the frame.
//   2. Stride-sample so the long edge of the sampled grid is ~96 px.
//   3. Mean luma = arithmetic mean of all sampled bytes.
//   4. 3×3 (4-neighbour) Laplacian over the *interior* of the sampled grid.
//   5. blurScore = variance of the Laplacian = E[l²] − E[l]², clamped to 0.
//
// No allocations on the steady-state path beyond a single stack-bounded
// sample buffer. No I/O, no exceptions.
#pragma once

#include <cstdint>

namespace supy::scanner::quality {

struct LumaMetrics {
  // Arithmetic mean of sampled Y values, 0..255.
  double mean_luma = 0.0;
  // Variance-of-Laplacian over the downsampled grid. Higher = sharper.
  // 0 on degenerate input (null buffer, sub-3×3 sample grid, etc.).
  double blur_score = 0.0;
};

#if defined(_WIN32)
#  define SUPY_QUALITY_EXPORT __declspec(dllexport)
#else
#  define SUPY_QUALITY_EXPORT __attribute__((visibility("default")))
#endif

// Computes mean luma + variance-of-Laplacian over a center-crop downsample
// of the Y plane. `luma` is a packed 8-bit luminance buffer, top-left origin.
// `row_stride` is bytes per row (>= width). Returns {0, 0} on degenerate
// input — never throws, never allocates the host's heap.
SUPY_QUALITY_EXPORT LumaMetrics
compute_luma_metrics(const uint8_t* luma, int width, int height, int row_stride);

}  // namespace supy::scanner::quality
