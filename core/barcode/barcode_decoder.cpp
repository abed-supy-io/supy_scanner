#include "barcode_decoder.h"

#include "supy_scanner.h"

#if defined(SUPY_WITH_ZXING_CPP)
#include "ReadBarcode.h"
#include "ImageView.h"
#include "BarcodeFormat.h"
#endif

namespace supy::scanner::barcode {

namespace {

#if defined(SUPY_WITH_ZXING_CPP)

ZXing::BarcodeFormats fromMask(std::uint32_t mask) {
  if (mask == SUPY_FORMAT_NONE || mask == SUPY_FORMAT_ALL) {
    return ZXing::BarcodeFormat::Any;
  }
  ZXing::BarcodeFormats formats;
  if (mask & SUPY_FORMAT_AZTEC)             formats |= ZXing::BarcodeFormat::Aztec;
  if (mask & SUPY_FORMAT_CODABAR)           formats |= ZXing::BarcodeFormat::Codabar;
  if (mask & SUPY_FORMAT_CODE_39)           formats |= ZXing::BarcodeFormat::Code39;
  if (mask & SUPY_FORMAT_CODE_93)           formats |= ZXing::BarcodeFormat::Code93;
  if (mask & SUPY_FORMAT_CODE_128)          formats |= ZXing::BarcodeFormat::Code128;
  if (mask & SUPY_FORMAT_DATA_MATRIX)       formats |= ZXing::BarcodeFormat::DataMatrix;
  if (mask & SUPY_FORMAT_EAN_8)             formats |= ZXing::BarcodeFormat::EAN8;
  if (mask & SUPY_FORMAT_EAN_13)            formats |= ZXing::BarcodeFormat::EAN13;
  if (mask & SUPY_FORMAT_ITF)               formats |= ZXing::BarcodeFormat::ITF;
  if (mask & SUPY_FORMAT_PDF_417)           formats |= ZXing::BarcodeFormat::PDF417;
  if (mask & SUPY_FORMAT_QR_CODE)           formats |= ZXing::BarcodeFormat::QRCode;
  if (mask & SUPY_FORMAT_UPC_A)             formats |= ZXing::BarcodeFormat::UPCA;
  if (mask & SUPY_FORMAT_UPC_E)             formats |= ZXing::BarcodeFormat::UPCE;
  if (mask & SUPY_FORMAT_DATA_BAR)          formats |= ZXing::BarcodeFormat::DataBar;
  if (mask & SUPY_FORMAT_DATA_BAR_EXPANDED) formats |= ZXing::BarcodeFormat::DataBarExpanded;
  if (mask & SUPY_FORMAT_MICRO_QR)          formats |= ZXing::BarcodeFormat::MicroQRCode;
  if (mask & SUPY_FORMAT_RMQR)              formats |= ZXing::BarcodeFormat::RMQRCode;
  if (mask & SUPY_FORMAT_MAXI_CODE)         formats |= ZXing::BarcodeFormat::MaxiCode;
  return formats;
}

std::uint32_t toMask(ZXing::BarcodeFormat fmt) {
  switch (fmt) {
    case ZXing::BarcodeFormat::Aztec:           return SUPY_FORMAT_AZTEC;
    case ZXing::BarcodeFormat::Codabar:         return SUPY_FORMAT_CODABAR;
    case ZXing::BarcodeFormat::Code39:          return SUPY_FORMAT_CODE_39;
    case ZXing::BarcodeFormat::Code93:          return SUPY_FORMAT_CODE_93;
    case ZXing::BarcodeFormat::Code128:         return SUPY_FORMAT_CODE_128;
    case ZXing::BarcodeFormat::DataMatrix:      return SUPY_FORMAT_DATA_MATRIX;
    case ZXing::BarcodeFormat::EAN8:            return SUPY_FORMAT_EAN_8;
    case ZXing::BarcodeFormat::EAN13:           return SUPY_FORMAT_EAN_13;
    case ZXing::BarcodeFormat::ITF:             return SUPY_FORMAT_ITF;
    case ZXing::BarcodeFormat::PDF417:          return SUPY_FORMAT_PDF_417;
    case ZXing::BarcodeFormat::QRCode:          return SUPY_FORMAT_QR_CODE;
    case ZXing::BarcodeFormat::UPCA:            return SUPY_FORMAT_UPC_A;
    case ZXing::BarcodeFormat::UPCE:            return SUPY_FORMAT_UPC_E;
    case ZXing::BarcodeFormat::DataBar:         return SUPY_FORMAT_DATA_BAR;
    case ZXing::BarcodeFormat::DataBarExpanded: return SUPY_FORMAT_DATA_BAR_EXPANDED;
    case ZXing::BarcodeFormat::MicroQRCode:     return SUPY_FORMAT_MICRO_QR;
    case ZXing::BarcodeFormat::RMQRCode:        return SUPY_FORMAT_RMQR;
    case ZXing::BarcodeFormat::MaxiCode:        return SUPY_FORMAT_MAXI_CODE;
    default:                                    return SUPY_FORMAT_NONE;
  }
}

#endif  // SUPY_WITH_ZXING_CPP

bool isInputValid(const DecodeInput& in) {
  if (in.luma == nullptr) return false;
  if (in.width <= 0 || in.height <= 0) return false;
  if (in.row_stride < in.width) return false;
  return true;
}

}  // namespace

bool hasZxing() {
#if defined(SUPY_WITH_ZXING_CPP)
  return true;
#else
  return false;
#endif
}

std::vector<DecodedBarcode> decode(const DecodeInput& input) {
  if (!isInputValid(input)) {
    return {};
  }

#if defined(SUPY_WITH_ZXING_CPP)
  using namespace ZXing;

  auto image = ImageView(
      input.luma,
      input.width,
      input.height,
      ImageFormat::Lum,
      input.row_stride);

  auto opts = ReaderOptions()
                  .setFormats(fromMask(input.formats))
                  .setTryHarder(input.try_harder)
                  .setTryRotate(input.try_rotate)
                  // We treat the camera frame as a sequence of independent
                  // attempts; deduplication happens upstream in the Kotlin /
                  // Swift loop, where it can also gate-by-confidence.
                  .setMaxNumberOfSymbols(8);

  auto results = ReadBarcodes(image, opts);

  std::vector<DecodedBarcode> out;
  out.reserve(results.size());
  for (const auto& r : results) {
    if (!r.isValid()) continue;
    const auto pos = r.position();
    DecodedBarcode db{};
    db.text = r.text();
    db.format = toMask(r.format());
    db.corners = {
        static_cast<float>(pos.topLeft().x),     static_cast<float>(pos.topLeft().y),
        static_cast<float>(pos.topRight().x),    static_cast<float>(pos.topRight().y),
        static_cast<float>(pos.bottomRight().x), static_cast<float>(pos.bottomRight().y),
        static_cast<float>(pos.bottomLeft().x),  static_cast<float>(pos.bottomLeft().y),
    };
    out.push_back(std::move(db));
  }
  return out;
#else
  (void)input;
  return {};
#endif
}

}  // namespace supy::scanner::barcode
