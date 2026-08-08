#pragma once

#include "buffer.h"

namespace supy::scanner::enhance {

enum class Verdict : std::int32_t { kOk = 0, kMarginal = 1, kReject = 2 };

struct GateResult {
  float blurScore = 0.0f;  // variance-of-Laplacian on luma plane
  Verdict verdict = Verdict::kOk;
};

// Runs a variance-of-Laplacian blur estimate on the RGBA view's luma plane.
// `min_blur_score` <= 0 selects the default reject/marginal thresholds.
GateResult runQualityGate(const RgbaView& view, float min_blur_score);

}  // namespace supy::scanner::enhance
