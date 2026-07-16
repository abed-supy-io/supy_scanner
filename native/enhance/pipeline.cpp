#include "supy_scanner_enhance.h"

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <new>
#include <vector>

#include "buffer.h"
#include "clahe.h"
#include "illumination.h"
#include "quality_gate.h"
#include "tone.h"
#include "tophat.h"
#include "unsharp.h"

// Opaque handle storage. Owns the output buffer; pointer returned via
// supy_core_enhance_rgba is invalidated by supy_core_enhance_free.
struct supy_enhance_result_s {
  std::vector<std::uint8_t> rgba;
  std::int32_t width = 0;
  std::int32_t height = 0;
  std::int32_t row_stride = 0;
  std::uint32_t applied_stages = 0;
  float quality_score = 0.0f;
  std::int32_t verdict = SUPY_ENHANCE_VERDICT_OK;
  std::int32_t processing_ms = 0;
};

namespace {

using supy::scanner::enhance::OwnedRgba;
using supy::scanner::enhance::packCopy;
using supy::scanner::enhance::runQualityGate;
using supy::scanner::enhance::normalizeIllumination;
using supy::scanner::enhance::suppressSpecular;
using supy::scanner::enhance::applyTopHatFlatten;
using supy::scanner::enhance::applyClahe;
using supy::scanner::enhance::applyToneCurve;
using supy::scanner::enhance::applyUnsharpMask;
using supy::scanner::enhance::Verdict;

bool validInput(const supy_enhance_input_t* in) {
  if (in == nullptr) return false;
  if (in->rgba == nullptr) return false;
  if (in->width <= 0 || in->height <= 0) return false;
  if (in->row_stride < in->width * 4) return false;
  return true;
}

}  // namespace

extern "C" {

supy_enhance_result_t* supy_core_enhance(const supy_enhance_input_t* input) {
  if (!validInput(input)) return nullptr;

  const auto t0 = std::chrono::steady_clock::now();

  OwnedRgba owned = packCopy(input->rgba, input->width, input->height, input->row_stride);
  auto view = owned.view();

  auto* handle = new (std::nothrow) supy_enhance_result_s{};
  if (handle == nullptr) return nullptr;

  // Quality gate always runs (cheap + informative); skip if mode is OFF and
  // caller asked for pure pass-through.
  std::uint32_t applied = 0;
  std::int32_t verdictOut = SUPY_ENHANCE_VERDICT_OK;
  float blurScore = 0.0f;

  if (input->mode != SUPY_ENHANCE_OFF) {
    const auto gate = runQualityGate(view, input->min_blur_score);
    blurScore = gate.blurScore;
    verdictOut = static_cast<std::int32_t>(gate.verdict);
    applied |= SUPY_ENHANCE_STAGE_GATE;

    if (gate.verdict != Verdict::kReject) {
      switch (input->mode) {
        case SUPY_ENHANCE_FAST:
          applyToneCurve(view);
          applied |= SUPY_ENHANCE_STAGE_TONE;
          break;
        case SUPY_ENHANCE_BALANCED:
          normalizeIllumination(view);
          applied |= SUPY_ENHANCE_STAGE_ILLUMINATION;
          applyToneCurve(view);
          applied |= SUPY_ENHANCE_STAGE_TONE;
          applyUnsharpMask(view);
          applied |= SUPY_ENHANCE_STAGE_UNSHARP;
          break;
        case SUPY_ENHANCE_MAX:
          // Geometry-flatten first (vignette division), then strip glare, then
          // flatten the residual background offset, tone-map, lift local
          // contrast, and finally sharpen edges.
          normalizeIllumination(view);
          applied |= SUPY_ENHANCE_STAGE_ILLUMINATION;
          suppressSpecular(view);
          applied |= SUPY_ENHANCE_STAGE_SPECULAR;
          applyTopHatFlatten(view);
          applied |= SUPY_ENHANCE_STAGE_TOPHAT;
          applyToneCurve(view);
          applied |= SUPY_ENHANCE_STAGE_TONE;
          applyClahe(view);
          applied |= SUPY_ENHANCE_STAGE_CLAHE;
          applyUnsharpMask(view);
          applied |= SUPY_ENHANCE_STAGE_UNSHARP;
          break;
        default:
          break;
      }
    }
  }

  handle->rgba = std::move(owned.bytes);
  handle->width = input->width;
  handle->height = input->height;
  handle->row_stride = input->width * 4;
  handle->applied_stages = applied;
  handle->quality_score = blurScore;
  handle->verdict = verdictOut;

  const auto t1 = std::chrono::steady_clock::now();
  handle->processing_ms = static_cast<std::int32_t>(
      std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count());
  return handle;
}

const std::uint8_t* supy_core_enhance_rgba(const supy_enhance_result_t* h) {
  return h ? h->rgba.data() : nullptr;
}
std::int32_t supy_core_enhance_width(const supy_enhance_result_t* h) {
  return h ? h->width : 0;
}
std::int32_t supy_core_enhance_height(const supy_enhance_result_t* h) {
  return h ? h->height : 0;
}
std::int32_t supy_core_enhance_row_stride(const supy_enhance_result_t* h) {
  return h ? h->row_stride : 0;
}
std::uint32_t supy_core_enhance_applied_stages(const supy_enhance_result_t* h) {
  return h ? h->applied_stages : 0u;
}
float supy_core_enhance_quality_score(const supy_enhance_result_t* h) {
  return h ? h->quality_score : 0.0f;
}
std::int32_t supy_core_enhance_verdict(const supy_enhance_result_t* h) {
  return h ? h->verdict : SUPY_ENHANCE_VERDICT_REJECT;
}
std::int32_t supy_core_enhance_processing_ms(const supy_enhance_result_t* h) {
  return h ? h->processing_ms : 0;
}
void supy_core_enhance_free(supy_enhance_result_t* h) {
  delete h;
}

}  // extern "C"

namespace {

// Score-to-bucket thresholds. Aligned with the gate's reject/marginal
// (40 / 120) so a `veryPoor` bucket and a REJECT verdict mean the same thing.
// `good` / `excellent` cutoffs derived from synthetic-page experiments —
// crisp ≥A4 captures sit ~500-800 var-of-Laplacian on the synthetic
// checkerboard fixture; field captures of a clean printed page hover ~200-300.
constexpr float kBucketPoor      = 40.0f;
constexpr float kBucketOk        = 120.0f;
constexpr float kBucketGood      = 240.0f;
constexpr float kBucketExcellent = 480.0f;

// Soft normalizer for the wire-side `qualityScore`. 600 ≈ "very crisp" —
// anything beyond is clamped so the value stays in [0, 1] for the consumer.
constexpr float kQualityScoreNorm = 600.0f;

int32_t bucketFromBlurScore(float s) {
  if (s < kBucketPoor)      return SUPY_SCORE_BUCKET_VERY_POOR;
  if (s < kBucketOk)        return SUPY_SCORE_BUCKET_POOR;
  if (s < kBucketGood)      return SUPY_SCORE_BUCKET_OK;
  if (s < kBucketExcellent) return SUPY_SCORE_BUCKET_GOOD;
  return SUPY_SCORE_BUCKET_EXCELLENT;
}

bool validScoreInput(const supy_score_input_t* in) {
  if (in == nullptr) return false;
  if (in->rgba == nullptr) return false;
  if (in->width <= 0 || in->height <= 0) return false;
  if (in->row_stride < in->width * 4) return false;
  return true;
}

}  // namespace

extern "C" {

int32_t supy_core_score_page(const supy_score_input_t* input,
                             supy_score_result_t* out) {
  if (out == nullptr) return 0;
  if (!validScoreInput(input)) return 0;

  supy::scanner::enhance::RgbaView view{};
  view.data = const_cast<std::uint8_t*>(input->rgba);
  view.width = input->width;
  view.height = input->height;
  view.row_stride = input->row_stride;

  const auto gate = runQualityGate(view, /*min_blur_score=*/0.0f);
  const float norm = gate.blurScore / kQualityScoreNorm;
  out->blur_score = gate.blurScore;
  out->quality_score = norm < 0.0f ? 0.0f : (norm > 1.0f ? 1.0f : norm);
  out->bucket = bucketFromBlurScore(gate.blurScore);
  return 1;
}

}  // extern "C"
