// Host-side tests for the C ABI + C++ wrapper around zxing-cpp.
//
// Two layers of coverage:
//   1. ABI contract — input validation, NULL handling, ownership lifecycle.
//      These pass regardless of SUPY_WITH_ZXING_CPP.
//   2. Decode behavior — synthetic luma frames containing a QR / EAN code.
//      Gated on SUPY_WITH_ZXING_CPP so the suite stays green for the
//      default Sprint 1 build path.
//
// Runtime decode verification on real device camera frames is V1-S2-03a/b
// (Android JNI + iOS Swift wire-through) — out of scope for this gtest.

#include <gtest/gtest.h>

#include <cstdint>
#include <cstring>
#include <vector>

#include "barcode_decoder.h"
#include "supy_scanner.h"

#if defined(SUPY_WITH_ZXING_CPP)
#include "BitMatrix.h"
#include "MultiFormatWriter.h"
#endif

namespace {

// Renders a single full-white luma frame. Useful for "decode runs, finds
// nothing, returns empty handle" assertions.
std::vector<std::uint8_t> blankLuma(int width, int height, std::uint8_t fill = 0xFF) {
  return std::vector<std::uint8_t>(static_cast<size_t>(width) * height, fill);
}

#if defined(SUPY_WITH_ZXING_CPP)

// Encodes `text` as `format` and returns a luma buffer + dimensions.
// The buffer's row_stride == width (no padding).
struct LumaImage {
  std::vector<std::uint8_t> pixels;
  int width;
  int height;
};

LumaImage renderBarcode(const std::string& text, ZXing::BarcodeFormat format,
                        int target_w, int target_h, int margin = 10) {
  ZXing::MultiFormatWriter writer(format);
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

TEST(BarcodeDecoderAbi, HasZxingMatchesBuildFlag) {
#if defined(SUPY_WITH_ZXING_CPP)
  EXPECT_EQ(supy_core_has_zxing(), 1);
#else
  EXPECT_EQ(supy_core_has_zxing(), 0);
#endif
}

TEST(BarcodeDecoderAbi, NullInputReturnsNull) {
  EXPECT_EQ(supy_core_decode(nullptr), nullptr);
}

TEST(BarcodeDecoderAbi, InvalidDimensionsReturnNull) {
  auto luma = blankLuma(4, 4);
  supy_core_decode_input_t in{};
  in.luma = luma.data();
  in.width = 0;
  in.height = 4;
  in.row_stride = 4;
  in.formats = SUPY_FORMAT_ALL;
  EXPECT_EQ(supy_core_decode(&in), nullptr);

  in.width = 4;
  in.height = 0;
  EXPECT_EQ(supy_core_decode(&in), nullptr);

  in.height = 4;
  in.row_stride = 2;  // < width
  EXPECT_EQ(supy_core_decode(&in), nullptr);
}

TEST(BarcodeDecoderAbi, NullLumaReturnsNull) {
  supy_core_decode_input_t in{};
  in.luma = nullptr;
  in.width = 4;
  in.height = 4;
  in.row_stride = 4;
  in.formats = SUPY_FORMAT_ALL;
  EXPECT_EQ(supy_core_decode(&in), nullptr);
}

TEST(BarcodeDecoderAbi, FreeNullHandleIsSafe) {
  supy_core_decode_results_free(nullptr);  // must not crash
  SUCCEED();
}

TEST(BarcodeDecoderAbi, CountOnNullHandleIsZero) {
  EXPECT_EQ(supy_core_decode_count(nullptr), 0);
  EXPECT_EQ(supy_core_decode_text(nullptr, 0), nullptr);
  EXPECT_EQ(supy_core_decode_format(nullptr, 0), SUPY_FORMAT_NONE);
  float xy[8] = {};
  EXPECT_EQ(supy_core_decode_corners(nullptr, 0, xy), 0);
}

#if !defined(SUPY_WITH_ZXING_CPP)

TEST(BarcodeDecoderAbi, DecodeReturnsNullWhenZxingDisabled) {
  auto luma = blankLuma(16, 16);
  supy_core_decode_input_t in{};
  in.luma = luma.data();
  in.width = 16;
  in.height = 16;
  in.row_stride = 16;
  in.formats = SUPY_FORMAT_ALL;
  EXPECT_EQ(supy_core_decode(&in), nullptr);
}

#else  // SUPY_WITH_ZXING_CPP

TEST(BarcodeDecoderDecode, BlankFrameYieldsEmptyHandle) {
  auto luma = blankLuma(64, 64);
  supy_core_decode_input_t in{};
  in.luma = luma.data();
  in.width = 64;
  in.height = 64;
  in.row_stride = 64;
  in.formats = SUPY_FORMAT_ALL;
  in.try_harder = 0;
  in.try_rotate = 0;

  auto* handle = supy_core_decode(&in);
  ASSERT_NE(handle, nullptr);
  EXPECT_EQ(supy_core_decode_count(handle), 0);
  supy_core_decode_results_free(handle);
}

TEST(BarcodeDecoderDecode, DecodesSyntheticQrCode) {
  const std::string payload = "supy-scanner-v1-s2-03";
  auto img = renderBarcode(payload, ZXing::BarcodeFormat::QRCode, 200, 200);

  supy_core_decode_input_t in{};
  in.luma = img.pixels.data();
  in.width = img.width;
  in.height = img.height;
  in.row_stride = img.width;
  in.formats = SUPY_FORMAT_QR_CODE;
  in.try_harder = 1;
  in.try_rotate = 0;

  auto* handle = supy_core_decode(&in);
  ASSERT_NE(handle, nullptr);
  ASSERT_GE(supy_core_decode_count(handle), 1);

  const char* text = supy_core_decode_text(handle, 0);
  ASSERT_NE(text, nullptr);
  EXPECT_EQ(std::string(text), payload);
  EXPECT_EQ(supy_core_decode_format(handle, 0), SUPY_FORMAT_QR_CODE);

  float xy[8] = {};
  EXPECT_EQ(supy_core_decode_corners(handle, 0, xy), 1);
  // Corners should be inside the image bounds.
  for (int i = 0; i < 8; i += 2) {
    EXPECT_GE(xy[i], 0.0f);
    EXPECT_LE(xy[i], static_cast<float>(img.width));
    EXPECT_GE(xy[i + 1], 0.0f);
    EXPECT_LE(xy[i + 1], static_cast<float>(img.height));
  }

  supy_core_decode_results_free(handle);
}

TEST(BarcodeDecoderDecode, FormatMaskFiltersResults) {
  // Render an EAN-13 and ask for QR only — must come back empty.
  const std::string payload = "5901234123457";  // valid EAN-13 check digit
  auto img = renderBarcode(payload, ZXing::BarcodeFormat::EAN13, 200, 100);

  supy_core_decode_input_t in{};
  in.luma = img.pixels.data();
  in.width = img.width;
  in.height = img.height;
  in.row_stride = img.width;
  in.formats = SUPY_FORMAT_QR_CODE;
  in.try_harder = 1;
  in.try_rotate = 0;

  auto* handle = supy_core_decode(&in);
  ASSERT_NE(handle, nullptr);
  EXPECT_EQ(supy_core_decode_count(handle), 0);
  supy_core_decode_results_free(handle);
}

#endif  // SUPY_WITH_ZXING_CPP
