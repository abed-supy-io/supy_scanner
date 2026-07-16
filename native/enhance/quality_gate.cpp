#include "quality_gate.h"

#include <cstdlib>
#include <vector>

namespace supy::scanner::enhance {

namespace {

constexpr float kDefaultRejectThreshold = 40.0f;
constexpr float kDefaultMarginalThreshold = 120.0f;

// Variance of the 4-neighbour Laplacian (|N + S + E + W - 4·C|) on the luma
// plane. Standard sharpness proxy — same definition as
// document_guidance_classifier uses.
float varianceOfLaplacian(const RgbaView& view) {
  if (view.width < 3 || view.height < 3) return 0.0f;
  const std::int32_t w = view.width;
  const std::int32_t h = view.height;

  // Pre-extract luma into a contiguous plane so the Laplacian loop hits
  // cache predictably.
  std::vector<std::uint8_t> luma(static_cast<std::size_t>(w) * h);
  for (std::int32_t y = 0; y < h; ++y) {
    const std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    std::uint8_t* out = luma.data() + static_cast<std::size_t>(y) * w;
    for (std::int32_t x = 0; x < w; ++x) {
      const std::uint8_t* px = row + x * 4;
      out[x] = luma601(px[0], px[1], px[2]);
    }
  }

  // Pass 1: sum and count.
  double sum = 0.0;
  double sumSq = 0.0;
  std::int64_t count = 0;
  for (std::int32_t y = 1; y < h - 1; ++y) {
    const std::uint8_t* up   = luma.data() + (y - 1) * w;
    const std::uint8_t* cur  = luma.data() + y * w;
    const std::uint8_t* down = luma.data() + (y + 1) * w;
    for (std::int32_t x = 1; x < w - 1; ++x) {
      const int lap = static_cast<int>(up[x]) + static_cast<int>(down[x]) +
                      static_cast<int>(cur[x - 1]) + static_cast<int>(cur[x + 1]) -
                      4 * static_cast<int>(cur[x]);
      sum += lap;
      sumSq += static_cast<double>(lap) * lap;
      ++count;
    }
  }
  if (count == 0) return 0.0f;
  const double mean = sum / static_cast<double>(count);
  const double var = sumSq / static_cast<double>(count) - mean * mean;
  return var > 0.0 ? static_cast<float>(var) : 0.0f;
}

}  // namespace

GateResult runQualityGate(const RgbaView& view, float min_blur_score) {
  GateResult r{};
  r.blurScore = varianceOfLaplacian(view);

  const float rejectAt = min_blur_score > 0.0f ? min_blur_score : kDefaultRejectThreshold;
  const float marginalAt = min_blur_score > 0.0f
                               ? min_blur_score * (kDefaultMarginalThreshold / kDefaultRejectThreshold)
                               : kDefaultMarginalThreshold;
  if (r.blurScore < rejectAt) r.verdict = Verdict::kReject;
  else if (r.blurScore < marginalAt) r.verdict = Verdict::kMarginal;
  else r.verdict = Verdict::kOk;
  return r;
}

}  // namespace supy::scanner::enhance
