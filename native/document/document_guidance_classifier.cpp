// document_guidance_classifier.cpp — see header for the contract.
//
// Direct port of lib/src/document/supy_document_state_machine.dart +
// supy_document_metrics_smoother.dart. Order of operations and threshold
// arithmetic match the Dart line-by-line so the host gtest fixture (which
// replays the same sequences that lib/test/.../ exercises) sees identical
// state transitions.

#include "document_guidance_classifier.h"

namespace supy::scanner::document {

namespace {

constexpr int kPriority[] = {
    /* kNoDocument */ 0,
    /* kTooDark    */ 1,
    /* kTooClose   */ 2,
    /* kTooFar     */ 3,
    /* kTooSkewed  */ 4,
    /* kBlurry     */ 5,
    /* kHoldSteady */ 6,
    /* kReady      */ 7,
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
    out.hasDocument = false;
    out.clipsEdge = false;
    out.coverageRatio = 0.0f;
    out.tiltDegrees = 0.0f;
    out.meanLuma = 0.0f;
    out.blurScore = 0.0f;
    out.quadStability = 0.0f;
    out.interiorVariance = 0.0f;
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
  out.quad = {};
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

  const float minLuma = (current == FrameState::kTooDark)
                            ? c.minMeanLuma * loose
                            : c.minMeanLuma;
  if (m.meanLuma < minLuma) return FrameState::kTooDark;

  if (m.clipsEdge) return FrameState::kTooClose;
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
