// document_edge_detector_test.cpp — GoogleTest cases for the document edge detector.
#include "document/document_edge_detector.h"
#include <gtest/gtest.h>
#include <vector>

using namespace supy::scanner::document;

// Synthesizes a W×H Y-plane with a bright rectangle on a dark background.
static std::vector<uint8_t> makeRectImage(int w, int h, int x0, int y0, int x1, int y1) {
    std::vector<uint8_t> img(static_cast<size_t>(w * h), 30);
    for (int y = y0; y < y1; ++y)
        for (int x = x0; x < x1; ++x)
            img[static_cast<size_t>(y * w + x)] = 200;
    return img;
}

TEST(DocumentEdgeDetector, DetectsCenteredRectangle) {
    // Bright rect occupying most of a 256×256 frame → strong edges everywhere.
    auto img = makeRectImage(256, 256, 40, 60, 220, 200);
    DetectionInput in{img.data(), 256, 256, 256};
    auto q = detectDocument(in);
    ASSERT_TRUE(q.has_value()) << "Expected a quad on a bright-rect image";
    // TL corner near (40/256, 60/256); BR corner near (220/256, 200/256).
    EXPECT_NEAR(q->corners[0].x, 40.f / 256.f,  0.05f);
    EXPECT_NEAR(q->corners[0].y, 60.f / 256.f,  0.05f);
    EXPECT_NEAR(q->corners[2].x, 220.f / 256.f, 0.05f);
    EXPECT_NEAR(q->corners[2].y, 200.f / 256.f, 0.05f);
    EXPECT_GT(q->coverageRatio, 0.0f);
    EXPECT_LT(q->coverageRatio, 1.0f);
}

TEST(DocumentEdgeDetector, ReturnsNulloptOnUniformInput) {
    // Perfectly uniform grey → no edges → no quad.
    std::vector<uint8_t> img(256 * 256, 128);
    DetectionInput in{img.data(), 256, 256, 256};
    EXPECT_FALSE(detectDocument(in).has_value());
}

TEST(DocumentEdgeDetector, DetectsRectangleWithPaddedStride) {
    // rowStride = width + 16 (typical CameraX padding).
    constexpr int w = 256, h = 256, stride = w + 16;
    std::vector<uint8_t> img(static_cast<size_t>(stride) * h, 30);
    // Bright rectangle from (40,60)..(220,200), but written into a stride-padded buffer.
    for (int y = 60; y < 200; ++y)
        for (int x = 40; x < 220; ++x)
            img[static_cast<size_t>(y) * stride + x] = 200;
    DetectionInput in{img.data(), w, h, stride};
    auto q = detectDocument(in);
    ASSERT_TRUE(q.has_value());
    EXPECT_NEAR(q->corners[0].x, 40.f / w, 0.05f);
    EXPECT_NEAR(q->corners[2].y, 200.f / h, 0.05f);
}
