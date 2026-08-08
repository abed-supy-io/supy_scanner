#pragma once

#include <cstdint>

namespace supy::scanner::enhance {

// Separable grayscale morphology on an 8-bit plane (row-major, tightly packed
// width*height). O(n) per row/column via the monotonic-deque min/max trick;
// border handling is reflect-clamp. Shared by the illumination, top-hat and
// specular-clamp stages so they agree on the structuring element.
//
// All ops are in-place on `plane`; `tmp` is a caller-provided scratch buffer
// of the same size (width*height). Radius `r` is the SE half-width (square SE
// of side 2r+1); r <= 0 is a no-op.

// 2D dilation (square SE): plane := max over the (2r+1)^2 neighbourhood.
void dilate2D(std::uint8_t* plane, std::uint8_t* tmp,
              std::int32_t w, std::int32_t h, std::int32_t r);

// 2D erosion (square SE): plane := min over the (2r+1)^2 neighbourhood.
void erode2D(std::uint8_t* plane, std::uint8_t* tmp,
             std::int32_t w, std::int32_t h, std::int32_t r);

// Morphological closing = dilate then erode. Fills dark gaps narrower than the
// SE — estimates the bright (paper) background under dark text.
void close2D(std::uint8_t* plane, std::uint8_t* tmp,
             std::int32_t w, std::int32_t h, std::int32_t r);

// Morphological opening = erode then dilate. Removes bright spikes narrower
// than the SE — estimates the background with specular highlights stripped.
void open2D(std::uint8_t* plane, std::uint8_t* tmp,
            std::int32_t w, std::int32_t h, std::int32_t r);

}  // namespace supy::scanner::enhance
