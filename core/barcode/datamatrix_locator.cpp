#include "datamatrix_locator.h"

#include <algorithm>

#if defined(SUPY_WITH_LIBDMTX)
#include <dmtx.h>
#endif

namespace supy::scanner::barcode {

namespace {

bool isInputValid(const LocateInput& in) {
  if (in.luma == nullptr) return false;
  if (in.width <= 0 || in.height <= 0) return false;
  if (in.row_stride < in.width) return false;
  return true;
}

#if defined(SUPY_WITH_LIBDMTX)

// libdmtx returns regions through `reg->fit2raw`, a 3x3 transform mapping
// the unit square in "fit" space to pixel space. Sampling at the four unit
// corners gives the perspective quad in pixel coordinates. Per libdmtx
// convention, (0,0) is bottom-left of the matrix and the y-axis grows
// upward in "raw" space — we flip y back to image (top-left origin) so the
// returned quad matches `DecodedBarcode::corners` (TL,TR,BR,BL with y
// growing downward).
std::array<float, 8> cornersFromRegion(const DmtxRegion& reg, int height) {
  DmtxVector2 p00 = {0.0, 0.0};
  DmtxVector2 p10 = {1.0, 0.0};
  DmtxVector2 p11 = {1.0, 1.0};
  DmtxVector2 p01 = {0.0, 1.0};
  dmtxMatrix3VMultiplyBy(&p00, reg.fit2raw);
  dmtxMatrix3VMultiplyBy(&p10, reg.fit2raw);
  dmtxMatrix3VMultiplyBy(&p11, reg.fit2raw);
  dmtxMatrix3VMultiplyBy(&p01, reg.fit2raw);

  auto flipY = [height](double y) {
    return static_cast<float>(static_cast<double>(height) - 1.0 - y);
  };

  // After y-flip: p01 -> TL, p11 -> TR, p10 -> BR, p00 -> BL.
  return {
      static_cast<float>(p01.X), flipY(p01.Y),
      static_cast<float>(p11.X), flipY(p11.Y),
      static_cast<float>(p10.X), flipY(p10.Y),
      static_cast<float>(p00.X), flipY(p00.Y),
  };
}

#endif  // SUPY_WITH_LIBDMTX

}  // namespace

bool hasLibdmtx() {
#if defined(SUPY_WITH_LIBDMTX)
  return true;
#else
  return false;
#endif
}

std::vector<LocatedRegion> locate(const LocateInput& input) {
  if (!isInputValid(input)) {
    return {};
  }

#if defined(SUPY_WITH_LIBDMTX)
  // libdmtx takes a non-const buffer pointer even for read-only scans; the
  // const_cast is safe because the library never writes through it during
  // region discovery.
  auto* mutable_luma = const_cast<unsigned char*>(input.luma);
  DmtxImage* img = dmtxImageCreate(
      mutable_luma,
      input.width,
      input.height,
      DmtxPack8bppK);
  if (img == nullptr) return {};
  // Honor the camera's row stride by telling libdmtx how many pad bytes
  // sit at the end of each row.
  if (input.row_stride > input.width) {
    dmtxImageSetProp(img, DmtxPropRowPadBytes, input.row_stride - input.width);
  }

  DmtxDecode* dec = dmtxDecodeCreate(img, 1);
  if (dec == nullptr) {
    dmtxImageDestroy(&img);
    return {};
  }

  const int cap = std::max(1, input.max_regions);
  std::vector<LocatedRegion> out;
  out.reserve(static_cast<std::size_t>(cap));

  DmtxTime deadline;
  DmtxTime* deadline_ptr = nullptr;
  if (input.timeout_ms > 0) {
    deadline = dmtxTimeAdd(dmtxTimeNow(), input.timeout_ms);
    deadline_ptr = &deadline;
  }

  for (int i = 0; i < cap; ++i) {
    DmtxRegion* reg = dmtxRegionFindNext(dec, deadline_ptr);
    if (reg == nullptr) break;
    LocatedRegion r{};
    r.corners = cornersFromRegion(*reg, input.height);
    out.push_back(r);
    dmtxRegionDestroy(&reg);
  }

  dmtxDecodeDestroy(&dec);
  dmtxImageDestroy(&img);
  return out;
#else
  (void)input;
  return {};
#endif
}

}  // namespace supy::scanner::barcode
