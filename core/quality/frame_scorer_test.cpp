// Host-side tests for the C++ frame quality scorer (Phase FQS).
//
// Pins the algorithm contract documented in `frame_scorer.h`:
//   - mean_luma is the arithmetic mean of sampled Y bytes (0..255).
//   - blur_score is variance-of-Laplacian, ≥ 0, monotonically higher for
//     sharper buffers.
//
// If you change either output here, the iOS / Android guidance classifier
// thresholds in `document_guidance_classifier.h` need re-tuning — these are
// the numbers that feed it. See `docs/QA.md` Phase FQS scenarios.

#include <gtest/gtest.h>

#include <cmath>
#include <cstdint>
#include <vector>

#include "frame_scorer.h"

namespace q = supy::scanner::quality;

namespace {

constexpr int kW = 320;
constexpr int kH = 240;

std::vector<uint8_t> uniformBuffer(uint8_t v) {
  return std::vector<uint8_t>(static_cast<std::size_t>(kW * kH), v);
}

// Vertical stripes 8px wide (0 / 255). Deliberately coarser than the
// scorer's internal subsampling stride (`stride_step` in frame_scorer.cpp,
// which is 2 for these dimensions): a 1px-period pattern aliases to a flat
// buffer under that decimation and scores a spurious zero. Eight-pixel
// stripes keep hard edges in the sampled grid, so this stays the sharpest
// fixture here — high variance-of-Laplacian.
std::vector<uint8_t> verticalEdges() {
  std::vector<uint8_t> b(static_cast<std::size_t>(kW * kH), 0);
  for (int y = 0; y < kH; ++y) {
    for (int x = 0; x < kW; ++x) {
      b[y * kW + x] = ((x / 8) & 1) ? 255 : 0;
    }
  }
  return b;
}

// Soft gradient — strictly between uniform and edges on sharpness.
std::vector<uint8_t> softGradient() {
  std::vector<uint8_t> b(static_cast<std::size_t>(kW * kH), 0);
  for (int y = 0; y < kH; ++y) {
    for (int x = 0; x < kW; ++x) {
      b[y * kW + x] = static_cast<uint8_t>((x * 255) / (kW - 1));
    }
  }
  return b;
}

}  // namespace

TEST(FrameScorer, NullBufferReturnsZeros) {
  const auto m = q::compute_luma_metrics(nullptr, kW, kH, kW);
  EXPECT_DOUBLE_EQ(m.mean_luma, 0.0);
  EXPECT_DOUBLE_EQ(m.blur_score, 0.0);
}

TEST(FrameScorer, BadDimensionsReturnZeros) {
  const auto buf = uniformBuffer(128);
  const auto m1 = q::compute_luma_metrics(buf.data(), 0, kH, kW);
  EXPECT_DOUBLE_EQ(m1.blur_score, 0.0);
  const auto m2 = q::compute_luma_metrics(buf.data(), kW, kH, kW - 1);
  EXPECT_DOUBLE_EQ(m2.blur_score, 0.0);
}

TEST(FrameScorer, UniformBufferHasMeanAndZeroBlur) {
  const auto buf = uniformBuffer(180);
  const auto m = q::compute_luma_metrics(buf.data(), kW, kH, kW);
  EXPECT_NEAR(m.mean_luma, 180.0, 0.5);
  EXPECT_DOUBLE_EQ(m.blur_score, 0.0);
}

TEST(FrameScorer, BlurScoreOrdersByContent) {
  const auto flat = uniformBuffer(128);
  const auto gradient = softGradient();
  const auto edges = verticalEdges();

  const auto m_flat = q::compute_luma_metrics(flat.data(), kW, kH, kW);
  const auto m_grad = q::compute_luma_metrics(gradient.data(), kW, kH, kW);
  const auto m_edge = q::compute_luma_metrics(edges.data(), kW, kH, kW);

  EXPECT_DOUBLE_EQ(m_flat.blur_score, 0.0);
  EXPECT_GT(m_edge.blur_score, m_grad.blur_score);
  EXPECT_GT(m_grad.blur_score, m_flat.blur_score);
}

TEST(FrameScorer, RowStridePaddingDoesNotShiftMean) {
  // Build a padded buffer (stride > width) and confirm scoring ignores
  // the padding bytes — same mean as the packed equivalent.
  const int stride = kW + 16;
  std::vector<uint8_t> packed(static_cast<std::size_t>(kW * kH));
  std::vector<uint8_t> padded(static_cast<std::size_t>(stride * kH), 0xFF);
  for (int y = 0; y < kH; ++y) {
    for (int x = 0; x < kW; ++x) {
      const uint8_t v = static_cast<uint8_t>((x + y) & 0xFF);
      packed[y * kW + x] = v;
      padded[y * stride + x] = v;
    }
  }
  const auto m_packed = q::compute_luma_metrics(packed.data(), kW, kH, kW);
  const auto m_padded = q::compute_luma_metrics(padded.data(), kW, kH, stride);
  EXPECT_NEAR(m_packed.mean_luma, m_padded.mean_luma, 0.001);
  EXPECT_NEAR(m_packed.blur_score, m_padded.blur_score, 0.001);
}
