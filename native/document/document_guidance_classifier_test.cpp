// Host-side tests for the C++ document guidance classifier.
//
// These pin the classifier's transitions against the same semantics the Dart
// `SupyDocumentStateMachine` enforces. If you change one without the other,
// the standalone-launcher native path will diverge from the PlatformView
// Flutter path and users will see different hint text in the two flows.

#include <gtest/gtest.h>

#include "document_guidance_classifier.h"

namespace doc = supy::scanner::document;

namespace {

doc::FrameMetrics goodFrame() {
  // All thresholds comfortably satisfied: large doc, head-on, bright, sharp,
  // stable, high interior variance.
  doc::FrameMetrics m{};
  m.hasDocument = true;
  m.clipsEdge = false;
  m.coverageRatio = 0.60f;
  m.tiltDegrees = 2.0f;
  m.meanLuma = 180.0f;
  m.blurScore = 200.0f;
  m.quadStability = 0.95f;
  m.interiorVariance = 50.0f;
  return m;
}

doc::FrameState run(doc::GuidanceState& s,
                    const doc::GuidanceConfig& c,
                    const doc::FrameMetrics& m,
                    int n) {
  doc::FrameState last = s.current;
  for (int i = 0; i < n; ++i) last = doc::classify(m, c, s, nullptr);
  return last;
}

}  // namespace

TEST(GuidanceClassifier, StartsAtNoDocument) {
  doc::GuidanceState s{};
  EXPECT_EQ(s.current, doc::FrameState::kNoDocument);
}

TEST(GuidanceClassifier, MissingDocumentStaysNoDocument) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics empty{};
  EXPECT_EQ(run(s, c, empty, 10), doc::FrameState::kNoDocument);
}

TEST(GuidanceClassifier, GoodFramesEventuallyReachReady) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  // Need readyStableFrames consecutive passes — alpha smoothing means the
  // first few frames may not cross the stability floor, so allow extras.
  const doc::FrameState last = run(s, c, goodFrame(), 30);
  EXPECT_EQ(last, doc::FrameState::kReady);
}

TEST(GuidanceClassifier, DarkSceneReportsTooDark) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics m = goodFrame();
  m.meanLuma = 20.0f;
  EXPECT_EQ(run(s, c, m, 10), doc::FrameState::kTooDark);
}

TEST(GuidanceClassifier, ClippedEdgeReportsTooClose) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics m = goodFrame();
  m.clipsEdge = true;
  EXPECT_EQ(run(s, c, m, 10), doc::FrameState::kTooClose);
}

TEST(GuidanceClassifier, OverCoverageReportsTooClose) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics m = goodFrame();
  m.coverageRatio = 0.95f;
  EXPECT_EQ(run(s, c, m, 10), doc::FrameState::kTooClose);
}

TEST(GuidanceClassifier, UnderCoverageReportsTooFar) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics m = goodFrame();
  m.coverageRatio = 0.10f;
  EXPECT_EQ(run(s, c, m, 10), doc::FrameState::kTooFar);
}

TEST(GuidanceClassifier, HighTiltReportsTooSkewed) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics m = goodFrame();
  m.tiltDegrees = 45.0f;
  EXPECT_EQ(run(s, c, m, 10), doc::FrameState::kTooSkewed);
}

TEST(GuidanceClassifier, LowSharpnessReportsBlurry) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics m = goodFrame();
  m.blurScore = 10.0f;
  EXPECT_EQ(run(s, c, m, 10), doc::FrameState::kBlurry);
}

TEST(GuidanceClassifier, LowStabilityHoldsSteady) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics m = goodFrame();
  m.quadStability = 0.40f;  // below readyStabilityFloor
  EXPECT_EQ(run(s, c, m, 20), doc::FrameState::kHoldSteady);
}

TEST(GuidanceClassifier, LowInteriorVarianceFoldsIntoNoDocument) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics m = goodFrame();
  m.interiorVariance = 1.0f;  // below interiorVarianceFloor (5.0)
  EXPECT_EQ(run(s, c, m, 10), doc::FrameState::kNoDocument);
}

TEST(GuidanceClassifier, LostDocumentGraceHoldsPriorState) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  // Drive to ready.
  run(s, c, goodFrame(), 30);
  ASSERT_EQ(s.current, doc::FrameState::kReady);
  // Drop detection for less than grace frames — state must hold.
  doc::FrameMetrics empty{};
  for (int i = 0; i < c.lostDocumentGraceFrames; ++i) {
    doc::classify(empty, c, s, nullptr);
  }
  EXPECT_EQ(s.current, doc::FrameState::kReady);
  // One more miss exceeds grace — degrades to noDocument.
  doc::classify(empty, c, s, nullptr);
  EXPECT_EQ(s.current, doc::FrameState::kNoDocument);
}

TEST(GuidanceClassifier, HigherPriorityPreemptsImmediately) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  // Settle into blurry (priority 5).
  doc::FrameMetrics blurry = goodFrame();
  blurry.blurScore = 10.0f;
  run(s, c, blurry, 10);
  ASSERT_EQ(s.current, doc::FrameState::kBlurry);
  // tooDark (priority 1) must preempt without waiting for dwell.
  doc::FrameMetrics dark = goodFrame();
  dark.meanLuma = 20.0f;
  doc::classify(dark, c, s, nullptr);
  EXPECT_EQ(s.current, doc::FrameState::kTooDark);
}

TEST(GuidanceClassifier, ExitMarginPreventsBouncing) {
  // tooFar with coverage just below threshold: bumping coverage to exactly
  // the entry threshold should NOT exit tooFar until it passes the relaxed
  // (loose) threshold.
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::FrameMetrics far = goodFrame();
  far.coverageRatio = 0.10f;
  run(s, c, far, 10);
  ASSERT_EQ(s.current, doc::FrameState::kTooFar);

  // Move to the entry boundary (0.30) — exit threshold is 0.30 * 1.10 = 0.33.
  doc::FrameMetrics border = goodFrame();
  border.coverageRatio = 0.31f;
  // Run a few frames to let EMA approach the new value.
  for (int i = 0; i < 8; ++i) doc::classify(border, c, s, nullptr);
  EXPECT_EQ(s.current, doc::FrameState::kTooFar);
}

TEST(GuidanceClassifier, ResetReturnsToNoDocument) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  run(s, c, goodFrame(), 30);
  ASSERT_EQ(s.current, doc::FrameState::kReady);
  s.reset();
  EXPECT_EQ(s.current, doc::FrameState::kNoDocument);
  EXPECT_EQ(s.framesAtState, 0);
  EXPECT_FALSE(s.hasSamples);
}

TEST(GuidanceClassifier, SmoothedMetricsPopulated) {
  doc::GuidanceConfig c{};
  doc::GuidanceState s{};
  doc::SmoothedMetrics out{};
  doc::classify(goodFrame(), c, s, &out);
  EXPECT_TRUE(out.hasDocument);
  EXPECT_GT(out.coverageRatio, 0.0f);
  EXPECT_GT(out.meanLuma, 0.0f);
}
