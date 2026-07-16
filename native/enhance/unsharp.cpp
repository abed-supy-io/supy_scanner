#include "unsharp.h"

#include <array>
#include <cstdint>
#include <vector>

namespace supy::scanner::enhance {

namespace {

// 5-tap Gaussian, sigma ~= 1.5 -> normalised kernel {1, 4, 6, 4, 1} / 16.
constexpr int kKernel[5] = {1, 4, 6, 4, 1};
constexpr int kKernelSum = 16;
constexpr float kAmount = 0.4f;

inline int reflect(int i, int n) {
  if (i < 0) return -i;
  if (i >= n) return 2 * n - i - 2;
  return i;
}

void blurPlane(const std::uint8_t* in, std::uint8_t* out, std::int32_t w, std::int32_t h) {
  std::vector<std::uint8_t> tmp(static_cast<std::size_t>(w) * h);

  // Horizontal pass: in -> tmp.
  for (std::int32_t y = 0; y < h; ++y) {
    const std::uint8_t* row = in + y * w;
    std::uint8_t* outRow = tmp.data() + y * w;
    for (std::int32_t x = 0; x < w; ++x) {
      int acc = 0;
      for (int k = -2; k <= 2; ++k) {
        const int sx = reflect(x + k, w);
        acc += row[sx] * kKernel[k + 2];
      }
      outRow[x] = static_cast<std::uint8_t>(acc / kKernelSum);
    }
  }
  // Vertical pass: tmp -> out.
  for (std::int32_t x = 0; x < w; ++x) {
    for (std::int32_t y = 0; y < h; ++y) {
      int acc = 0;
      for (int k = -2; k <= 2; ++k) {
        const int sy = reflect(y + k, h);
        acc += tmp[sy * w + x] * kKernel[k + 2];
      }
      out[y * w + x] = static_cast<std::uint8_t>(acc / kKernelSum);
    }
  }
}

}  // namespace

void applyUnsharpMask(RgbaView view) {
  const std::int32_t w = view.width;
  const std::int32_t h = view.height;
  if (w < 3 || h < 3) return;

  // Extract per-channel planes (R, G, B). Alpha left untouched.
  std::vector<std::uint8_t> plane(static_cast<std::size_t>(w) * h);
  std::vector<std::uint8_t> blurred(static_cast<std::size_t>(w) * h);

  for (int ch = 0; ch < 3; ++ch) {
    for (std::int32_t y = 0; y < h; ++y) {
      const std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
      std::uint8_t* p = plane.data() + y * w;
      for (std::int32_t x = 0; x < w; ++x) {
        p[x] = row[x * 4 + ch];
      }
    }
    blurPlane(plane.data(), blurred.data(), w, h);

    for (std::int32_t y = 0; y < h; ++y) {
      std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
      const std::uint8_t* src = plane.data() + y * w;
      const std::uint8_t* blr = blurred.data() + y * w;
      for (std::int32_t x = 0; x < w; ++x) {
        const float v = static_cast<float>(src[x]) +
                        kAmount * (static_cast<float>(src[x]) - static_cast<float>(blr[x]));
        row[x * 4 + ch] = clampByteF(v);
      }
    }
  }
}

}  // namespace supy::scanner::enhance
