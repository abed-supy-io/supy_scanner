// datamatrix_locator.h — C++ wrapper around libdmtx region finding.
//
// libdmtx is used as a finder only — `locate()` returns the perspective
// corners of every detected Data Matrix region in pixel space. Decode is
// handled separately by the zxing-cpp path on the ROI crop; see the
// "Data Matrix locator" block in supy_scanner_core.h for the contract.
//
// Gating: when SUPY_WITH_LIBDMTX is undefined, `locate` is a no-op
// (returns an empty vector). This lets contributors who haven't enabled
// the libdmtx vendor flag keep a green build.
#pragma once

#include <array>
#include <cstdint>
#include <vector>

namespace supy::scanner::barcode {

struct LocateInput {
  const uint8_t* luma;
  std::int32_t width;
  std::int32_t height;
  std::int32_t row_stride;
  std::int32_t max_regions;
  std::int32_t timeout_ms;
};

struct LocatedRegion {
  // TL, TR, BR, BL in input-image pixel space. Same convention as
  // `DecodedBarcode::corners`.
  std::array<float, 8> corners;
};

// Returns true when this build linked libdmtx. Mirrors
// `supy_core_has_libdmtx()` on the C ABI.
bool hasLibdmtx();

// Synchronous CPU-bound region search. Empty vector on input-validation
// failure or "nothing found"; the C ABI layer distinguishes by returning
// NULL on validation failure.
std::vector<LocatedRegion> locate(const LocateInput& input);

}  // namespace supy::scanner::barcode
