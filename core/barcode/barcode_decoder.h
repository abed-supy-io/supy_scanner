// barcode_decoder.h — C++ wrapper around zxing-cpp `ReadBarcodes`.
//
// The public ABI (supy_scanner.h) is intentionally C-only so JNI,
// Swift, and dart:ffi can all bind to it. This header is the internal
// C++ layer that owns the zxing-cpp integration; only supy_scanner_core.cpp
// includes it. Keeping zxing-cpp's C++ types out of the public ABI means we
// can bump zxing-cpp versions without rippling type changes through every
// language binding.
//
// Gating: when SUPY_WITH_ZXING_CPP is undefined, `decode` is a no-op
// (returns an empty result). This lets the Sprint 1 build path stay green
// for contributors who haven't run tools/build_zxing_xcframework.sh / set
// the CMake flag.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace supy::scanner::barcode {

struct DecodeInput {
  const uint8_t* luma;
  std::int32_t width;
  std::int32_t height;
  std::int32_t row_stride;
  std::uint32_t formats;  // SUPY_FORMAT_* bitmask
  bool try_harder;
  bool try_rotate;
};

struct DecodedBarcode {
  std::string text;
  std::uint32_t format;  // single SUPY_FORMAT_* bit
  // TL, TR, BR, BL in input-image pixel space.
  std::array<float, 8> corners;
};

// Returns true when this build linked zxing-cpp. Mirrors
// `supy_core_has_zxing()` on the C ABI.
bool hasZxing();

// Synchronous CPU-bound decode. Empty vector on input-validation failure
// or "nothing found"; the caller cannot distinguish — that's intentional,
// because the camera loop treats both the same way. If you need to surface
// validation errors, do it at the C ABI layer by returning NULL.
std::vector<DecodedBarcode> decode(const DecodeInput& input);

}  // namespace supy::scanner::barcode
