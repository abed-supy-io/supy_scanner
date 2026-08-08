import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

const _quad = <Offset>[
  Offset(0.1, 0.1),
  Offset(0.9, 0.1),
  Offset(0.9, 0.9),
  Offset(0.1, 0.9),
];

SupyDocumentFrameMetrics _goodFrame({
  List<Offset> quad = _quad,
  double coverageRatio = 0.6,
  double tiltDegrees = 5.0,
  double meanLuma = 140.0,
  double blurScore = 200.0,
  bool clipsEdge = false,
  // Task 3 added the stability + interior-variance gates. Default both to
  // comfortably-passing values so tests that pre-date the gates continue to
  // exercise the failure classification they were written for.
  double quadStability = 1.0,
  double interiorVariance = 50.0,
  // CQG additions. Defaults sit comfortably below the failure thresholds so
  // pre-CQG tests continue to exercise the failure they were written for.
  double glareRatio = 0.0,
  double cornerVelocity = 0.0,
  double centerOffsetX = 0.0,
  double centerOffsetY = 0.0,
  List<double> perCornerStability = const <double>[0.95, 0.95, 0.95, 0.95],
  double? liveQualityScore,
}) {
  return SupyDocumentFrameMetrics(
    quad: quad,
    coverageRatio: coverageRatio,
    tiltDegrees: tiltDegrees,
    meanLuma: meanLuma,
    blurScore: blurScore,
    clipsEdge: clipsEdge,
    quadStability: quadStability,
    interiorVariance: interiorVariance,
    glareRatio: glareRatio,
    cornerVelocity: cornerVelocity,
    centerOffsetX: centerOffsetX,
    centerOffsetY: centerOffsetY,
    perCornerStability: perCornerStability,
    liveQualityScore: liveQualityScore,
  );
}

void main() {
  group('SupyDocumentStateMachine', () {
    test('starts at noDocument', () {
      final sm = SupyDocumentStateMachine();
      expect(sm.state, SupyDocumentFrameState.noDocument);
    });

    test('empty quad -> noDocument once grace exhausted', () {
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          lostDocumentGraceFrames: 0,
        ),
      );
      final frame = sm.tick(const SupyDocumentFrameMetrics());
      expect(frame.state, SupyDocumentFrameState.noDocument);
      expect(frame.quad, isEmpty);
    });

    test('tooDark wins over every other failure', () {
      final sm = SupyDocumentStateMachine();
      final frame = sm.tick(
        _goodFrame(
          meanLuma: 10,
          coverageRatio: 0.05,
          tiltDegrees: 40,
          blurScore: 5,
        ),
      );
      expect(frame.state, SupyDocumentFrameState.tooDark);
    });

    test('clipsEdge -> tooClose even when coverage is normal', () {
      final sm = SupyDocumentStateMachine();
      final frame = sm.tick(_goodFrame(clipsEdge: true));
      expect(frame.state, SupyDocumentFrameState.tooClose);
    });

    test('low coverage -> tooFar', () {
      final sm = SupyDocumentStateMachine();
      final frame = sm.tick(_goodFrame(coverageRatio: 0.10));
      expect(frame.state, SupyDocumentFrameState.tooFar);
    });

    test('tilt > threshold -> tooSkewed', () {
      final sm = SupyDocumentStateMachine();
      final frame = sm.tick(_goodFrame(tiltDegrees: 35));
      expect(frame.state, SupyDocumentFrameState.tooSkewed);
    });

    test('low blur score -> blurry', () {
      final sm = SupyDocumentStateMachine();
      final frame = sm.tick(_goodFrame(blurScore: 10));
      expect(frame.state, SupyDocumentFrameState.blurry);
    });

    test('ready requires readyStableFrames consecutive good frames', () {
      const config = SupyDocumentGuidanceConfiguration(readyStableFrames: 3);
      final sm = SupyDocumentStateMachine(configuration: config);

      final first = sm.tick(_goodFrame());
      final second = sm.tick(_goodFrame());
      expect(first.state, isNot(SupyDocumentFrameState.ready));
      expect(second.state, isNot(SupyDocumentFrameState.ready));

      final third = sm.tick(_goodFrame());
      expect(third.state, SupyDocumentFrameState.ready);
      expect(third.framesAtState, 1);

      final fourth = sm.tick(_goodFrame());
      expect(fourth.state, SupyDocumentFrameState.ready);
      expect(fourth.framesAtState, 2);
    });

    test('a sustained bad signal resets the good streak', () {
      // With temporal smoothing, a single jittery frame is absorbed
      // (that's the point). A sustained signal flips classification.
      const config = SupyDocumentGuidanceConfiguration(
        readyStableFrames: 3,
        smoothingAlpha: 1.0, // disable EMA for this test's determinism
      );
      final sm = SupyDocumentStateMachine(configuration: config);

      sm.tick(_goodFrame());
      sm.tick(_goodFrame());
      final bad = sm.tick(_goodFrame(blurScore: 10));
      expect(bad.state, SupyDocumentFrameState.blurry);

      // Need readyStableFrames good frames again, not just one.
      final r1 = sm.tick(_goodFrame());
      expect(r1.state, isNot(SupyDocumentFrameState.ready));
      sm.tick(_goodFrame());
      final r3 = sm.tick(_goodFrame());
      expect(r3.state, SupyDocumentFrameState.ready);
    });

    test('lostDocumentGraceFrames holds last state across detector misses', () {
      const config = SupyDocumentGuidanceConfiguration(
        readyStableFrames: 1,
        lostDocumentGraceFrames: 2,
      );
      final sm = SupyDocumentStateMachine(configuration: config);

      final ready = sm.tick(_goodFrame());
      expect(ready.state, SupyDocumentFrameState.ready);

      final miss1 = sm.tick(const SupyDocumentFrameMetrics());
      final miss2 = sm.tick(const SupyDocumentFrameMetrics());
      expect(miss1.state, SupyDocumentFrameState.ready);
      expect(miss2.state, SupyDocumentFrameState.ready);

      final miss3 = sm.tick(const SupyDocumentFrameMetrics());
      expect(miss3.state, SupyDocumentFrameState.noDocument);
    });

    test('reset() clears all hysteresis state', () {
      const config = SupyDocumentGuidanceConfiguration(readyStableFrames: 1);
      final sm = SupyDocumentStateMachine(configuration: config);

      sm.tick(_goodFrame());
      expect(sm.state, SupyDocumentFrameState.ready);

      sm.reset();
      expect(sm.state, SupyDocumentFrameState.noDocument);

      // After reset, ready still requires the stable-frame count from zero.
      const harder = SupyDocumentGuidanceConfiguration(readyStableFrames: 2);
      sm.configuration = harder;
      final first = sm.tick(_goodFrame());
      expect(first.state, isNot(SupyDocumentFrameState.ready));
      final second = sm.tick(_goodFrame());
      expect(second.state, SupyDocumentFrameState.ready);
    });

    // ---- CQG: new states ----

    test('glareRatio above threshold -> glare', () {
      // smoothingAlpha=1.0 keeps the EMA from blunting the spike — we want to
      // assert the classifier reacts to the raw value, not to a 3-frame ramp.
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
        ),
      );
      final frame = sm.tick(_goodFrame(glareRatio: 0.20));
      expect(frame.state, SupyDocumentFrameState.glare);
    });

    test('any perCornerStability below floor -> occluded', () {
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
        ),
      );
      final frame = sm.tick(
        _goodFrame(perCornerStability: const [0.95, 0.95, 0.10, 0.95]),
      );
      expect(frame.state, SupyDocumentFrameState.occluded);
    });

    test('cornerVelocity above threshold -> handShake', () {
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
        ),
      );
      final frame = sm.tick(_goodFrame(cornerVelocity: 0.10));
      expect(frame.state, SupyDocumentFrameState.handShake);
    });

    test('clipsEdge with edgeClipBlocking=true -> edgeClipped', () {
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          edgeClipBlocking: true,
        ),
      );
      final frame = sm.tick(_goodFrame(clipsEdge: true));
      expect(frame.state, SupyDocumentFrameState.edgeClipped);
    });

    test('clipsEdge with edgeClipBlocking=false falls through to tooClose', () {
      final sm = SupyDocumentStateMachine();
      final frame = sm.tick(_goodFrame(clipsEdge: true));
      expect(frame.state, SupyDocumentFrameState.tooClose);
    });

    // ---- CQG: priority preemption among the new states ----

    test('occluded preempts tooDark', () {
      // Even a finger-occluded frame in a very dark scene reports occluded,
      // because occlusion invalidates every other measurement.
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
        ),
      );
      final frame = sm.tick(
        _goodFrame(
          meanLuma: 10,
          perCornerStability: const [0.10, 0.95, 0.95, 0.95],
        ),
      );
      expect(frame.state, SupyDocumentFrameState.occluded);
    });

    test('glare preempts edgeClipped', () {
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          edgeClipBlocking: true,
        ),
      );
      final frame = sm.tick(_goodFrame(glareRatio: 0.20, clipsEdge: true));
      expect(frame.state, SupyDocumentFrameState.glare);
    });

    test('edgeClipped preempts tooClose', () {
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          edgeClipBlocking: true,
        ),
      );
      final frame = sm.tick(_goodFrame(clipsEdge: true, coverageRatio: 0.95));
      expect(frame.state, SupyDocumentFrameState.edgeClipped);
    });

    test('blurry preempts handShake when both fire', () {
      final sm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
        ),
      );
      final frame = sm.tick(_goodFrame(blurScore: 10, cornerVelocity: 0.10));
      expect(frame.state, SupyDocumentFrameState.blurry);
    });

    // ---- CQG: exit-margin hysteresis on the new fields ----
    //
    // Exit-margin un-latching (widening the threshold while in-state so a
    // marginal frame clears the hint) lives on the native/iOS path and the C++
    // classifier — see `core/document/document_guidance_classifier_test.cpp`.
    // The Dart FSM does NOT un-latch via exit margin: `_holdingState()` re-applies
    // the prior failure label until `_goodStreak` reaches `readyStableFrames`.
    // This is one of the three documented Dart-FSM hysteresis quirks (ARCHITECTURE.md,
    // TODO.md CXD-IG2); the Android Dart-FSM fix is deferred to CXD-IG3. These
    // tests pin the current documented behaviour: a marginal frame that still
    // trips the entry threshold keeps the hint latched.

    test('glare holds at a ratio that still exceeds the entry threshold', () {
      // entry: 0.04. A ratio of 0.05 still trips entry, so the Dart FSM keeps
      // glare latched (no exit-margin un-latch on this path — CXD-IG3).
      const config = SupyDocumentGuidanceConfiguration(
        smoothingAlpha: 1.0,
        minDwellFrames: 0,
      );
      final sm = SupyDocumentStateMachine(configuration: config);
      sm.tick(_goodFrame(glareRatio: 0.20));
      expect(sm.state, SupyDocumentFrameState.glare);
      final held = sm.tick(_goodFrame(glareRatio: 0.05));
      expect(held.state, SupyDocumentFrameState.glare);
    });

    test('occluded holds at a stability that still trips the entry floor', () {
      // entry floor: 0.42. A corner at 0.39 still trips entry, so the Dart FSM
      // keeps occluded latched (no exit-margin un-latch on this path — CXD-IG3).
      const config = SupyDocumentGuidanceConfiguration(
        smoothingAlpha: 1.0,
        minDwellFrames: 0,
      );
      final sm = SupyDocumentStateMachine(configuration: config);
      sm.tick(_goodFrame(perCornerStability: const [0.95, 0.95, 0.10, 0.95]));
      expect(sm.state, SupyDocumentFrameState.occluded);
      final held = sm.tick(
        _goodFrame(perCornerStability: const [0.95, 0.95, 0.39, 0.95]),
      );
      expect(held.state, SupyDocumentFrameState.occluded);
    });

    test(
      'handShake holds at a velocity that still trips the entry ceiling',
      () {
        // entry: 0.035. Velocity 0.036 still trips entry, so the Dart FSM keeps
        // handShake latched (no exit-margin un-latch on this path — CXD-IG3).
        const config = SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          minDwellFrames: 0,
        );
        final sm = SupyDocumentStateMachine(configuration: config);
        sm.tick(_goodFrame(cornerVelocity: 0.10));
        expect(sm.state, SupyDocumentFrameState.handShake);
        final held = sm.tick(_goodFrame(cornerVelocity: 0.036));
        expect(held.state, SupyDocumentFrameState.handShake);
      },
    );

    test('framesAtState counts consecutive ticks at the same state', () {
      final sm = SupyDocumentStateMachine();
      final a = sm.tick(_goodFrame(coverageRatio: 0.1));
      final b = sm.tick(_goodFrame(coverageRatio: 0.1));
      final c = sm.tick(_goodFrame(coverageRatio: 0.1));
      expect(a.state, SupyDocumentFrameState.tooFar);
      expect(a.framesAtState, 1);
      expect(b.framesAtState, 2);
      expect(c.framesAtState, 3);
    });

    test('off-center framing holds offCenter before ready (horizontal)', () {
      // Framing otherwise passes but the quad sits well right of center
      // (0.5 >> the 0.12 default maxCenterOffset). Mirrors the C++ classifier.
      const config = SupyDocumentGuidanceConfiguration(smoothingAlpha: 1.0);
      final sm = SupyDocumentStateMachine(configuration: config);
      final frame = sm.tick(_goodFrame(centerOffsetX: 0.5));
      expect(frame.state, SupyDocumentFrameState.offCenter);
    });

    test('off-center framing holds offCenter before ready (vertical)', () {
      const config = SupyDocumentGuidanceConfiguration(smoothingAlpha: 1.0);
      final sm = SupyDocumentStateMachine(configuration: config);
      final frame = sm.tick(_goodFrame(centerOffsetY: -0.5));
      expect(frame.state, SupyDocumentFrameState.offCenter);
    });

    test('small centroid offset inside maxCenterOffset reaches ready', () {
      const config = SupyDocumentGuidanceConfiguration(
        smoothingAlpha: 1.0,
        readyStableFrames: 1,
      );
      final sm = SupyDocumentStateMachine(configuration: config);
      final frame = sm.tick(
        _goodFrame(centerOffsetX: 0.05, centerOffsetY: 0.05),
      );
      expect(frame.state, SupyDocumentFrameState.ready);
    });

    test(
      'off-center detection disabled when centerGuidanceEnabled is false',
      () {
        const config = SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          readyStableFrames: 1,
          centerGuidanceEnabled: false,
        );
        final sm = SupyDocumentStateMachine(configuration: config);
        final frame = sm.tick(_goodFrame(centerOffsetX: 0.5));
        expect(frame.state, SupyDocumentFrameState.ready);
      },
    );

    test('offCenter uses relaxed exit ceiling (quick-clear family)', () {
      // Mirrors the C++ OffCenterUsesRelaxedExitCeiling gtest: once in
      // offCenter the ceiling is raised to maxCenterOffset * (1 + exitMargin),
      // so an offset comfortably above it keeps the prompt up.
      const config = SupyDocumentGuidanceConfiguration(
        smoothingAlpha: 1.0,
        minDwellFrames: 0,
      );
      final sm = SupyDocumentStateMachine(configuration: config);
      sm.tick(_goodFrame(centerOffsetX: 0.5));
      expect(sm.state, SupyDocumentFrameState.offCenter);
      final still = sm.tick(_goodFrame(centerOffsetX: 0.20));
      expect(still.state, SupyDocumentFrameState.offCenter);
    });

    test('hand-held invoice sample reaches ready under relaxed defaults', () {
      // Regression for "invoice capture never locks onto page": the production
      // invoice flow routes through the generic default config on both
      // platforms. A phone held by hand over a sparse, mostly-white invoice
      // under indoor light produces this metrics profile — every value sits in
      // the band the pre-tuning gates rejected but a real, capturable frame
      // occupies. It must resolve to `ready`.
      SupyDocumentFrameMetrics invoiceSample() => _goodFrame(
        blurScore: 65, // hand-held softness, but legible
        quadStability: 0.68, // small sway
        interiorVariance: 4.0, // low-ink invoice, wide margins
        cornerVelocity: 0.028, // steady but not tripod-still
        perCornerStability: const [0.5, 0.5, 0.5, 0.5],
      );

      // No config argument — exercise the exact defaults the app ships with.
      const relaxed = SupyDocumentGuidanceConfiguration();
      final smRelaxed = SupyDocumentStateMachine();
      var frame = smRelaxed.tick(invoiceSample());
      for (var i = 0; i < relaxed.readyStableFrames; i++) {
        frame = smRelaxed.tick(invoiceSample());
      }
      expect(
        frame.state,
        SupyDocumentFrameState.ready,
        reason: 'relaxed defaults must let a hand-held invoice lock',
      );

      // Guard the direction of the fix: the pre-tuning thresholds would have
      // pinned this same frame to noDocument (interior variance below the old
      // 5.0 floor), so the outline never even highlighted.
      const strict = SupyDocumentGuidanceConfiguration(
        minBlurScore: 80.0,
        readyStabilityFloor: 0.75,
        interiorVarianceFloor: 5.0,
        maxCornerVelocity: 0.020,
        minPerCornerStability: 0.55,
      );
      final smStrict = SupyDocumentStateMachine(configuration: strict);
      var strictFrame = smStrict.tick(invoiceSample());
      for (var i = 0; i < strict.readyStableFrames + 2; i++) {
        strictFrame = smStrict.tick(invoiceSample());
      }
      expect(
        strictFrame.state,
        isNot(SupyDocumentFrameState.ready),
        reason: 'the old strict gates never locked this frame — the bug',
      );
    });
  });

  group('SupyDocumentGuidanceConfiguration', () {
    test('hintFor maps each state to a non-empty hint', () {
      const config = SupyDocumentGuidanceConfiguration();
      for (final state in SupyDocumentFrameState.values) {
        expect(
          config.hintFor(state),
          isNotEmpty,
          reason: 'missing hint for $state',
        );
      }
    });

    test('colorFor flips palette on ready', () {
      const config = SupyDocumentGuidanceConfiguration();
      expect(config.colorFor(SupyDocumentFrameState.ready), config.readyColor);
      expect(
        config.colorFor(SupyDocumentFrameState.tooFar),
        config.notReadyColor,
      );
    });

    test('value equality', () {
      const a = SupyDocumentGuidanceConfiguration();
      const b = SupyDocumentGuidanceConfiguration();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SupyDocumentFrameMetrics.fromMap', () {
    test('parses a well-formed payload', () {
      final metrics = SupyDocumentFrameMetrics.fromMap(const <Object?, Object?>{
        'quad': <Object?>[
          <Object?, Object?>{'x': 0.0, 'y': 0.0},
          <Object?, Object?>{'x': 1.0, 'y': 0.0},
          <Object?, Object?>{'x': 1.0, 'y': 1.0},
          <Object?, Object?>{'x': 0.0, 'y': 1.0},
        ],
        'coverageRatio': 0.5,
        'tiltDegrees': 3.5,
        'meanLuma': 120.0,
        'blurScore': 250.0,
        'clipsEdge': false,
      });
      expect(metrics.hasDocument, isTrue);
      expect(metrics.quad, hasLength(4));
      expect(metrics.coverageRatio, 0.5);
      expect(metrics.tiltDegrees, 3.5);
    });

    test('drops malformed quads', () {
      final metrics = SupyDocumentFrameMetrics.fromMap(const <Object?, Object?>{
        'quad': <Object?>[
          <Object?, Object?>{'x': 0.0, 'y': 0.0},
        ],
      });
      expect(metrics.hasDocument, isFalse);
      expect(metrics.quad, isEmpty);
    });
  });

  group('SupyDocumentEvent.fromMap', () {
    test('frame_metrics dispatches to the metrics variant', () {
      final event = SupyDocumentEvent.fromMap(<Object?, Object?>{
        'type': 'frame_metrics',
        'coverageRatio': 0.4,
      });
      expect(event, isA<SupyDocumentFrameMetricsEvent>());
      final metrics = (event as SupyDocumentFrameMetricsEvent).metrics;
      expect(metrics.coverageRatio, 0.4);
    });

    test('unknown type falls back to error', () {
      final event = SupyDocumentEvent.fromMap(<Object?, Object?>{
        'type': 'something_else',
      });
      expect(event, isA<SupyDocumentErrorEvent>());
    });
  });
}
