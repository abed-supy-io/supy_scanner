// binarize.h — C++ implementation surface for the adaptive-binarization
// kernel. The C ABI (supy_scanner_binarize.h) is the consumer; see the
// rationale block there for the V1-S2-05 split.
#pragma once

#include <cstdint>

#include "supy_scanner_binarize.h"

namespace supy::scanner::barcode {

// Returns true on success; false on input validation failure or allocation
// error. In-place — `luma` is overwritten with 0/255 values.
bool binarizeLuma(
    std::uint8_t* luma,
    std::int32_t width,
    std::int32_t height,
    std::int32_t row_stride,
    supy_binarize_mode_t mode);

}  // namespace supy::scanner::barcode
