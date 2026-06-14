// document_guidance_classifier.h — pure-C++ port of the Dart
// `SupyDocumentStateMachine` + `SupyDocumentMetricsSmoother`.
//
// The Dart classifier remains the source of truth for the PlatformView path
// (where Flutter consumes `frame_metrics` and renders an overlay in Dart).
// This native port exists for the standalone launcher path
// (DocumentScannerPresenter / CameraXDocumentScannerActivity), which paints
// hint text directly into the native scanner UI without a Dart round-trip.
//
// Behavioural contract: identical state transitions to the Dart impl for the
// same metric sequence. The host-side gtest fixture pins this by replaying
// canned metric streams and asserting the produced state sequence.
//
// No I/O, no allocations on the steady-state path, no exceptions.
#pragma once

#include <array>
#include <cstdint>

namespace supy::scanner::document {

enum class FrameState : std::uint8_t {
  kNoDocument = 0,
  kTooDark = 1,
  kTooClose = 2,
  kTooFar = 3,
  kTooSkewed = 4,
  kBlurry = 5,
  kHoldSteady = 6,
  kReady = 7,
};

// Mirror of `SupyDocumentFrameMetrics`. Pure data — populate from the
// platform's per-frame measurement and feed into `classify`.
struct FrameMetrics {
  bool hasDocument = false;
  bool clipsEdge = false;
  float coverageRatio = 0.0f;
  float tiltDegrees = 0.0f;
  float meanLuma = 0.0f;        // 0..255
  float blurScore = 0.0f;       // variance-of-Laplacian
  float quadStability = 0.0f;   // 0..1
  float interiorVariance = 0.0f;
};

// Mirror of `SupyDocumentGuidanceConfiguration` (threshold subset — colors and
// hint copy stay in the consumer layer).
struct GuidanceConfig {
  float minCoverageRatio = 0.30f;
  float maxCoverageRatio = 0.90f;
  float maxTiltDegrees = 20.0f;
  float minMeanLuma = 60.0f;
  float minBlurScore = 80.0f;
  float readyStabilityFloor = 0.75f;
  float interiorVarianceFloor = 5.0f;
  float exitMargin = 0.10f;
  float smoothingAlpha = 0.35f;
  int readyStableFrames = 5;
  int holdSteadyFrames = 6;
  int lostDocumentGraceFrames = 3;
  int minDwellFrames = 4;
};

// Internal classifier state. Zero-initialise on construction; `reset()`
// restores that initial state. Safe to allocate on the stack or as a member.
struct GuidanceState {
  FrameState current = FrameState::kNoDocument;
  int framesAtState = 0;
  int goodStreak = 0;
  int missingStreak = 0;

  // EMA smoother accumulators. `hasSamples == false` means "no document
  // sample ingested yet — seed from the next present frame".
  bool hasSamples = false;
  float coverage = 0.0f;
  float tilt = 0.0f;
  float luma = 0.0f;
  float blur = 0.0f;
  float stability = 0.0f;
  float interior = 0.0f;
  // Smoothed quad — 4 points (x,y) packed as 8 floats, TL/TR/BR/BL.
  std::array<float, 8> quad{};
  bool hasQuad = false;
  bool lastClipsEdge = false;

  void reset() { *this = GuidanceState{}; }
};

// Optional smoothed-metrics output produced alongside the new state. UIs that
// also want to draw an outline from the C++ pipeline read it from here.
struct SmoothedMetrics {
  bool hasDocument = false;
  bool clipsEdge = false;
  float coverageRatio = 0.0f;
  float tiltDegrees = 0.0f;
  float meanLuma = 0.0f;
  float blurScore = 0.0f;
  float quadStability = 0.0f;
  float interiorVariance = 0.0f;
  std::array<float, 8> quad{};
};

#if defined(_WIN32)
#  define SUPY_GUIDANCE_EXPORT __declspec(dllexport)
#else
#  define SUPY_GUIDANCE_EXPORT __attribute__((visibility("default")))
#endif

// Smooth `raw` into `state`'s EMA, classify, commit hysteresis/dwell rules,
// and return the resulting `FrameState`. `out_smoothed` (optional) receives
// the smoothed metrics used for classification — pass nullptr if the caller
// only needs the state.
SUPY_GUIDANCE_EXPORT FrameState classify(const FrameMetrics& raw,
                                          const GuidanceConfig& config,
                                          GuidanceState& state,
                                          SmoothedMetrics* out_smoothed);

}  // namespace supy::scanner::document
