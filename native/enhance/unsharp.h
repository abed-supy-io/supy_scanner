#pragma once

#include "buffer.h"

namespace supy::scanner::enhance {

// Unsharp mask: out = clamp(in + amount * (in - blur(in))).
// 5-tap separable Gaussian (sigma ~= 1.5), amount = 0.4. Operates per
// channel on RGB; alpha is left alone.
SUPY_ENHANCE_STAGE_EXPORT void applyUnsharpMask(RgbaView view);

}  // namespace supy::scanner::enhance
