import XCTest

@testable import supy_scanner

/// Pins the Swift → Obj-C++ → C++ marshalling for the document guidance
/// classifier. Ports a representative subset of the Dart fixture in
/// `test/document/supy_document_state_machine_test.dart`; the host gtest
/// already pins C++ ↔ Dart parity, so together they close the loop end-to-end.
///
/// These assert the *bridge* produces the same `GuidanceFrameState` sequence as
/// Dart for the same metric stream — not that the algorithm is correct (that's
/// the gtest's job).
final class SupyGuidanceClassifierTests: XCTestCase {

  /// A frame that passes every gate. Defaults mirror `_goodFrame` in the Dart
  /// fixture so failure cases flip exactly one field.
  private func goodFrame(
    coverageRatio: Float = 0.6,
    tiltDegrees: Float = 5.0,
    meanLuma: Float = 140.0,
    blurScore: Float = 200.0,
    clipsEdge: Bool = false,
    quadStability: Float = 1.0,
    interiorVariance: Float = 50.0,
    glareRatio: Float = 0.0,
    cornerVelocity: Float = 0.0,
    centerOffsetX: Float = 0.0,
    centerOffsetY: Float = 0.0,
    perCornerStability: [Float] = [0.95, 0.95, 0.95, 0.95]
  ) -> GuidanceFrameMetrics {
    return GuidanceFrameMetrics(
      hasDocument: true,
      clipsEdge: clipsEdge,
      coverageRatio: coverageRatio,
      tiltDegrees: tiltDegrees,
      meanLuma: meanLuma,
      blurScore: blurScore,
      quadStability: quadStability,
      interiorVariance: interiorVariance,
      glareRatio: glareRatio,
      cornerVelocity: cornerVelocity,
      centerOffsetX: centerOffsetX,
      centerOffsetY: centerOffsetY,
      perCornerStability: perCornerStability
    )
  }

  /// Config that reacts to raw values (no EMA blunting) for single-frame
  /// preemption assertions — mirrors the Dart tests' `smoothingAlpha: 1.0`.
  private var rawConfig: GuidanceConfig {
    var c = GuidanceConfig()
    c.smoothingAlpha = 1.0
    return c
  }

  func testStartsAtNoDocument() {
    let classifier = GuidanceClassifier()
    let result = classifier.classify(
      GuidanceFrameMetrics(
        hasDocument: false, clipsEdge: false,
        coverageRatio: 0, tiltDegrees: 0, meanLuma: 0, blurScore: 0,
        quadStability: 0, interiorVariance: 0
      ),
      config: rawConfig
    )
    XCTAssertEqual(result.state, .noDocument)
  }

  func testReadyRequiresConsecutiveGoodFrames() {
    var config = rawConfig
    config.readyStableFrames = 3
    let classifier = GuidanceClassifier()

    let first = classifier.classify(goodFrame(), config: config)
    let second = classifier.classify(goodFrame(), config: config)
    XCTAssertNotEqual(first.state, .ready)
    XCTAssertNotEqual(second.state, .ready)

    let third = classifier.classify(goodFrame(), config: config)
    XCTAssertEqual(third.state, .ready)
  }

  func testTooDarkWinsOverOtherFailures() {
    let classifier = GuidanceClassifier()
    let result = classifier.classify(
      goodFrame(coverageRatio: 0.05, tiltDegrees: 40, meanLuma: 10, blurScore: 5),
      config: rawConfig
    )
    XCTAssertEqual(result.state, .tooDark)
  }

  func testLowCoverageTooFar() {
    let classifier = GuidanceClassifier()
    let result = classifier.classify(goodFrame(coverageRatio: 0.10), config: rawConfig)
    XCTAssertEqual(result.state, .tooFar)
  }

  func testLowBlurScoreBlurry() {
    let classifier = GuidanceClassifier()
    let result = classifier.classify(goodFrame(blurScore: 10), config: rawConfig)
    XCTAssertEqual(result.state, .blurry)
  }

  func testGlareAboveThreshold() {
    let classifier = GuidanceClassifier()
    let result = classifier.classify(goodFrame(glareRatio: 0.20), config: rawConfig)
    XCTAssertEqual(result.state, .glare)
  }

  func testOccludedWhenCornerBelowFloor() {
    let classifier = GuidanceClassifier()
    let result = classifier.classify(
      goodFrame(perCornerStability: [0.95, 0.95, 0.10, 0.95]),
      config: rawConfig
    )
    XCTAssertEqual(result.state, .occluded)
  }

  func testHandShakeOnHighCornerVelocity() {
    let classifier = GuidanceClassifier()
    let result = classifier.classify(goodFrame(cornerVelocity: 0.10), config: rawConfig)
    XCTAssertEqual(result.state, .handShake)
  }

  func testEdgeClippedWhenBlockingEnabled() {
    var config = rawConfig
    config.edgeClipBlocking = true
    let classifier = GuidanceClassifier()
    let result = classifier.classify(goodFrame(clipsEdge: true), config: config)
    XCTAssertEqual(result.state, .edgeClipped)
  }

  func testResetClearsHysteresis() {
    var config = rawConfig
    config.readyStableFrames = 1
    let classifier = GuidanceClassifier()

    let ready = classifier.classify(goodFrame(), config: config)
    XCTAssertEqual(ready.state, .ready)

    classifier.reset()

    // After reset, ready needs the stable-frame count from zero again.
    config.readyStableFrames = 2
    let firstAfter = classifier.classify(goodFrame(), config: config)
    XCTAssertNotEqual(firstAfter.state, .ready)
    let secondAfter = classifier.classify(goodFrame(), config: config)
    XCTAssertEqual(secondAfter.state, .ready)
  }

  func testEmptyPerCornerArrayHoldsPriorJudgement() {
    // A frame with no per-corner signal must not crash and must not be read as
    // occluded — the length-0 contract tells the classifier to hold prior.
    var config = rawConfig
    config.readyStableFrames = 1
    let classifier = GuidanceClassifier()
    var metrics = goodFrame()
    metrics.perCornerStability = []
    XCTAssertFalse(metrics.hasPerCornerStability)
    let result = classifier.classify(metrics, config: config)
    XCTAssertEqual(result.state, .ready)
  }

  func testOffCenterHorizontalHeldBeforeReady() {
    // Framing passes but the quad sits well right of center (0.5 >> the 0.12
    // default maxCenterOffset) — must surface .offCenter, not promote to ready.
    let classifier = GuidanceClassifier()
    let result = classifier.classify(goodFrame(centerOffsetX: 0.5), config: rawConfig)
    XCTAssertEqual(result.state, .offCenter)
  }

  func testOffCenterVerticalHeldBeforeReady() {
    let classifier = GuidanceClassifier()
    let result = classifier.classify(goodFrame(centerOffsetY: -0.5), config: rawConfig)
    XCTAssertEqual(result.state, .offCenter)
  }

  func testCenteredFrameDoesNotTripOffCenter() {
    // A small offset inside maxCenterOffset must reach ready, not .offCenter.
    var config = rawConfig
    config.readyStableFrames = 1
    let classifier = GuidanceClassifier()
    let result = classifier.classify(
      goodFrame(centerOffsetX: 0.05, centerOffsetY: 0.05),
      config: config
    )
    XCTAssertEqual(result.state, .ready)
  }

  func testOffCenterDisabledWhenMaxCenterOffsetNonPositive() {
    // maxCenterOffset <= 0 is the centerGuidanceEnabled == false sentinel:
    // off-center framing is ignored and the frame promotes to ready.
    var config = rawConfig
    config.readyStableFrames = 1
    config.maxCenterOffset = -1.0
    let classifier = GuidanceClassifier()
    let result = classifier.classify(goodFrame(centerOffsetX: 0.5), config: config)
    XCTAssertEqual(result.state, .ready)
  }
}
