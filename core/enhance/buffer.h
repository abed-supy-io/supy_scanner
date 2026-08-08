// Internal RGBA8888 buffer view shared by the enhance stages.
// Not part of the public ABI.
#pragma once

#include <algorithm>
#include <cstdint>
#include <vector>

// The core lib builds with -fvisibility=hidden, which hides the internal
// enhance-stage functions from the host test binary that links the shared lib.
// Tag the stage entry points so the unit tests can call them directly. No
// effect on the public C ABI (already tagged in supy_scanner_enhance.h).
#if defined(_WIN32)
#  define SUPY_ENHANCE_STAGE_EXPORT __declspec(dllexport)
#else
#  define SUPY_ENHANCE_STAGE_EXPORT __attribute__((visibility("default")))
#endif

namespace supy::scanner::enhance {

struct RgbaView {
  uint8_t* data = nullptr;     // non-owning; tightly packed (row_stride == width*4)
  std::int32_t width = 0;
  std::int32_t height = 0;
  std::int32_t row_stride = 0; // bytes per row (== width*4 for owned buffers)
};

// Owned packed RGBA buffer. row_stride == width*4 by construction.
struct OwnedRgba {
  std::vector<std::uint8_t> bytes;
  std::int32_t width = 0;
  std::int32_t height = 0;

  RgbaView view() {
    return RgbaView{bytes.data(), width, height, width * 4};
  }
};

// Copy a (possibly padded) source RGBA buffer into a packed OwnedRgba.
inline OwnedRgba packCopy(const std::uint8_t* src, std::int32_t w, std::int32_t h,
                          std::int32_t src_stride) {
  OwnedRgba out;
  out.width = w;
  out.height = h;
  out.bytes.resize(static_cast<std::size_t>(w) * static_cast<std::size_t>(h) * 4);
  const std::int32_t packed = w * 4;
  for (std::int32_t y = 0; y < h; ++y) {
    const std::uint8_t* s = src + static_cast<std::size_t>(y) * static_cast<std::size_t>(src_stride);
    std::uint8_t* d = out.bytes.data() + static_cast<std::size_t>(y) * static_cast<std::size_t>(packed);
    std::copy(s, s + packed, d);
  }
  return out;
}

inline std::uint8_t clampByte(int v) {
  return static_cast<std::uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
}

inline std::uint8_t clampByteF(float v) {
  if (v <= 0.0f) return 0;
  if (v >= 255.0f) return 255;
  return static_cast<std::uint8_t>(v + 0.5f);
}

// BT.601 luma. Used by the quality gate and as the input plane for tone shaping.
inline std::uint8_t luma601(std::uint8_t r, std::uint8_t g, std::uint8_t b) {
  // 0.299, 0.587, 0.114 in Q8.
  const int y = (77 * r + 150 * g + 29 * b + 128) >> 8;
  return static_cast<std::uint8_t>(y);
}

}  // namespace supy::scanner::enhance
