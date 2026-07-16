#ifndef SUPY_SCANNER_BARCODE_TEMPORAL_H_
#define SUPY_SCANNER_BARCODE_TEMPORAL_H_

#include <cstdint>

namespace supy::scanner::barcode {

// Per-pixel median of three luma planes. See supy_scanner_temporal.h for
// the public contract. Returns false on validation failure.
bool temporalMedianLuma3(
    const uint8_t* frame0,
    const uint8_t* frame1,
    const uint8_t* frame2,
    uint8_t* out,
    int32_t width, int32_t height, int32_t row_stride);

}  // namespace supy::scanner::barcode

#endif  // SUPY_SCANNER_BARCODE_TEMPORAL_H_
