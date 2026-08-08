// Host-side tests for the document image enhancement pipeline.
//
// The pipeline runs on every captured page on Android (and on iOS when the
// consumer explicitly opts in). PNG fixtures aren't checked in — instead
// we synthesize deterministic RGBA buffers that exercise each stage's
// contract:
//
//   - blur gate verdict ≠ REJECT for a clean image
//   - illumination normalization flattens a synthetic vignette
//   - tone curve produces non-pass-through output on a low-contrast image
//   - unsharp mask boosts contrast at a synthetic step edge
//   - OFF is a pure pass-through (zero stages applied)
//
// These assertions are tight enough to catch regressions in the stage
// orchestration without being a golden-image diff (which would require an
// in-repo PNG codec dependency).

#include <gtest/gtest.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

#include "supy_scanner_enhance.h"

// Internal stage headers — exercised directly so a stage's contract is tested
// in isolation, without the upstream stages of a full pipeline run masking it.
#include "buffer.h"
#include "clahe.h"
#include "illumination.h"
#include "tophat.h"
#include "unsharp.h"

namespace {

using supy::scanner::enhance::RgbaView;

constexpr int kWidth = 256;
constexpr int kHeight = 256;
constexpr int kStride = kWidth * 4;

struct Image {
  std::vector<std::uint8_t> bytes;
  int width = kWidth;
  int height = kHeight;
  int stride = kStride;
};

Image makeImage() {
  Image img;
  img.bytes.assign(static_cast<std::size_t>(kStride) * kHeight, 0);
  return img;
}

void setPixel(Image& img, int x, int y, std::uint8_t v) {
  const std::size_t i = static_cast<std::size_t>(y) * img.stride + x * 4;
  img.bytes[i + 0] = v;
  img.bytes[i + 1] = v;
  img.bytes[i + 2] = v;
  img.bytes[i + 3] = 255;
}

std::uint8_t getPixel(const std::uint8_t* rgba, int stride, int x, int y) {
  return rgba[static_cast<std::size_t>(y) * stride + x * 4];
}

// A sharp checkerboard — high variance-of-Laplacian, should never be
// rejected by the blur gate.
Image sharpCheckerboard() {
  Image img = makeImage();
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      const std::uint8_t v = ((x / 8 + y / 8) % 2 == 0) ? 240 : 32;
      setPixel(img, x, y, v);
    }
  }
  return img;
}

// A uniform mid-gray field — variance-of-Laplacian ≈ 0, should trip the
// REJECT branch (callers re-prompt the user).
Image uniformGray() {
  Image img = makeImage();
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      setPixel(img, x, y, 128);
    }
  }
  return img;
}

// Sharp checkerboard multiplied by a radial vignette. The illumination
// stage's job is to undo this so the corner-vs-center luma gap collapses.
Image vignettedCheckerboard() {
  Image img = makeImage();
  const float cx = kWidth * 0.5f;
  const float cy = kHeight * 0.5f;
  const float maxR = std::sqrt(cx * cx + cy * cy);
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      const float dx = x - cx;
      const float dy = y - cy;
      const float r = std::sqrt(dx * dx + dy * dy) / maxR;
      // 1.0 at center, ~0.35 at corner.
      const float gain = 1.0f - 0.65f * r;
      const std::uint8_t base = ((x / 8 + y / 8) % 2 == 0) ? 240 : 32;
      const float lit = base * gain;
      const std::uint8_t v = static_cast<std::uint8_t>(
          std::max(0.0f, std::min(255.0f, lit)));
      setPixel(img, x, y, v);
    }
  }
  return img;
}

// Vertical step edge at x = width/2. Used to verify unsharp mask boosts
// micro-contrast at a known feature.
Image stepEdge() {
  Image img = makeImage();
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      setPixel(img, x, y, x < kWidth / 2 ? 96 : 160);
    }
  }
  return img;
}

// Mutable view over an Image's packed bytes (stride == width*4), for calling
// internal stage functions directly.
RgbaView viewFor(Image& img) {
  return RgbaView{img.bytes.data(), img.width, img.height, img.stride};
}

supy_enhance_input_t inputFor(const Image& img, supy_enhance_mode_t mode) {
  supy_enhance_input_t in{};
  in.rgba = img.bytes.data();
  in.width = img.width;
  in.height = img.height;
  in.row_stride = img.stride;
  in.mode = mode;
  in.min_blur_score = 0.0f;
  return in;
}

// Mean absolute luma difference between corner and center 16x16 patches.
// Drops sharply after illumination normalization.
float cornerCenterGap(const std::uint8_t* rgba, int stride) {
  auto patchMean = [&](int x0, int y0) {
    long sum = 0;
    for (int y = y0; y < y0 + 16; ++y) {
      for (int x = x0; x < x0 + 16; ++x) {
        sum += getPixel(rgba, stride, x, y);
      }
    }
    return sum / 256.0f;
  };
  const float center = patchMean(kWidth / 2 - 8, kHeight / 2 - 8);
  const float corner = patchMean(0, 0);
  return std::abs(center - corner);
}

}  // namespace

TEST(EnhancePipeline, NullInputReturnsNull) {
  EXPECT_EQ(supy_core_enhance(nullptr), nullptr);
}

TEST(EnhancePipeline, InvalidDimsReturnsNull) {
  Image img = sharpCheckerboard();
  auto in = inputFor(img, SUPY_ENHANCE_BALANCED);
  in.width = 0;
  EXPECT_EQ(supy_core_enhance(&in), nullptr);
}

TEST(EnhancePipeline, OffModeIsPassThrough) {
  Image img = sharpCheckerboard();
  auto in = inputFor(img, SUPY_ENHANCE_OFF);
  auto* h = supy_core_enhance(&in);
  ASSERT_NE(h, nullptr);
  EXPECT_EQ(supy_core_enhance_applied_stages(h), 0u);
  EXPECT_EQ(supy_core_enhance_width(h), kWidth);
  EXPECT_EQ(supy_core_enhance_height(h), kHeight);
  // OFF should leave pixels untouched.
  const std::uint8_t* out = supy_core_enhance_rgba(h);
  for (int i = 0; i < kStride * kHeight; ++i) {
    ASSERT_EQ(out[i], img.bytes[i]) << "byte " << i;
  }
  supy_core_enhance_free(h);
}

TEST(EnhancePipeline, BalancedAppliesAllStagesOnGoodImage) {
  Image img = sharpCheckerboard();
  auto in = inputFor(img, SUPY_ENHANCE_BALANCED);
  auto* h = supy_core_enhance(&in);
  ASSERT_NE(h, nullptr);
  EXPECT_NE(supy_core_enhance_verdict(h), SUPY_ENHANCE_VERDICT_REJECT);
  const std::uint32_t stages = supy_core_enhance_applied_stages(h);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_GATE);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_ILLUMINATION);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_TONE);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_UNSHARP);
  EXPECT_GE(supy_core_enhance_processing_ms(h), 0);
  supy_core_enhance_free(h);
}

TEST(EnhancePipeline, BlurredInputIsRejected) {
  Image img = uniformGray();
  auto in = inputFor(img, SUPY_ENHANCE_BALANCED);
  auto* h = supy_core_enhance(&in);
  ASSERT_NE(h, nullptr);
  EXPECT_EQ(supy_core_enhance_verdict(h), SUPY_ENHANCE_VERDICT_REJECT);
  // Rejected → pass-through copy, no downstream stages.
  const std::uint32_t stages = supy_core_enhance_applied_stages(h);
  EXPECT_FALSE(stages & SUPY_ENHANCE_STAGE_ILLUMINATION);
  EXPECT_FALSE(stages & SUPY_ENHANCE_STAGE_UNSHARP);
  supy_core_enhance_free(h);
}

TEST(EnhancePipeline, IlluminationFlattensVignette) {
  Image img = vignettedCheckerboard();
  const float gapBefore = cornerCenterGap(img.bytes.data(), kStride);

  auto in = inputFor(img, SUPY_ENHANCE_BALANCED);
  auto* h = supy_core_enhance(&in);
  ASSERT_NE(h, nullptr);
  const float gapAfter = cornerCenterGap(
      supy_core_enhance_rgba(h), supy_core_enhance_row_stride(h));

  // The vignette imparts a large corner-vs-center luma gap; balanced
  // mode should close most of it.
  EXPECT_GT(gapBefore, 40.0f) << "fixture sanity: vignette should be strong";
  EXPECT_LT(gapAfter, gapBefore * 0.5f)
      << "illumination stage failed to flatten vignette";
  supy_core_enhance_free(h);
}

TEST(EnhancePipeline, FastModeSkipsIlluminationAndUnsharp) {
  Image img = sharpCheckerboard();
  auto in = inputFor(img, SUPY_ENHANCE_FAST);
  auto* h = supy_core_enhance(&in);
  ASSERT_NE(h, nullptr);
  const std::uint32_t stages = supy_core_enhance_applied_stages(h);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_GATE);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_TONE);
  EXPECT_FALSE(stages & SUPY_ENHANCE_STAGE_ILLUMINATION);
  EXPECT_FALSE(stages & SUPY_ENHANCE_STAGE_UNSHARP);
  supy_core_enhance_free(h);
}

TEST(EnhancePipeline, FreeOnNullIsSafe) {
  supy_core_enhance_free(nullptr);
  // Accessors must also tolerate NULL.
  EXPECT_EQ(supy_core_enhance_rgba(nullptr), nullptr);
  EXPECT_EQ(supy_core_enhance_width(nullptr), 0);
  EXPECT_EQ(supy_core_enhance_height(nullptr), 0);
  EXPECT_EQ(supy_core_enhance_row_stride(nullptr), 0);
  EXPECT_EQ(supy_core_enhance_applied_stages(nullptr), 0u);
  EXPECT_EQ(supy_core_enhance_verdict(nullptr), SUPY_ENHANCE_VERDICT_REJECT);
  EXPECT_EQ(supy_core_enhance_processing_ms(nullptr), 0);
  EXPECT_EQ(supy_core_enhance_quality_score(nullptr), 0.0f);
}

// Unsharp's "widen a step edge" contract holds for the stage in isolation.
// (At the full-pipeline level it does NOT: BALANCED runs illumination first,
// whose morphological closing flattens a lone step toward the page mean,
// leaving unsharp nothing to overshoot — see MaxAppliesAdvancedStages /
// BalancedAppliesAllStagesOnGoodImage for the orchestration-level coverage.)
TEST(EnhanceStage, UnsharpWidensStepEdge) {
  Image img = stepEdge();
  const int y = kHeight / 2;
  const int xL = kWidth / 2 - 1;
  const int xR = kWidth / 2;
  const int beforeGap = std::abs(
      static_cast<int>(getPixel(img.bytes.data(), kStride, xL, y))
      - static_cast<int>(getPixel(img.bytes.data(), kStride, xR, y)));

  RgbaView view = viewFor(img);
  supy::scanner::enhance::applyUnsharpMask(view);

  const int afterGap = std::abs(
      static_cast<int>(getPixel(img.bytes.data(), kStride, xL, y))
      - static_cast<int>(getPixel(img.bytes.data(), kStride, xR, y)));
  EXPECT_GT(afterGap, beforeGap)
      << "unsharp mask should widen the step edge contrast";
}

// A low-contrast field that CLAHE should stretch: an 8px checkerboard whose
// two levels sit only 20 luma apart. CLAHE's clipped per-tile equalization
// pushes them further apart.
Image lowContrastCheckerboard() {
  Image img = makeImage();
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      const std::uint8_t v = ((x / 8 + y / 8) % 2 == 0) ? 130 : 110;
      setPixel(img, x, y, v);
    }
  }
  return img;
}

TEST(EnhanceStage, ClaheLiftsLocalContrast) {
  Image img = lowContrastCheckerboard();
  // Adjacent light/dark cells near the centre.
  const int y = kHeight / 2 + 2;
  const int xLight = kWidth / 2 + 2;   // a "130" cell
  const int xDark = kWidth / 2 + 10;   // the neighbouring "110" cell
  const int before = std::abs(
      static_cast<int>(getPixel(img.bytes.data(), kStride, xLight, y))
      - static_cast<int>(getPixel(img.bytes.data(), kStride, xDark, y)));

  RgbaView view = viewFor(img);
  supy::scanner::enhance::applyClahe(view);

  const int after = std::abs(
      static_cast<int>(getPixel(img.bytes.data(), kStride, xLight, y))
      - static_cast<int>(getPixel(img.bytes.data(), kStride, xDark, y)));
  EXPECT_GT(after, before) << "CLAHE should stretch local contrast";
}

TEST(EnhanceStage, TopHatLiftsDimBackground) {
  // A uniformly dim page (luma 150, below paper white). Top-hat estimates the
  // background and lifts every pixel toward paper, capped at +80.
  Image img = makeImage();
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) setPixel(img, x, y, 150);
  }
  const int before = getPixel(img.bytes.data(), kStride, kWidth / 2, kHeight / 2);

  RgbaView view = viewFor(img);
  supy::scanner::enhance::applyTopHatFlatten(view);

  const int after = getPixel(img.bytes.data(), kStride, kWidth / 2, kHeight / 2);
  EXPECT_GT(after, before + 40) << "top-hat should lift a dim background";
  EXPECT_LE(after, 255);
}

TEST(EnhanceStage, SuppressSpecularClampsHotspot) {
  // Diffuse page at luma 180 with a small blown-out blow (luma 255) narrower
  // than the morphological SE, so the opening strips it and flags it as glare.
  Image img = makeImage();
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) setPixel(img, x, y, 180);
  }
  const int cx = kWidth / 2;
  const int cy = kHeight / 2;
  for (int y = cy - 4; y < cy + 4; ++y) {
    for (int x = cx - 4; x < cx + 4; ++x) setPixel(img, x, y, 255);
  }
  const int hotBefore = getPixel(img.bytes.data(), kStride, cx, cy);
  const int diffuseBefore = getPixel(img.bytes.data(), kStride, 4, 4);

  RgbaView view = viewFor(img);
  supy::scanner::enhance::suppressSpecular(view);

  const int hotAfter = getPixel(img.bytes.data(), kStride, cx, cy);
  const int diffuseAfter = getPixel(img.bytes.data(), kStride, 4, 4);
  EXPECT_LT(hotAfter, hotBefore) << "glare hotspot should be pulled down";
  EXPECT_EQ(diffuseAfter, diffuseBefore) << "diffuse paper must be untouched";
}

TEST(EnhancePipeline, MaxAppliesAdvancedStages) {
  Image img = sharpCheckerboard();
  auto in = inputFor(img, SUPY_ENHANCE_MAX);
  auto* h = supy_core_enhance(&in);
  ASSERT_NE(h, nullptr);
  EXPECT_NE(supy_core_enhance_verdict(h), SUPY_ENHANCE_VERDICT_REJECT);
  const std::uint32_t stages = supy_core_enhance_applied_stages(h);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_GATE);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_ILLUMINATION);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_SPECULAR);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_TOPHAT);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_TONE);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_CLAHE);
  EXPECT_TRUE(stages & SUPY_ENHANCE_STAGE_UNSHARP);
  supy_core_enhance_free(h);
}

// -----------------------------------------------------------------------------
// supy_core_score_page — standalone per-page quality scorer.

TEST(ScorePage, NullInputReturnsFailure) {
  supy_score_result_t r{};
  EXPECT_EQ(supy_core_score_page(nullptr, &r), 0);

  supy_score_input_t in{};
  EXPECT_EQ(supy_core_score_page(&in, nullptr), 0);
}

TEST(ScorePage, InvalidDimsReturnsFailure) {
  Image img = sharpCheckerboard();
  supy_score_input_t in{};
  in.rgba = img.bytes.data();
  in.width = 0;
  in.height = img.height;
  in.row_stride = img.stride;
  supy_score_result_t r{};
  EXPECT_EQ(supy_core_score_page(&in, &r), 0);

  in.width = img.width;
  in.row_stride = img.width * 4 - 1;  // stride < width*4
  EXPECT_EQ(supy_core_score_page(&in, &r), 0);
}

TEST(ScorePage, SharpInputProducesHighBucket) {
  Image img = sharpCheckerboard();
  supy_score_input_t in{};
  in.rgba = img.bytes.data();
  in.width = img.width;
  in.height = img.height;
  in.row_stride = img.stride;
  supy_score_result_t r{};
  ASSERT_EQ(supy_core_score_page(&in, &r), 1);

  // Checkerboard => very high variance-of-Laplacian => excellent bucket and
  // qualityScore clamped at 1.0.
  EXPECT_EQ(r.bucket, SUPY_SCORE_BUCKET_EXCELLENT);
  EXPECT_GE(r.quality_score, 0.0f);
  EXPECT_LE(r.quality_score, 1.0f);
  EXPECT_GT(r.blur_score, 0.0f);
}

TEST(ScorePage, FlatInputProducesVeryPoorBucket) {
  Image img = makeImage();  // all-zero (with alpha 0 too)
  // Fill with constant gray so the gate sees a real but blur-free image.
  for (int y = 0; y < img.height; ++y) {
    for (int x = 0; x < img.width; ++x) {
      setPixel(img, x, y, 128);
    }
  }
  supy_score_input_t in{};
  in.rgba = img.bytes.data();
  in.width = img.width;
  in.height = img.height;
  in.row_stride = img.stride;
  supy_score_result_t r{};
  ASSERT_EQ(supy_core_score_page(&in, &r), 1);
  // Zero variance => veryPoor and qualityScore == 0.
  EXPECT_EQ(r.bucket, SUPY_SCORE_BUCKET_VERY_POOR);
  EXPECT_FLOAT_EQ(r.quality_score, 0.0f);
}
