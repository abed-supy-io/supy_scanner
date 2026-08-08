#include "clahe.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

namespace supy::scanner::enhance {

namespace {

// Contrast clip factor: clip bound = kClipFactor * (tilePixels / 256). Higher
// = more aggressive local contrast. 3.0 is a moderate, OCR-safe default.
constexpr float kClipFactor = 3.0f;

using Lut = std::array<std::uint8_t, 256>;

// Build the clipped-histogram-equalization LUT for one tile.
Lut tileLut(const std::array<int, 256>& hist, int tilePixels) {
  std::array<int, 256> h = hist;

  // Clip and accumulate the excess.
  const int clip = std::max(1, static_cast<int>(kClipFactor * tilePixels / 256.0f));
  long excess = 0;
  for (int i = 0; i < 256; ++i) {
    if (h[i] > clip) {
      excess += h[i] - clip;
      h[i] = clip;
    }
  }
  // Redistribute the excess uniformly, then sprinkle the remainder.
  const int incr = static_cast<int>(excess / 256);
  int remainder = static_cast<int>(excess - static_cast<long>(incr) * 256);
  for (int i = 0; i < 256; ++i) {
    h[i] += incr;
    if (remainder > 0) {
      h[i] += 1;
      --remainder;
    }
  }

  // CDF -> mapping. Total is preserved (== tilePixels) by the redistribution.
  Lut lut{};
  const float norm = tilePixels > 0 ? 255.0f / static_cast<float>(tilePixels) : 0.0f;
  long cdf = 0;
  for (int i = 0; i < 256; ++i) {
    cdf += h[i];
    int v = static_cast<int>(static_cast<float>(cdf) * norm + 0.5f);
    lut[i] = static_cast<std::uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
  }
  return lut;
}

}  // namespace

void applyClahe(RgbaView view) {
  const std::int32_t w = view.width;
  const std::int32_t h = view.height;
  if (w <= 16 || h <= 16) return;

  // Tile grid: aim for 8x8, but keep tiles at least ~16px so histograms have
  // enough samples. Degenerates gracefully toward a single global mapping.
  const int tilesX = std::max(1, std::min(8, static_cast<int>(w / 16)));
  const int tilesY = std::max(1, std::min(8, static_cast<int>(h / 16)));
  const float tileWf = static_cast<float>(w) / tilesX;
  const float tileHf = static_cast<float>(h) / tilesY;

  // Luma plane.
  std::vector<std::uint8_t> luma(static_cast<std::size_t>(w) * h);
  for (std::int32_t y = 0; y < h; ++y) {
    const std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    for (std::int32_t x = 0; x < w; ++x) {
      const std::uint8_t* p = row + x * 4;
      luma[y * w + x] = luma601(p[0], p[1], p[2]);
    }
  }

  // Per-tile histograms.
  std::vector<std::array<int, 256>> hists(static_cast<std::size_t>(tilesX) * tilesY);
  std::vector<int> counts(static_cast<std::size_t>(tilesX) * tilesY, 0);
  for (auto& hg : hists) hg.fill(0);
  for (std::int32_t y = 0; y < h; ++y) {
    const int ty = std::min(static_cast<int>(y / tileHf), tilesY - 1);
    const std::uint8_t* lRow = luma.data() + static_cast<std::size_t>(y) * w;
    for (std::int32_t x = 0; x < w; ++x) {
      const int tx = std::min(static_cast<int>(x / tileWf), tilesX - 1);
      const std::size_t t = static_cast<std::size_t>(ty) * tilesX + tx;
      hists[t][lRow[x]] += 1;
      counts[t] += 1;
    }
  }

  // Per-tile LUTs.
  std::vector<Lut> luts(static_cast<std::size_t>(tilesX) * tilesY);
  for (std::size_t t = 0; t < luts.size(); ++t) {
    luts[t] = tileLut(hists[t], counts[t]);
  }

  auto lutAt = [&](int tx, int ty) -> const Lut& {
    tx = std::max(0, std::min(tilesX - 1, tx));
    ty = std::max(0, std::min(tilesY - 1, ty));
    return luts[static_cast<std::size_t>(ty) * tilesX + tx];
  };

  // Apply with bilinear interpolation across the four nearest tile centres.
  for (std::int32_t y = 0; y < h; ++y) {
    const float gy = static_cast<float>(y) / tileHf - 0.5f;
    int ty0 = static_cast<int>(std::floor(gy));
    float fy = gy - static_cast<float>(ty0);
    if (ty0 < 0) { ty0 = 0; fy = 0.0f; }
    if (ty0 >= tilesY - 1) { ty0 = tilesY - 1; fy = 0.0f; }
    const int ty1 = ty0 + 1;

    std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    const std::uint8_t* lRow = luma.data() + static_cast<std::size_t>(y) * w;
    for (std::int32_t x = 0; x < w; ++x) {
      const float gx = static_cast<float>(x) / tileWf - 0.5f;
      int tx0 = static_cast<int>(std::floor(gx));
      float fx = gx - static_cast<float>(tx0);
      if (tx0 < 0) { tx0 = 0; fx = 0.0f; }
      if (tx0 >= tilesX - 1) { tx0 = tilesX - 1; fx = 0.0f; }
      const int tx1 = tx0 + 1;

      const int l = lRow[x];
      const float m00 = lutAt(tx0, ty0)[l];
      const float m10 = lutAt(tx1, ty0)[l];
      const float m01 = lutAt(tx0, ty1)[l];
      const float m11 = lutAt(tx1, ty1)[l];
      const float top = m00 + (m10 - m00) * fx;
      const float bot = m01 + (m11 - m01) * fx;
      const float newLuma = top + (bot - top) * fy;

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
