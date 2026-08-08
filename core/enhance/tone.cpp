#include "tone.h"

#include <array>
#include <cmath>

namespace supy::scanner::enhance {

namespace {

constexpr float kGamma = 1.20f;
// Sigmoid steepness; ~3 gives a gentle S without harsh clipping.
constexpr float kSigmoidK = 3.0f;

std::array<std::uint8_t, 256> buildLut() {
  std::array<std::uint8_t, 256> lut{};
  // Sigmoid normalisation so the curve maps 0->0 and 255->255 exactly.
  const float s0 = 1.0f / (1.0f + std::exp(kSigmoidK * 0.5f));
  const float s1 = 1.0f / (1.0f + std::exp(-kSigmoidK * 0.5f));
  const float denom = s1 - s0;
  for (int i = 0; i < 256; ++i) {
    const float n = static_cast<float>(i) / 255.0f;
    const float gammaCorrected = std::pow(n, 1.0f / kGamma);
    const float t = gammaCorrected - 0.5f;
    const float sig = 1.0f / (1.0f + std::exp(-kSigmoidK * t));
    const float mapped = (sig - s0) / denom;
    int v = static_cast<int>(mapped * 255.0f + 0.5f);
    if (v < 0) v = 0;
    if (v > 255) v = 255;
    lut[i] = static_cast<std::uint8_t>(v);
  }
  return lut;
}

}  // namespace

void applyToneCurve(RgbaView view) {
  static const std::array<std::uint8_t, 256> lut = buildLut();
  for (std::int32_t y = 0; y < view.height; ++y) {
    std::uint8_t* row = view.data + static_cast<std::size_t>(y) * view.row_stride;
    for (std::int32_t x = 0; x < view.width; ++x) {
      std::uint8_t* p = row + x * 4;
      p[0] = lut[p[0]];
      p[1] = lut[p[1]];
      p[2] = lut[p[2]];
    }
  }
}

}  // namespace supy::scanner::enhance
