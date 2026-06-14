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
}) {
  return SupyDocumentFrameMetrics(
    quad: quad,
    coverageRatio: coverageRatio,
    tiltDegrees: tiltDegrees,
    meanLuma: meanLuma,
    blurScore: blurScore,
    clipsEdge: clipsEdge,
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

    test('lostDocumentGraceFrames holds last state across detector misses',
        () {
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
      expect(
        config.colorFor(SupyDocumentFrameState.ready),
        config.readyColor,
      );
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
