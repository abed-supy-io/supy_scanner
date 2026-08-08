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

// Wire-stable indices. Values 0..7 match the original v1.0 ordering and MUST
// NOT be reordered — `kSupyDocumentFrameStateWireIndex` on the Dart side maps
// by these numbers, and the launcher path persists state across native ↔
// channel boundaries by name + raw value. New variants append only.
//
// Detection-priority ordering (which state preempts which when several apply
// on the same frame) is encoded separately in `priority()` in the .cpp — it
// is NOT the same as this enum's numeric ordering.
enum class FrameState : std::uint8_t {
  kNoDocument = 0,
  kTooDark = 1,
  kTooClose = 2,
  kTooFar = 3,
  kTooSkewed = 4,
  kBlurry = 5,
  kHoldSteady = 6,
  kReady = 7,
  // Appended for the CQG sprint. Order here is wire-stable; matches the
  // tail of `kSupyDocumentFrameStateWireIndex` in
  // `lib/src/models/supy_document_frame_state.dart`.
  kGlare = 8,
  kOccluded = 9,
  kHandShake = 10,
  kEdgeClipped = 11,
  // Framing checks all pass but the quad sits too far off-center. Emitted
  // after `firstFailure` clears, before the stability gate, so the consumer
  // can prompt a recenter before promoting to ready. The arrow direction is
  // a pure render detail derived from the signed centerOffset — no direction
  // is encoded in the state itself.
  kOffCenter = 12,
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
  // CQG additions — see Dart `SupyDocumentFrameMetrics` for semantics.
  float glareRatio = 0.0f;          // 0..1, fraction of luma > 245 inside quad
  float cornerVelocity = 0.0f;      // 0..~0.1, L2 of quad delta / preview diag
  // Per-corner EMA distance from `QuadStabilityTracker` (TL/TR/BR/BL).
  // Length-4 if present; a length-0 array signals "no per-corner signal this
  // frame" — the classifier holds its prior occlusion judgement.
  std::array<float, 4> perCornerStability{};
  bool hasPerCornerStability = false;
  // Signed quad-centroid offset from preview center, per axis, in half-extent
  // fractions: `(centroid - 0.5) * 2`. Range ~[-1, 1]. Positive X = quad sits
  // right of center; positive Y = below center. Native detectors compute this
  // from the quad they already have (the smoothed path carries no usable quad).
  float centerOffsetX = 0.0f;
  float centerOffsetY = 0.0f;
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
  // CQG additions — mirror of the Dart `SupyDocumentGuidanceConfiguration`.
  float maxGlareRatio = 0.04f;
  float glareExitMargin = 0.50f;  // wider than `exitMargin` — glare is bursty
  float maxCornerVelocity = 0.020f;
  float minPerCornerStability = 0.55f;
  bool edgeClipBlocking = false;  // invoice preset flips this to true
  // Max allowed quad-centroid offset from center (half-extent fraction) before
  // `kOffCenter` fires once framing otherwise passes. A non-positive value
  // disables center guidance entirely — Dart passes a sentinel `-1` when the
  // consumer turns `centerGuidanceEnabled` off, so no extra wire bool is
  // needed.
  float maxCenterOffset = 0.12f;
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

  // CQG additions.
  float glare = 0.0f;
  float cornerVelocity = 0.0f;
  std::array<float, 4> perCornerStability{};
  bool hasPerCornerStability = false;
  // Smoothed signed center offset (half-extent fractions, per axis).
  float centerOffsetX = 0.0f;
  float centerOffsetY = 0.0f;
  // Live, opaque quality estimate in [0,1] surfaced to consumers. Computed
  // ONLY on the C++ side; the Dart smoother treats this as passthrough so we
  // don't double-smooth. See header doc for the source-of-truth exception.
  float liveQualityScore = 0.0f;

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
  // CQG additions.
  float glareRatio = 0.0f;
  float cornerVelocity = 0.0f;
  std::array<float, 4> perCornerStability{};
  bool hasPerCornerStability = false;
  // Smoothed signed center offset (half-extent fractions, per axis).
  float centerOffsetX = 0.0f;
  float centerOffsetY = 0.0f;
  // Opaque, C++-computed quality estimate surfaced in `frame_metrics` to
  // consumers. Dart never recomputes — see header doc.
  float liveQualityScore = 0.0f;
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
