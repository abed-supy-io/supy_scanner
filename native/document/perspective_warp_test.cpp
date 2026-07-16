#include "document/perspective_warp.h"

#include <gtest/gtest.h>

#include <cmath>
#include <vector>

using namespace supy::scanner::document;

namespace {

// Packed RGBA8888 image with an optional row-stride pad.
struct Image {
    std::vector<uint8_t> px;
    int width;
    int height;
    int rowStride;
};

Image makeImage(int w, int h, int padBytes = 0) {
    Image img{};
    img.width = w;
    img.height = h;
    img.rowStride = w * 4 + padBytes;
    img.px.assign(static_cast<size_t>(img.rowStride) * h, 0);
    return img;
}

void setPixel(Image& img, int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) {
    uint8_t* p = img.px.data() + static_cast<size_t>(y) * img.rowStride + static_cast<size_t>(x) * 4;
    p[0] = r; p[1] = g; p[2] = b; p[3] = a;
}

// Fills an axis-aligned rectangle [x0,x1) x [y0,y1) with white.
void fillWhiteRect(Image& img, int x0, int y0, int x1, int y1) {
    for (int y = y0; y < y1; ++y)
        for (int x = x0; x < x1; ++x) setPixel(img, x, y, 255, 255, 255);
}

float meanLuma(const WarpResult& r) {
    double acc = 0.0;
    for (int y = 0; y < r.height; ++y) {
        const uint8_t* row = r.rgba.data() + static_cast<size_t>(y) * r.rowStride;
        for (int x = 0; x < r.width; ++x) acc += row[x * 4];  // red channel proxy
    }
    return static_cast<float>(acc / (static_cast<double>(r.width) * r.height));
}

}  // namespace

TEST(PerspectiveWarp, ComputeHomographyIdentityMapsRectToItself) {
    std::array<Point, 4> src = {{{0, 0}, {100, 0}, {100, 50}, {0, 50}}};
    auto h = computeHomography(src, 100.0f, 50.0f);
    ASSERT_TRUE(h.has_value());
    const auto& m = h->m;
    // Destination (40,20) should map back to source (40,20).
    const float w = m[6] * 40 + m[7] * 20 + m[8];
    const float u = (m[0] * 40 + m[1] * 20 + m[2]) / w;
    const float v = (m[3] * 40 + m[4] * 20 + m[5]) / w;
    EXPECT_NEAR(u, 40.0f, 0.01f);
    EXPECT_NEAR(v, 20.0f, 0.01f);
}

TEST(PerspectiveWarp, DegenerateQuadReturnsNullopt) {
    // Collinear corners — homography is unsolvable.
    std::array<Point, 4> src = {{{0, 0}, {10, 0}, {20, 0}, {30, 0}}};
    EXPECT_FALSE(computeHomography(src, 100.0f, 50.0f).has_value());
}

TEST(PerspectiveWarp, RectifiedSizeUsesLongerEdges) {
    std::array<Point, 4> src = {{{0, 0}, {200, 0}, {180, 100}, {0, 120}}};
    int w = 0, h = 0;
    rectifiedSize(src, /*maxLongSide=*/0, &w, &h);
    EXPECT_EQ(w, 200);  // max(top=200, bottom=180)
    EXPECT_EQ(h, 120);  // max(left=120, right≈101)
}

TEST(PerspectiveWarp, RectifiedSizeClampsLongSide) {
    std::array<Point, 4> src = {{{0, 0}, {4000, 0}, {4000, 2000}, {0, 2000}}};
    int w = 0, h = 0;
    rectifiedSize(src, /*maxLongSide=*/2000, &w, &h);
    EXPECT_EQ(w, 2000);
    EXPECT_EQ(h, 1000);  // aspect preserved
}

TEST(PerspectiveWarp, WarpAxisAlignedRectExtractsWhiteRegion) {
    Image img = makeImage(200, 200);
    fillWhiteRect(img, 50, 60, 150, 140);  // 100x80 white block

    WarpInput in{};
    in.rgba = img.px.data();
    in.width = img.width;
    in.height = img.height;
    in.rowStride = img.rowStride;
    in.srcCorners = {{{50, 60}, {150, 60}, {150, 140}, {50, 140}}};

    auto out = warpToRect(in, /*maxLongSide=*/0);
    ASSERT_TRUE(out.has_value());
    EXPECT_EQ(out->width, 100);
    EXPECT_EQ(out->height, 80);
    // Interior should be (almost) entirely white.
    EXPECT_GT(meanLuma(*out), 245.0f);
}

TEST(PerspectiveWarp, WarpTiltedQuadRectifiesToWhite) {
    // A slightly rotated white rect — sample a generous interior so AA edges
    // don't drag the mean down.
    Image img = makeImage(240, 240);
    // Quad corners (TL,TR,BR,BL) of a tilted near-rectangle, all inside a
    // solid white region we paint coarsely.
    for (int y = 30; y < 210; ++y)
        for (int x = 30; x < 210; ++x) setPixel(img, x, y, 255, 255, 255);

    WarpInput in{};
    in.rgba = img.px.data();
    in.width = img.width;
    in.height = img.height;
    in.rowStride = img.rowStride;
    in.srcCorners = {{{50, 40}, {200, 60}, {190, 200}, {40, 180}}};

    auto out = warpToRect(in, /*maxLongSide=*/0);
    ASSERT_TRUE(out.has_value());
    EXPECT_GT(out->width, 0);
    EXPECT_GT(out->height, 0);
    EXPECT_GT(meanLuma(*out), 245.0f);
}

TEST(PerspectiveWarp, StridePaddedInputIsHandled) {
    Image img = makeImage(120, 120, /*padBytes=*/16);
    fillWhiteRect(img, 20, 20, 100, 100);

    WarpInput in{};
    in.rgba = img.px.data();
    in.width = img.width;
    in.height = img.height;
    in.rowStride = img.rowStride;
    in.srcCorners = {{{20, 20}, {100, 20}, {100, 100}, {20, 100}}};

    auto out = warpToRect(in, /*maxLongSide=*/0);
    ASSERT_TRUE(out.has_value());
    EXPECT_EQ(out->rowStride, out->width * 4);
    EXPECT_GT(meanLuma(*out), 245.0f);
}

TEST(PerspectiveWarp, InvalidInputReturnsNullopt) {
    WarpInput in{};
    in.rgba = nullptr;
    in.width = 100;
    in.height = 100;
    in.rowStride = 400;
    in.srcCorners = {{{0, 0}, {100, 0}, {100, 100}, {0, 100}}};
    EXPECT_FALSE(warpToRect(in, 0).has_value());
}
