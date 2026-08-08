// Sauvola / Wolf-Jolion adaptive binarization, integral-image based.
//
// Window radius is derived from min(width, height) so it scales with the
// crop. The integral image of Y and Y² lets us evaluate
// mean / stddev over any rectangular window in O(1) per pixel. V1-S2-05.2
// will swap this for a Halide AOT-generated kernel behind the same C ABI.

#include "binarize.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <vector>

#if SUPY_HAVE_HALIDE_SAUVOLA
#include "HalideRuntime.h"
#include "sauvola_2d.h"  // emitted by the Halide AOT generator at build time
#endif

namespace supy::scanner::barcode {

namespace {

constexpr float kSauvolaK = 0.34f;
constexpr float kSauvolaR = 128.0f;
constexpr float kWolfK    = 0.34f;

// Window radius: ~1/16 of the short edge, clamped to [5, 25] so the total
// window stays in 11..51 px (matches the QA-validated range from the
// design doc). For very small crops the radius collapses naturally.
inline std::int32_t windowRadius(std::int32_t w, std::int32_t h) {
  const std::int32_t shortEdge = std::min(w, h);
  std::int32_t r = shortEdge / 16;
  if (r < 5) r = 5;
  if (r > 25) r = 25;
  if (r >= shortEdge / 2) r = std::max(1, shortEdge / 2 - 1);
  return r;
}

// Builds integral images of Y and Y² into `sum` / `sum_sq`. Both arrays
// have dimensions (W+1) × (H+1) with a leading row/col of zeros so window
// sums collapse to four lookups without bounds checks.
void buildIntegrals(
    const std::uint8_t* luma, std::int32_t w, std::int32_t h, std::int32_t row_stride,
    std::vector<std::int64_t>& sum, std::vector<std::int64_t>& sum_sq) {
  const std::int32_t sw = w + 1;
  // First row already zero from vector init.
  for (std::int32_t y = 0; y < h; ++y) {
    const std::uint8_t* src = luma + static_cast<std::size_t>(y) * row_stride;
    const std::int32_t rowOff  = (y + 1) * sw;
    const std::int32_t prevOff = y * sw;
    std::int64_t rowAcc   = 0;
    std::int64_t rowAccSq = 0;
    // Leading column is zero.
    sum[rowOff]    = 0;
    sum_sq[rowOff] = 0;
    for (std::int32_t x = 0; x < w; ++x) {
      const std::int64_t v = src[x];
      rowAcc   += v;
      rowAccSq += v * v;
      sum[rowOff + x + 1]    = sum[prevOff + x + 1]    + rowAcc;
      sum_sq[rowOff + x + 1] = sum_sq[prevOff + x + 1] + rowAccSq;
    }
  }
}

// Sums a window rect [x0,x1] × [y0,y1] (inclusive) from the integral image.
inline std::int64_t windowSum(const std::vector<std::int64_t>& integ,
                              std::int32_t sw,
                              std::int32_t x0, std::int32_t y0,
                              std::int32_t x1, std::int32_t y1) {
  // integ is indexed by (x+1, y+1), so the inclusive box translates to
  //   A=(x0, y0), B=(x1+1, y0), C=(x0, y1+1), D=(x1+1, y1+1).
  const std::int32_t a = (y0)         * sw + (x0);
  const std::int32_t b = (y0)         * sw + (x1 + 1);
  const std::int32_t c = (y1 + 1)     * sw + (x0);
  const std::int32_t d = (y1 + 1)     * sw + (x1 + 1);
  return integ[d] - integ[b] - integ[c] + integ[a];
}

}  // namespace

#if SUPY_HAVE_HALIDE_SAUVOLA
namespace {

// Bridge into the AOT-generated kernel. Builds a halide_buffer_t over the
// caller's luma allocation and invokes it in-place — Halide tolerates
// src==dst for element-wise output as long as no neighborhood is read
// after the final store; Sauvola 2D satisfies this because the threshold
// is fully memoized before the select.
bool runHalideSauvola2d(std::uint8_t* luma, std::int32_t w, std::int32_t h,
                        std::int32_t row_stride, std::int32_t radius) {
  halide_buffer_t buf{};
  halide_dimension_t dims[2];
  dims[0] = {0, w, 1};
  dims[1] = {0, h, row_stride};
  buf.dim = dims;
  buf.dimensions = 2;
  buf.type = halide_type_t(halide_type_uint, 8);
  buf.host = luma;

  const int rc = ::sauvola_2d(&buf, radius, kSauvolaK, kSauvolaR, &buf);
  return rc == 0;
}

}  // namespace
#endif  // SUPY_HAVE_HALIDE_SAUVOLA

bool binarizeLuma(std::uint8_t* luma, std::int32_t w, std::int32_t h,
                  std::int32_t row_stride, supy_binarize_mode_t mode) {
  if (luma == nullptr || w <= 0 || h <= 0 || row_stride < w) return false;

#if SUPY_HAVE_HALIDE_SAUVOLA
  if (mode == SUPY_BINARIZE_SAUVOLA_2D) {
    return runHalideSauvola2d(luma, w, h, row_stride, windowRadius(w, h));
  }
#endif

  const std::int32_t r  = windowRadius(w, h);
  const std::int32_t sw = w + 1;
  const std::int32_t sh = h + 1;
  const std::size_t  n  = static_cast<std::size_t>(sw) * sh;

  std::vector<std::int64_t> sum;
  std::vector<std::int64_t> sum_sq;
  try {
    sum.assign(n, 0);
    sum_sq.assign(n, 0);
  } catch (const std::bad_alloc&) {
    return false;
  }

  buildIntegrals(luma, w, h, row_stride, sum, sum_sq);

  // For Wolf-Jolion we need image-wide min(Y) and max(stddev). Sauvola
  // doesn't, but the cost of one extra pass is negligible vs the
  // per-pixel windowed work below.
  std::uint8_t globalMin = 255;
  if (mode == SUPY_BINARIZE_WOLF_JOLION_1D) {
    for (std::int32_t y = 0; y < h; ++y) {
      const std::uint8_t* src = luma + static_cast<std::size_t>(y) * row_stride;
      for (std::int32_t x = 0; x < w; ++x) {
        if (src[x] < globalMin) globalMin = src[x];
      }
    }
  }

  // First windowed pass (Wolf-Jolion only): find max-stddev across the image
  // so we can normalize the threshold. Sauvola skips this entirely.
  float maxStd = 0.0f;
  if (mode == SUPY_BINARIZE_WOLF_JOLION_1D) {
    for (std::int32_t y = 0; y < h; ++y) {
      const std::int32_t y0 = std::max(0, y - r);
      const std::int32_t y1 = std::min(h - 1, y + r);
      for (std::int32_t x = 0; x < w; ++x) {
        const std::int32_t x0 = std::max(0, x - r);
        const std::int32_t x1 = std::min(w - 1, x + r);
        const std::int64_t count = static_cast<std::int64_t>(x1 - x0 + 1) *
                                   static_cast<std::int64_t>(y1 - y0 + 1);
        const std::int64_t s  = windowSum(sum,    sw, x0, y0, x1, y1);
        const std::int64_t s2 = windowSum(sum_sq, sw, x0, y0, x1, y1);
        const float mean = static_cast<float>(s) / static_cast<float>(count);
        const float var  = static_cast<float>(s2) / static_cast<float>(count) - mean * mean;
        const float stdev = var > 0.0f ? std::sqrt(var) : 0.0f;
        if (stdev > maxStd) maxStd = stdev;
      }
    }
    if (maxStd <= 0.0f) maxStd = 1.0f;  // avoid div-by-zero on flat crops
  }

  // Second pass: compute per-pixel threshold + write back in place.
  // Safe to write into `luma` here because the integral images have
  // already captured the original values.
  for (std::int32_t y = 0; y < h; ++y) {
    const std::int32_t y0 = std::max(0, y - r);
    const std::int32_t y1 = std::min(h - 1, y + r);
    std::uint8_t* dst = luma + static_cast<std::size_t>(y) * row_stride;
    for (std::int32_t x = 0; x < w; ++x) {
      const std::int32_t x0 = std::max(0, x - r);
      const std::int32_t x1 = std::min(w - 1, x + r);
      const std::int64_t count = static_cast<std::int64_t>(x1 - x0 + 1) *
                                 static_cast<std::int64_t>(y1 - y0 + 1);
      const std::int64_t s  = windowSum(sum,    sw, x0, y0, x1, y1);
      const std::int64_t s2 = windowSum(sum_sq, sw, x0, y0, x1, y1);
      const float mean  = static_cast<float>(s) / static_cast<float>(count);
      const float var   = static_cast<float>(s2) / static_cast<float>(count) - mean * mean;
      const float stdev = var > 0.0f ? std::sqrt(var) : 0.0f;

      float t;
      switch (mode) {
        case SUPY_BINARIZE_WOLF_JOLION_1D: {
          // Wolf-Jolion: T = (1-k)·mean + k·min + k·(stdev/maxStd)·(mean − min)
          const float gm = static_cast<float>(globalMin);
          t = (1.0f - kWolfK) * mean + kWolfK * gm
              + kWolfK * (stdev / maxStd) * (mean - gm);
          break;
        }
        case SUPY_BINARIZE_SAUVOLA_2D:
        default: {
          // Sauvola: T = m · (1 + k·((stdev/R) − 1))
          t = mean * (1.0f + kSauvolaK * ((stdev / kSauvolaR) - 1.0f));
          break;
        }
      }
      // Cap into [0, 255] so float→uint8 doesn't wrap on degenerate windows.
      if (t < 0.0f) t = 0.0f;
      else if (t > 255.0f) t = 255.0f;
      // Read the *original* pixel from the integral image's source row —
      // but we still have it in dst because we haven't overwritten this
      // position yet on this row (writes go strictly left-to-right and
      // depend only on the integral image, never on neighbouring outputs).
      const std::uint8_t pixel = dst[x];
      dst[x] = static_cast<std::uint8_t>(pixel >= t ? 255 : 0);
    }
  }
  return true;
}

}  // namespace supy::scanner::barcode
