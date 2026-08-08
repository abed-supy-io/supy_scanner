#include "temporal.h"

#include <algorithm>

namespace supy::scanner::barcode {

namespace {

// Branch-free median-of-three on bytes promoted to int. The classic
// `max(min(a,b), min(max(a,b), c))` formulation; std::min/std::max compile
// down to two cmov pairs on arm64/x86_64 without a branch.
inline uint8_t median3(uint8_t a, uint8_t b, uint8_t c) {
  const int ai = a, bi = b, ci = c;
  const int lo = std::min(ai, bi);
  const int hi = std::max(ai, bi);
  return static_cast<uint8_t>(std::max(lo, std::min(hi, ci)));
}

}  // namespace

bool temporalMedianLuma3(const uint8_t* frame0, const uint8_t* frame1,
                        const uint8_t* frame2, uint8_t* out,
                        int32_t width, int32_t height, int32_t row_stride) {
  if (frame0 == nullptr || frame1 == nullptr || frame2 == nullptr || out == nullptr) {
    return false;
  }
  if (width <= 0 || height <= 0 || row_stride < width) {
    return false;
  }
  // Trivial alias check — overlapping reads/writes would silently corrupt.
  // Kotlin/Swift bridges always allocate `out` separately so this catches
  // honest mistakes, not adversarial inputs.
  if (out == frame0 || out == frame1 || out == frame2) {
    return false;
  }

  for (int32_t y = 0; y < height; ++y) {
    const uint8_t* r0 = frame0 + static_cast<size_t>(y) * row_stride;
    const uint8_t* r1 = frame1 + static_cast<size_t>(y) * row_stride;
    const uint8_t* r2 = frame2 + static_cast<size_t>(y) * row_stride;
    uint8_t* dst      = out    + static_cast<size_t>(y) * row_stride;
    for (int32_t x = 0; x < width; ++x) {
      dst[x] = median3(r0[x], r1[x], r2[x]);
    }
  }
  return true;
}

}  // namespace supy::scanner::barcode
