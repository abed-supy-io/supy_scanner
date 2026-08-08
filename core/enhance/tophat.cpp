#include "tophat.h"

#include <algorithm>
#include <cstdint>
#include <vector>

#include "morphology.h"

namespace supy::scanner::enhance {

void applyTopHatFlatten(RgbaView view) {
  const std::int32_t w = view.width;
  const std::int32_t h = view.height;
  if (w <= 8 || h <= 8) return;

  // Large SE — must exceed the largest glyph so a closing fills text and
  // returns the paper background, not the ink.
  const std::int32_t shortSide = std::min(w, h);
  const std::int32_t r = std::max(12, std::min(96, shortSide * 5 / 100));

  // Luma plane.
  std::vector<std::uint8_t> luma(static_cast<std::size_t>(w) * h);
  for (std::int32_t y = 0; y < h; ++y) {
    const std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    for (std::int32_t x = 0; x < w; ++x) {
      const std::uint8_t* p = row + x * 4;
      luma[y * w + x] = luma601(p[0], p[1], p[2]);
    }
  }

  // Closing => paper-white background estimate (dark text filled in).
  std::vector<std::uint8_t> bg = luma;
  std::vector<std::uint8_t> tmp(static_cast<std::size_t>(w) * h);
  close2D(bg.data(), tmp.data(), w, h, r);

  // Lift each pixel by the local paper deficit. Cap the correction so a dark
  // border region (where the closing is itself dark) can't blow the page out.
  constexpr float kPaper = 245.0f;
  constexpr float kMaxLift = 80.0f;

  for (std::int32_t y = 0; y < h; ++y) {
    std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    const std::uint8_t* lRow = luma.data() + y * w;
    const std::uint8_t* bgRow = bg.data() + y * w;
    for (std::int32_t x = 0; x < w; ++x) {
      const float deficit = kPaper - static_cast<float>(bgRow[x]);
      if (deficit <= 0.0f) continue;  // background already at/above paper white
      const float lift = std::min(deficit, kMaxLift);
      const int l = lRow[x];
      const float newLuma = static_cast<float>(l) + lift;
      const float gain = newLuma / static_cast<float>(std::max(l, 1));
      std::uint8_t* p = row + x * 4;
      p[0] = clampByteF(static_cast<float>(p[0]) * gain);
      p[1] = clampByteF(static_cast<float>(p[1]) * gain);
      p[2] = clampByteF(static_cast<float>(p[2]) * gain);
      // alpha untouched
    }
  }
}

}  // namespace supy::scanner::enhance
