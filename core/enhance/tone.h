#pragma once

#include "buffer.h"

namespace supy::scanner::enhance {

// In-place gamma + gentle S-curve via a precomputed 256-entry LUT.
// Gamma 1.20 lifts midtones; S-curve adds perceived contrast without
// crushing extremes.
void applyToneCurve(RgbaView view);

}  // namespace supy::scanner::enhance
