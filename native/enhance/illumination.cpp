#include "illumination.h"

#include <algorithm>
#include <cstdint>
#include <vector>

#include "morphology.h"

namespace supy::scanner::enhance {

namespace {

// Auto-chosen SE radius: ~3% of the short side, clamped to [8, 64].
std::int32_t backgroundRadius(std::int32_t w, std::int32_t h) {
  const std::int32_t shortSide = std::min(w, h);
  return std::max(8, std::min(64, shortSide * 3 / 100));
}

// Extract the BT.601 luma plane (tightly packed w*h) from an RGBA view.
std::vector<std::uint8_t> extractLuma(const RgbaView& view) {
  const std::int32_t w = view.width;
  const std::int32_t h = view.height;
  std::vector<std::uint8_t> luma(static_cast<std::size_t>(w) * h);
  for (std::int32_t y = 0; y < h; ++y) {
    const std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    for (std::int32_t x = 0; x < w; ++x) {
      const std::uint8_t* p = row + x * 4;
      luma[y * w + x] = luma601(p[0], p[1], p[2]);
    }
  }
  return luma;
}

}  // namespace

void normalizeIllumination(RgbaView view) {
  const std::int32_t w = view.width;
  const std::int32_t h = view.height;
  if (w <= 4 || h <= 4) return;

  const std::int32_t r = backgroundRadius(w, h);

  std::vector<std::uint8_t> luma = extractLuma(view);

  // Closing => bright-background estimate (dark text filled in).
  std::vector<std::uint8_t> tmp(static_cast<std::size_t>(w) * h);
  close2D(luma.data(), tmp.data(), w, h, r);

  // Target mean of the background — pin to 220 (a "clean paper" luma).
  // Lower target would darken the page; we want backgrounds to flatten to
  // bright white-ish.
  constexpr float kTargetMean = 220.0f;

  // Avoid divide-by-zero with a small floor.
  for (std::int32_t y = 0; y < h; ++y) {
    std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    const std::uint8_t* bgRow = luma.data() + y * w;
    for (std::int32_t x = 0; x < w; ++x) {
      const float bg = static_cast<float>(bgRow[x]);
      const float scale = kTargetMean / std::max(bg, 8.0f);
      std::uint8_t* p = row + x * 4;
      p[0] = clampByteF(static_cast<float>(p[0]) * scale);
      p[1] = clampByteF(static_cast<float>(p[1]) * scale);
      p[2] = clampByteF(static_cast<float>(p[2]) * scale);
      // alpha untouched
    }
  }
}

void suppressSpecular(RgbaView view) {
  const std::int32_t w = view.width;
  const std::int32_t h = view.height;
  if (w <= 4 || h <= 4) return;

  // A glare blob is a near-white region that an opening (which strips bright
  // spikes narrower than the SE) does not survive. The excess of the luma over
  // its opening is therefore the specular component; we cap that excess so
  // hotspots fall back toward the local diffuse background while genuinely
  // bright paper (which the opening preserves) is left alone.
  const std::int32_t r = backgroundRadius(w, h);

  std::vector<std::uint8_t> luma = extractLuma(view);
  std::vector<std::uint8_t> opened = luma;  // operated on in place by open2D
  std::vector<std::uint8_t> tmp(static_cast<std::size_t>(w) * h);
  open2D(opened.data(), tmp.data(), w, h, r);

  // Only touch pixels that are both blown-out and well above their diffuse
  // neighbourhood; allow a small headroom of excess so edges stay crisp.
  constexpr int kHotLuma = 235;      // below this we never treat it as glare
  constexpr int kMaxExcess = 24;     // permitted luma above the local diffuse

  for (std::int32_t y = 0; y < h; ++y) {
    std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    const std::uint8_t* lRow = luma.data() + y * w;
    const std::uint8_t* oRow = opened.data() + y * w;
    for (std::int32_t x = 0; x < w; ++x) {
      const int l = lRow[x];
      const int diffuse = oRow[x];
      const int excess = l - diffuse;
      if (l < kHotLuma || excess <= kMaxExcess) continue;
      const int targetLuma = diffuse + kMaxExcess;
      const float gain = static_cast<float>(targetLuma) / static_cast<float>(std::max(l, 1));
      std::uint8_t* p = row + x * 4;
      p[0] = clampByteF(static_cast<float>(p[0]) * gain);
      p[1] = clampByteF(static_cast<float>(p[1]) * gain);
      p[2] = clampByteF(static_cast<float>(p[2]) * gain);
      // alpha untouched
    }
  }
}

}  // namespace supy::scanner::enhance
