#include "frame_scorer.h"

#include <algorithm>
#include <cstdint>
#include <vector>

namespace supy::scanner::quality {

namespace {

constexpr double kCropFraction = 0.6;
constexpr int kTargetLongEdge = 96;

}  // namespace

LumaMetrics
compute_luma_metrics(const uint8_t* luma, int width, int height, int row_stride) {
  LumaMetrics out;
  if (luma == nullptr || width <= 0 || height <= 0 || row_stride < width) {
    return out;
  }

  const int crop_w = static_cast<int>(static_cast<double>(width) * kCropFraction);
  const int crop_h = static_cast<int>(static_cast<double>(height) * kCropFraction);
  if (crop_w <= 0 || crop_h <= 0) {
    return out;
  }
  const int x_offset = (width - crop_w) / 2;
  const int y_offset = (height - crop_h) / 2;
  const int long_edge = std::max(crop_w, crop_h);
  const int stride_step = std::max(1, long_edge / kTargetLongEdge);

  // Mirrors the Swift `samples: [Int16]` accumulator. Single allocation,
  // upper-bounded by (kTargetLongEdge + 1)^2 ≈ 9.4k samples — fits a stack
  // buffer if we want, but std::vector keeps the math obviously correct.
  std::vector<std::int16_t> samples;
  samples.reserve(static_cast<std::size_t>(
      (crop_h / stride_step + 1) * (crop_w / stride_step + 1)));

  std::int64_t luma_sum = 0;
  std::int64_t luma_count = 0;
  int sampled_cols = 0;
  int row_count = 0;

  for (int y = y_offset; y < y_offset + crop_h; y += stride_step) {
    const uint8_t* row = luma + static_cast<std::ptrdiff_t>(y) * row_stride;
    int col_count = 0;
    for (int x = x_offset; x < x_offset + crop_w; x += stride_step) {
      const int v = static_cast<int>(row[x]);
      luma_sum += v;
      ++luma_count;
      samples.push_back(static_cast<std::int16_t>(v));
      ++col_count;
    }
    if (row_count == 0) sampled_cols = col_count;
    ++row_count;
  }

  if (luma_count <= 0 || sampled_cols <= 2 ||
      static_cast<int>(samples.size()) < sampled_cols * 3) {
    return out;
  }

  out.mean_luma =
      static_cast<double>(luma_sum) / static_cast<double>(luma_count);

  const int rows_sampled = static_cast<int>(samples.size()) / sampled_cols;
  double laplacian_sum = 0.0;
  double laplacian_sq_sum = 0.0;
  std::int64_t laplacian_n = 0;
  for (int ry = 1; ry < rows_sampled - 1; ++ry) {
    for (int rx = 1; rx < sampled_cols - 1; ++rx) {
      const int i = ry * sampled_cols + rx;
      const int center = samples[i];
      const int up = samples[i - sampled_cols];
      const int down = samples[i + sampled_cols];
      const int left = samples[i - 1];
      const int right = samples[i + 1];
      const int l = (4 * center) - up - down - left - right;
      laplacian_sum += static_cast<double>(l);
      laplacian_sq_sum += static_cast<double>(l) * static_cast<double>(l);
      ++laplacian_n;
    }
  }
  if (laplacian_n <= 0) {
    return out;  // mean_luma already set; blur_score stays 0.
  }
  const double mean =
      laplacian_sum / static_cast<double>(laplacian_n);
  const double variance =
      (laplacian_sq_sum / static_cast<double>(laplacian_n)) - (mean * mean);
  out.blur_score = std::max(0.0, variance);
  return out;
}

}  // namespace supy::scanner::quality
