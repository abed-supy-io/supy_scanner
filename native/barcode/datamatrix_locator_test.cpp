// Host-side tests for the libdmtx Data Matrix locator (V1-S2-04).
//
// Same two-layer coverage as barcode_decoder_test.cpp:
//   1. ABI contract — NULL handling, input validation, ownership lifecycle.
//      Pass regardless of SUPY_WITH_LIBDMTX.
//   2. Locate behavior — synthetic Data Matrix frames. Requires both
//      SUPY_WITH_LIBDMTX (the symbol under test) and SUPY_WITH_ZXING_CPP
//      (for the writer that synthesizes the test image).

#include <gtest/gtest.h>

#include <cstdint>
#include <cstring>
#include <vector>

#include "datamatrix_locator.h"
#include "supy_scanner_core.h"

#if defined(SUPY_WITH_ZXING_CPP)
#include "BitMatrix.h"
#include "MultiFormatWriter.h"
#endif

namespace {

std::vector<std::uint8_t> blankLuma(int width, int height, std::uint8_t fill = 0xFF) {
  return std::vector<std::uint8_t>(static_cast<size_t>(width) * height, fill);
}

#if defined(SUPY_WITH_ZXING_CPP)

struct LumaImage {
  std::vector<std::uint8_t> pixels;
  int width;
  int height;
};

LumaImage renderDataMatrix(const std::string& text, int target_w, int target_h,
                           int margin = 20) {
  ZXing::MultiFormatWriter writer(ZXing::BarcodeFormat::DataMatrix);
  writer.setMargin(margin);
  ZXing::BitMatrix matrix = writer.encode(text, target_w, target_h);
  const int w = matrix.width();
  const int h = matrix.height();
  std::vector<std::uint8_t> px(static_cast<size_t>(w) * h, 0xFF);
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      px[y * w + x] = matrix.get(x, y) ? 0x00 : 0xFF;
    }
  }
  return {std::move(px), w, h};
}

#endif  // SUPY_WITH_ZXING_CPP

}  // namespace

TEST(DataMatrixLocatorAbi, HasLibdmtxMatchesBuildFlag) {
#if defined(SUPY_WITH_LIBDMTX)
  EXPECT_EQ(supy_core_has_libdmtx(), 1);
#else
  EXPECT_EQ(supy_core_has_libdmtx(), 0);
#endif
}

TEST(DataMatrixLocatorAbi, NullInputReturnsNull) {
  EXPECT_EQ(supy_core_locate_datamatrix(nullptr), nullptr);
}

TEST(DataMatrixLocatorAbi, InvalidDimensionsReturnNull) {
  auto luma = blankLuma(8, 8);
  supy_core_locate_input_t in{};
  in.luma = luma.data();
  in.width = 0;
  in.height = 8;
  in.row_stride = 8;
  in.max_regions = 1;
  in.timeout_ms = 10;
  EXPECT_EQ(supy_core_locate_datamatrix(&in), nullptr);

  in.width = 8;
  in.height = 0;
  EXPECT_EQ(supy_core_locate_datamatrix(&in), nullptr);

  in.height = 8;
  in.row_stride = 4;  // < width
  EXPECT_EQ(supy_core_locate_datamatrix(&in), nullptr);
}

TEST(DataMatrixLocatorAbi, NullLumaReturnsNull) {
  supy_core_locate_input_t in{};
  in.luma = nullptr;
  in.width = 8;
  in.height = 8;
  in.row_stride = 8;
  in.max_regions = 1;
  in.timeout_ms = 10;
  EXPECT_EQ(supy_core_locate_datamatrix(&in), nullptr);
}

TEST(DataMatrixLocatorAbi, FreeNullHandleIsSafe) {
  supy_core_locate_results_free(nullptr);  // must not crash
  SUCCEED();
}

TEST(DataMatrixLocatorAbi, CountOnNullHandleIsZero) {
  EXPECT_EQ(supy_core_locate_count(nullptr), 0);
  float xy[8] = {};
  EXPECT_EQ(supy_core_locate_corners(nullptr, 0, xy), 0);
}

#if !defined(SUPY_WITH_LIBDMTX)

TEST(DataMatrixLocatorAbi, LocateReturnsNullWhenLibdmtxDisabled) {
  auto luma = blankLuma(32, 32);
  supy_core_locate_input_t in{};
  in.luma = luma.data();
  in.width = 32;
  in.height = 32;
  in.row_stride = 32;
  in.max_regions = 4;
  in.timeout_ms = 10;
  EXPECT_EQ(supy_core_locate_datamatrix(&in), nullptr);
}

#else  // SUPY_WITH_LIBDMTX

TEST(DataMatrixLocatorLocate, BlankFrameYieldsEmptyHandle) {
  auto luma = blankLuma(96, 96);
  supy_core_locate_input_t in{};
  in.luma = luma.data();
  in.width = 96;
  in.height = 96;
  in.row_stride = 96;
  in.max_regions = 4;
  in.timeout_ms = 50;

  auto* handle = supy_core_locate_datamatrix(&in);
  ASSERT_NE(handle, nullptr);
  EXPECT_EQ(supy_core_locate_count(handle), 0);
  supy_core_locate_results_free(handle);
}

#if defined(SUPY_WITH_ZXING_CPP)

TEST(DataMatrixLocatorLocate, FindsSyntheticDataMatrix) {
  const std::string payload = "supy-v1-s2-04-locator";
  auto img = renderDataMatrix(payload, 200, 200);

  supy_core_locate_input_t in{};
  in.luma = img.pixels.data();
  in.width = img.width;
  in.height = img.height;
  in.row_stride = img.width;
  in.max_regions = 4;
  in.timeout_ms = 200;

  auto* handle = supy_core_locate_datamatrix(&in);
  ASSERT_NE(handle, nullptr);
  ASSERT_GE(supy_core_locate_count(handle), 1);

  float xy[8] = {};
  ASSERT_EQ(supy_core_locate_corners(handle, 0, xy), 1);
  for (int i = 0; i < 8; i += 2) {
    EXPECT_GE(xy[i], 0.0f);
    EXPECT_LE(xy[i], static_cast<float>(img.width));
    EXPECT_GE(xy[i + 1], 0.0f);
    EXPECT_LE(xy[i + 1], static_cast<float>(img.height));
  }

  supy_core_locate_results_free(handle);
}

TEST(DataMatrixLocatorLocate, RespectsRowStridePadding) {
  // Build a luma frame with extra row padding to simulate a camera stride.
  const std::string payload = "stride-padded";
  auto img = renderDataMatrix(payload, 180, 180);
  const int pad = 16;
  const int stride = img.width + pad;
  std::vector<std::uint8_t> padded(static_cast<size_t>(stride) * img.height, 0xFF);
  for (int y = 0; y < img.height; ++y) {
    std::memcpy(
        padded.data() + static_cast<size_t>(y) * stride,
        img.pixels.data() + static_cast<size_t>(y) * img.width,
        static_cast<size_t>(img.width));
  }

  supy_core_locate_input_t in{};
  in.luma = padded.data();
  in.width = img.width;
  in.height = img.height;
  in.row_stride = stride;
  in.max_regions = 1;
  in.timeout_ms = 200;

  auto* handle = supy_core_locate_datamatrix(&in);
  ASSERT_NE(handle, nullptr);
  EXPECT_GE(supy_core_locate_count(handle), 1);
  supy_core_locate_results_free(handle);
}

#endif  // SUPY_WITH_ZXING_CPP

#endif  // SUPY_WITH_LIBDMTX
