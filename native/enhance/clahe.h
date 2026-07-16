#pragma once

#include "buffer.h"

namespace supy::scanner::enhance {

// Contrast-Limited Adaptive Histogram Equalization on the luma plane, applied
// as a gain to RGB (chroma scaled with luma); alpha untouched. Operates
// in-place on `view`.
//
// Hand-rolled, dependency-free: an 8x8 tile grid (auto-reduced for small
// images), per-tile clipped histogram with excess redistributed uniformly,
// CDF-derived per-tile mapping, and bilinear interpolation of the four nearest
// tile mappings per pixel to avoid block artefacts. Lifts local contrast on
// dim, low-contrast captures (faint 6pt line items under kitchen light) where
// the global tone curve can't.
SUPY_ENHANCE_STAGE_EXPORT void applyClahe(RgbaView view);

}  // namespace supy::scanner::enhance
