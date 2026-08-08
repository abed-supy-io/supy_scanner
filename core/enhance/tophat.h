#pragma once

#include "buffer.h"

namespace supy::scanner::enhance {

// Morphological background flatten (black top-hat family) for dark-text-on-
// light-paper pages. Estimates the local paper white via a closing with a
// structuring element larger than the largest glyph, then lifts each pixel by
// the local "paper deficit" (kPaper - background) so uneven lighting flattens
// to a uniform bright page while text contrast is preserved. Applied as a luma
// gain to RGB (chroma scaled with luma); alpha untouched. Operates in-place.
//
// Complementary to `normalizeIllumination`: that stage corrects multiplicative
// vignetting via division; this corrects the residual additive offset with a
// large-SE top-hat. SE radius is ~5% of the short side, clamped to [12, 96].
SUPY_ENHANCE_STAGE_EXPORT void applyTopHatFlatten(RgbaView view);

}  // namespace supy::scanner::enhance
