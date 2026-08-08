// document_guidance_classifier.cpp — see header for the contract.
//
// Direct port of lib/src/document/supy_document_state_machine.dart +
// supy_document_metrics_smoother.dart. Order of operations and threshold
// arithmetic match the Dart line-by-line so the host gtest fixture (which
// replays the same sequences that lib/test/.../ exercises) sees identical
// state transitions.

#include "document_guidance_classifier.h"

#include <algorithm>
#include <cmath>

namespace supy::scanner::document {

namespace {

// Detection-priority table. Indexed by the enum's wire value (NOT by the
// urgency rank). Must stay byte-identical to `_priority` in the Dart state
// machine — a drift here means the launcher path and the PlatformView path
// surface different hints on the same frame. New entries append by wire
// value, not by rank.
constexpr int kPriority[] = {
    /* kNoDocument  = 0 */ 0,
    /* kTooDark     = 1 */ 2,
    /* kTooClose    = 2 */ 5,
    /* kTooFar      = 3 */ 6,
    /* kTooSkewed   = 4 */ 7,
    /* kBlurry      = 5 */ 8,
    /* kHoldSteady  = 6 */ 11,
    /* kReady       = 7 */ 12,
    /* kGlare       = 8 */ 3,
    /* kOccluded    = 9 */ 1,
    /* kHandShake   = 10*/ 9,
    /* kEdgeClipped = 11*/ 4,
    // Sits between handShake (9) and holdSteady (11): off-center is only
    // reached once every hard failure clears, but must still preempt the
    // settle-toward-ready holdSteady so the recenter prompt wins.
    /* kOffCenter   = 12*/ 10,
};

inline int priority(FrameState s) {
  return kPriority[static_cast<int>(s)];
}

inline float ema(bool seeded, float previous, float sample, float alpha) {
  return seeded ? (previous + alpha * (sample - previous)) : sample;
}

// Updates the EMA accumulators. Mirrors `SupyDocumentMetricsSmoother.add`:
// when the sample reports no document, the accumulator is reset and the raw
// sample is propagated verbatim — the state machine's grace-frame logic then
// decides whether to tolerate the gap.
void smooth(const FrameMetrics& raw,
            const GuidanceConfig& config,
            GuidanceState& state,
            SmoothedMetrics& out) {
  if (!raw.hasDocument) {
    state.hasSamples = false;
    state.hasQuad = false;
    state.lastClipsEdge = false;
    state.coverage = state.tilt = state.luma = state.blur =
        state.stability = state.interior = 0.0f;
    state.glare = 0.0f;
    state.cornerVelocity = 0.0f;
    state.hasPerCornerStability = false;
    state.perCornerStability = {};
    state.centerOffsetX = 0.0f;
    state.centerOffsetY = 0.0f;
    state.liveQualityScore = 0.0f;
    out.hasDocument = false;
    out.clipsEdge = false;
    out.coverageRatio = 0.0f;
    out.tiltDegrees = 0.0f;
    out.meanLuma = 0.0f;
    out.blurScore = 0.0f;
    out.quadStability = 0.0f;
    out.interiorVariance = 0.0f;
    out.glareRatio = 0.0f;
    out.cornerVelocity = 0.0f;
    out.perCornerStability = {};
    out.hasPerCornerStability = false;
    out.centerOffsetX = 0.0f;
    out.centerOffsetY = 0.0f;
    out.liveQualityScore = 0.0f;
    out.quad = {};
    return;
  }
  const float a = config.smoothingAlpha;
  state.coverage = ema(state.hasSamples, state.coverage, raw.coverageRatio, a);
  state.tilt = ema(state.hasSamples, state.tilt, raw.tiltDegrees, a);
  state.luma = ema(state.hasSamples, state.luma, raw.meanLuma, a);
  state.blur = ema(state.hasSamples, state.blur, raw.blurScore, a);
  state.stability =
      ema(state.hasSamples, state.stability, raw.quadStability, a);
  state.interior =
      ema(state.hasSamples, state.interior, raw.interiorVariance, a);
  state.glare = ema(state.hasSamples, state.glare, raw.glareRatio, a);
  state.cornerVelocity =
      ema(state.hasSamples, state.cornerVelocity, raw.cornerVelocity, a);
  state.centerOffsetX =
      ema(state.hasSamples, state.centerOffsetX, raw.centerOffsetX, a);
  state.centerOffsetY =
      ema(state.hasSamples, state.centerOffsetY, raw.centerOffsetY, a);
  // Per-corner EMA. Mirror of the Dart smoother: when the incoming frame
  // doesn't carry 4 corner values, hold the previous vector so one dropped
  // detection doesn't reset the occlusion judgement.
  if (raw.hasPerCornerStability) {
    if (!state.hasPerCornerStability) {
      state.perCornerStability = raw.perCornerStability;
    } else {
      for (int i = 0; i < 4; ++i) {
        state.perCornerStability[i] =
            state.perCornerStability[i] +
            a * (raw.perCornerStability[i] - state.perCornerStability[i]);
      }
    }
    state.hasPerCornerStability = true;
  }
  state.lastClipsEdge = raw.clipsEdge;
  state.hasSamples = true;
  state.hasQuad = true;

  out.hasDocument = true;
  out.clipsEdge = raw.clipsEdge;
  out.coverageRatio = state.coverage;
  out.tiltDegrees = state.tilt;
  out.meanLuma = state.luma;
  out.blurScore = state.blur;
  out.quadStability = state.stability;
  out.interiorVariance = state.interior;
  out.glareRatio = state.glare;
  out.cornerVelocity = state.cornerVelocity;
  out.perCornerStability = state.perCornerStability;
  out.hasPerCornerStability = state.hasPerCornerStability;
  out.centerOffsetX = state.centerOffsetX;
  out.centerOffsetY = state.centerOffsetY;
  out.quad = {};
}

// Composite live-quality estimate in [0,1] surfaced to consumers via
// `frame_metrics.liveQualityScore`. Combines the four signals that matter
// most for capture-readiness:
//   - sharpness  (blurScore / minBlur, clipped to 1)
//   - exposure   (1 - normalised distance from a midtone luma)
//   - cleanliness (1 - glareRatio / maxGlareRatio, clipped to [0,1])
//   - steadiness  (1 - cornerVelocity / maxCornerVelocity, clipped to [0,1])
// Geometric mean rather than arithmetic so any single collapsing signal
// drags the score down (sharp-but-glaring shouldn't read as ~0.85).
float computeLiveQualityScore(const SmoothedMetrics& m,
                              const GuidanceConfig& c) {
  const float sharpness =
      c.minBlurScore > 0.0f ? std::min(m.blurScore / c.minBlurScore, 1.0f) : 0.0f;
  // Midtone target 140 — chosen to land between the dark floor (~60) and the
  // glare-prone ceiling (~220) so well-lit paper sits near 1.0.
  const float lumaSpan = 140.0f;
  const float lumaDist = std::abs(m.meanLuma - 140.0f) / lumaSpan;
  const float exposure = std::max(0.0f, 1.0f - lumaDist);
  const float cleanliness =
      c.maxGlareRatio > 0.0f
          ? std::max(0.0f, 1.0f - m.glareRatio / c.maxGlareRatio)
          : 1.0f;
  const float steadiness =
      c.maxCornerVelocity > 0.0f
          ? std::max(0.0f, 1.0f - m.cornerVelocity / c.maxCornerVelocity)
          : 1.0f;
  // Geometric mean — clamp factors so a single zero collapses smoothly rather
  // than producing NaN under sqrt chains.
  const float p = std::max(0.001f, sharpness) * std::max(0.001f, exposure) *
                  std::max(0.001f, cleanliness) *
                  std::max(0.001f, steadiness);
  // 4th-root via two sqrts.
  return std::sqrt(std::sqrt(p));
}

// Returns kHoldSteady when no hard failure applies but stability is below the
// promotion floor; returns FrameState::kReady-equivalent (i.e. the caller's
// "all good" sentinel) when every check passes — we represent that as
// kReady from the caller's POV but the *commit* stage gates final promotion
// on `goodStreak`.
//
// State-aware exit margins mirror the Dart classifier exactly.
FrameState firstFailure(const SmoothedMetrics& m,
                        const GuidanceConfig& c,
                        FrameState current,
                        bool& outAllPassed) {
  outAllPassed = false;
  const float loose = 1.0f + c.exitMargin;
  const float tight = 1.0f - c.exitMargin;

  // Occlusion is first — a finger on the quad corrupts every other metric.
  if (m.hasPerCornerStability) {
    const float occlusionFloor =
        (current == FrameState::kOccluded)
            ? c.minPerCornerStability * (1.0f - c.exitMargin)
            : c.minPerCornerStability;
    for (int i = 0; i < 4; ++i) {
      if (m.perCornerStability[i] < occlusionFloor) {
        return FrameState::kOccluded;
      }
    }
  }

  const float minLuma = (current == FrameState::kTooDark)
                            ? c.minMeanLuma * loose
                            : c.minMeanLuma;
  if (m.meanLuma < minLuma) return FrameState::kTooDark;

  // Glare uses a dedicated, wider exit margin — glare is bursty and clears
  // with a 1° camera shift, so keep the state from sticking when it stops.
  const float maxGlare =
      (current == FrameState::kGlare)
          ? c.maxGlareRatio * (1.0f + c.glareExitMargin)
          : c.maxGlareRatio;
  if (m.glareRatio > maxGlare) return FrameState::kGlare;

  if (m.clipsEdge) {
    // `edgeClipBlocking` only controls whether a clipping quad gets its own
    // hint state. When false, fall through to tooClose so v1.0 behaviour is
    // preserved on a drop-in upgrade.
    if (c.edgeClipBlocking) return FrameState::kEdgeClipped;
    return FrameState::kTooClose;
  }
  const float maxCov = (current == FrameState::kTooClose)
                           ? c.maxCoverageRatio * tight
                           : c.maxCoverageRatio;
  if (m.coverageRatio > maxCov) return FrameState::kTooClose;

  const float minCov = (current == FrameState::kTooFar)
                           ? c.minCoverageRatio * loose
                           : c.minCoverageRatio;
  if (m.coverageRatio < minCov) return FrameState::kTooFar;

  const float maxTilt = (current == FrameState::kTooSkewed)
                            ? c.maxTiltDegrees * tight
                            : c.maxTiltDegrees;
  if (m.tiltDegrees > maxTilt) return FrameState::kTooSkewed;

  const float minBlur = (current == FrameState::kBlurry)
                            ? c.minBlurScore * loose
                            : c.minBlurScore;
  if (m.blurScore < minBlur) return FrameState::kBlurry;

  const float maxVel = (current == FrameState::kHandShake)
                           ? c.maxCornerVelocity * (1.0f + c.exitMargin)
                           : c.maxCornerVelocity;
  if (m.cornerVelocity > maxVel) return FrameState::kHandShake;

  outAllPassed = true;
  return FrameState::kNoDocument;  // sentinel — caller must check outAllPassed
}

// While accumulating good frames toward `ready` but not yet there, hold on
// the previous non-ready failure if any, else fall back to `blurry`.
FrameState holdingState(FrameState current) {
  if (current == FrameState::kReady) return FrameState::kReady;
  if (current == FrameState::kNoDocument) return FrameState::kBlurry;
  return current;
}

void commit(FrameState next, const GuidanceConfig& c, GuidanceState& s) {
  if (next == s.current) {
    s.framesAtState += 1;
    return;
  }
  const bool isTerminal = (next == FrameState::kNoDocument) ||
                          (s.current == FrameState::kNoDocument) ||
                          (next == FrameState::kReady) ||
                          (s.current == FrameState::kReady);
  if (isTerminal || priority(next) < priority(s.current) ||
      s.framesAtState >= c.minDwellFrames) {
    s.current = next;
    s.framesAtState = 1;
  } else {
    s.framesAtState += 1;
  }
}

}  // namespace

FrameState classify(const FrameMetrics& raw,
                    const GuidanceConfig& config,
                    GuidanceState& state,
                    SmoothedMetrics* out_smoothed) {
  SmoothedMetrics local{};
  smooth(raw, config, state, local);
  // Compute the opaque live-quality score on smoothed inputs and stash it on
  // the smoother state so a future no-document frame doesn't drop the last
  // good value to zero (handled inside `smooth`). The Dart side passes this
  // through verbatim — see `SupyDocumentMetricsSmoother._liveQualityScore`.
  if (local.hasDocument) {
    state.liveQualityScore = computeLiveQualityScore(local, config);
  }
  local.liveQualityScore = state.liveQualityScore;
  if (out_smoothed) *out_smoothed = local;

  // Mirror the Dart classifier's hasUsableDoc gate: a quad with too-low
  // interior variance (laptop screen showing a flat image) folds into
  // noDocument so the FSM doesn't surface holdSteady on a non-document.
  const bool hasUsableDoc =
      local.hasDocument && local.interiorVariance >= config.interiorVarianceFloor;
  if (!hasUsableDoc) {
    state.goodStreak = 0;
    state.missingStreak += 1;
    FrameState next = FrameState::kNoDocument;
    if (state.missingStreak <= config.lostDocumentGraceFrames &&
        state.current != FrameState::kNoDocument) {
      next = state.current;
    }
    commit(next, config, state);
    return state.current;
  }
  state.missingStreak = 0;

  bool allPassed = false;
  const FrameState failing =
      firstFailure(local, config, state.current, allPassed);
  if (!allPassed) {
    state.goodStreak = 0;
    commit(failing, config, state);
    return state.current;
  }

  // All hard failures pass — but if the document sits too far off-center,
  // prompt a recenter before letting it settle toward ready. Disabled when
  // maxCenterOffset is non-positive (Dart's centerGuidanceEnabled == false
  // sentinel). While already in kOffCenter, relax the threshold by exitMargin
  // so the prompt doesn't flicker as the user nudges it back across the band.
  if (config.maxCenterOffset > 0.0f) {
    const float centerCeiling =
        (state.current == FrameState::kOffCenter)
            ? config.maxCenterOffset * (1.0f + config.exitMargin)
            : config.maxCenterOffset;
    if (std::abs(local.centerOffsetX) > centerCeiling ||
        std::abs(local.centerOffsetY) > centerCeiling) {
      state.goodStreak = 0;
      commit(FrameState::kOffCenter, config, state);
      return state.current;
    }
  }

  // All hard failures pass — require quad stability before promoting to
  // ready. While in holdSteady relax the floor by exitMargin to dampen jitter.
  const float stabilityFloor =
      (state.current == FrameState::kHoldSteady)
          ? config.readyStabilityFloor * (1.0f - config.exitMargin)
          : config.readyStabilityFloor;
  if (local.quadStability < stabilityFloor) {
    state.goodStreak = 0;
    commit(FrameState::kHoldSteady, config, state);
    return state.current;
  }

  state.goodStreak += 1;
  const int framesNeeded = (state.current == FrameState::kHoldSteady)
                               ? config.holdSteadyFrames
                               : config.readyStableFrames;
  if (state.goodStreak >= framesNeeded) {
    commit(FrameState::kReady, config, state);
    return state.current;
  }
  commit(holdingState(state.current), config, state);
  return state.current;
}

}  // namespace supy::scanner::document
