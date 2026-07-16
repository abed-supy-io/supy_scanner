#pragma once

#include "buffer.h"

namespace supy::scanner::enhance {

// Estimate the slowly-varying illumination field via separable morphological
// closing (1D dilate -> 1D erode along each axis) on the luma plane, then
// divide the source RGB by that field scaled to a target mean. Operates
// in-place on `view`.
//
// Kernel radius is auto-chosen as ~3% of min(w,h), clamped to [8, 64].
// O(n) per row/col via the standard monotonic-deque min/max trick.
void normalizeIllumination(RgbaView view);

// Specular/glare clamp. Estimates the local diffuse background via a
// morphological opening (which strips bright spikes narrower than the SE) and
// caps any pixel whose luma sits well above that diffuse level and is itself
// near-white — pulling blown-out highlights back toward the page while
// leaving genuinely bright paper untouched. Operates in-place on `view`.
// Same auto-chosen SE radius as `normalizeIllumination`.
SUPY_ENHANCE_STAGE_EXPORT void suppressSpecular(RgbaView view);

}  // namespace supy::scanner::enhance
