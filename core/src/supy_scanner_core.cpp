#include "supy_scanner.h"

#include <cstring>
#include <new>
#include <string>
#include <vector>

#include "../barcode/barcode_decoder.h"
#include "../barcode/binarize.h"
#include "../barcode/datamatrix_locator.h"
#include "../barcode/temporal.h"
#include "../document/perspective_warp.h"
#include "supy_scanner_binarize.h"
#include "supy_scanner_temporal.h"

namespace {

constexpr const char* kSupyCoreVersion = "1.2.0-dev.1";

}  // namespace

// Opaque handle definition — kept here so callers never see the C++ vector.
struct supy_core_decode_result_s {
  std::vector<supy::scanner::barcode::DecodedBarcode> items;
};

struct supy_core_locate_result_s {
  std::vector<supy::scanner::barcode::LocatedRegion> items;
};

// Owns the rectified RGBA buffer until the caller frees the handle — mirrors
// the enhance-result pattern so pixel data never crosses dart:ffi.
struct supy_warp_result_s {
  std::vector<uint8_t> rgba;
  int32_t width = 0;
  int32_t height = 0;
  int32_t row_stride = 0;
};

extern "C" {

const char* supy_core_version(void) {
  return kSupyCoreVersion;
}

int supy_core_abi_version(void) {
  return SUPY_CORE_ABI_VERSION;
}

int supy_core_has_zxing(void) {
  return supy::scanner::barcode::hasZxing() ? 1 : 0;
}

supy_core_decode_result_t* supy_core_decode(const supy_core_decode_input_t* input) {
  if (input == nullptr) return nullptr;
  if (!supy::scanner::barcode::hasZxing()) return nullptr;

  supy::scanner::barcode::DecodeInput cpp_in{};
  cpp_in.luma       = input->luma;
  cpp_in.width      = input->width;
  cpp_in.height     = input->height;
  cpp_in.row_stride = input->row_stride;
  cpp_in.formats    = input->formats;
  cpp_in.try_harder = input->try_harder != 0;
  cpp_in.try_rotate = input->try_rotate != 0;

  // Validate at the ABI boundary so callers get NULL (not an empty handle)
  // for invalid inputs — mirrors the documented contract on the C ABI.
  if (cpp_in.luma == nullptr || cpp_in.width <= 0 || cpp_in.height <= 0 ||
      cpp_in.row_stride < cpp_in.width) {
    return nullptr;
  }

  auto items = supy::scanner::barcode::decode(cpp_in);

  auto* handle = new (std::nothrow) supy_core_decode_result_s{};
  if (handle == nullptr) return nullptr;
  handle->items = std::move(items);
  return handle;
}

int32_t supy_core_decode_count(const supy_core_decode_result_t* handle) {
  if (handle == nullptr) return 0;
  return static_cast<int32_t>(handle->items.size());
}

const char* supy_core_decode_text(const supy_core_decode_result_t* handle, int32_t index) {
  if (handle == nullptr) return nullptr;
  if (index < 0 || static_cast<size_t>(index) >= handle->items.size()) return nullptr;
  return handle->items[index].text.c_str();
}

uint32_t supy_core_decode_format(const supy_core_decode_result_t* handle, int32_t index) {
  if (handle == nullptr) return SUPY_FORMAT_NONE;
  if (index < 0 || static_cast<size_t>(index) >= handle->items.size()) return SUPY_FORMAT_NONE;
  return handle->items[index].format;
}

int32_t supy_core_decode_corners(const supy_core_decode_result_t* handle, int32_t index, float* out_xy8) {
  if (handle == nullptr || out_xy8 == nullptr) return 0;
  if (index < 0 || static_cast<size_t>(index) >= handle->items.size()) return 0;
  const auto& corners = handle->items[index].corners;
  std::memcpy(out_xy8, corners.data(), corners.size() * sizeof(float));
  return 1;
}

void supy_core_decode_results_free(supy_core_decode_result_t* handle) {
  delete handle;
}

// ---------------------------------------------------------------------------
// Data Matrix locator (V1-S2-04)
// ---------------------------------------------------------------------------

int supy_core_has_libdmtx(void) {
  return supy::scanner::barcode::hasLibdmtx() ? 1 : 0;
}

supy_core_locate_result_t* supy_core_locate_datamatrix(
    const supy_core_locate_input_t* input) {
  if (input == nullptr) return nullptr;
  if (!supy::scanner::barcode::hasLibdmtx()) return nullptr;

  if (input->luma == nullptr || input->width <= 0 || input->height <= 0 ||
      input->row_stride < input->width) {
    return nullptr;
  }

  supy::scanner::barcode::LocateInput cpp_in{};
  cpp_in.luma        = input->luma;
  cpp_in.width       = input->width;
  cpp_in.height      = input->height;
  cpp_in.row_stride  = input->row_stride;
  cpp_in.max_regions = input->max_regions;
  cpp_in.timeout_ms  = input->timeout_ms;

  auto items = supy::scanner::barcode::locate(cpp_in);

  auto* handle = new (std::nothrow) supy_core_locate_result_s{};
  if (handle == nullptr) return nullptr;
  handle->items = std::move(items);
  return handle;
}

int32_t supy_core_locate_count(const supy_core_locate_result_t* handle) {
  if (handle == nullptr) return 0;
  return static_cast<int32_t>(handle->items.size());
}

int32_t supy_core_locate_corners(
    const supy_core_locate_result_t* handle, int32_t index, float* out_xy8) {
  if (handle == nullptr || out_xy8 == nullptr) return 0;
  if (index < 0 || static_cast<size_t>(index) >= handle->items.size()) return 0;
  const auto& corners = handle->items[index].corners;
  std::memcpy(out_xy8, corners.data(), corners.size() * sizeof(float));
  return 1;
}

void supy_core_locate_results_free(supy_core_locate_result_t* handle) {
  delete handle;
}

// ---------------------------------------------------------------------------
// Adaptive binarization (V1-S2-05.1)
// ---------------------------------------------------------------------------

int supy_core_binarize_luma(uint8_t* luma, int32_t width, int32_t height,
                            int32_t row_stride, supy_binarize_mode_t mode) {
  return supy::scanner::barcode::binarizeLuma(luma, width, height, row_stride, mode)
      ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Temporal median-of-3 luma fusion (V1-S2-06.1)
// ---------------------------------------------------------------------------

int supy_core_temporal_median_luma(
    const uint8_t* frame0, const uint8_t* frame1, const uint8_t* frame2,
    uint8_t* out, int32_t width, int32_t height, int32_t row_stride) {
  return supy::scanner::barcode::temporalMedianLuma3(
             frame0, frame1, frame2, out, width, height, row_stride)
      ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Perspective warp (V1-S6-02 / Sprint 4)
// ---------------------------------------------------------------------------

supy_warp_result_t* supy_core_warp(const supy_warp_input_t* input) {
  if (input == nullptr) return nullptr;

  namespace doc = supy::scanner::document;
  doc::WarpInput in{};
  in.rgba = input->rgba;
  in.width = input->width;
  in.height = input->height;
  in.rowStride = input->row_stride;
  // src_corners is interleaved x,y in TL,TR,BR,BL order.
  for (int i = 0; i < 4; ++i) {
    in.srcCorners[i].x = input->src_corners[2 * i];
    in.srcCorners[i].y = input->src_corners[2 * i + 1];
  }

  auto warped = doc::warpToRect(in, input->max_long_side);
  if (!warped) return nullptr;

  auto* handle = new (std::nothrow) supy_warp_result_s{};
  if (handle == nullptr) return nullptr;
  handle->rgba = std::move(warped->rgba);
  handle->width = warped->width;
  handle->height = warped->height;
  handle->row_stride = warped->rowStride;
  return handle;
}

const uint8_t* supy_core_warp_rgba(const supy_warp_result_t* handle) {
  return handle == nullptr ? nullptr : handle->rgba.data();
}

int32_t supy_core_warp_width(const supy_warp_result_t* handle) {
  return handle == nullptr ? 0 : handle->width;
}

int32_t supy_core_warp_height(const supy_warp_result_t* handle) {
  return handle == nullptr ? 0 : handle->height;
}

int32_t supy_core_warp_row_stride(const supy_warp_result_t* handle) {
  return handle == nullptr ? 0 : handle->row_stride;
}

void supy_core_warp_free(supy_warp_result_t* handle) {
  delete handle;
}

}  // extern "C"
