import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/document/supy_document_state_machine.dart';
import 'package:supy_scanner/src/models/supy_document_frame_metrics.dart';
import 'package:supy_scanner/src/models/supy_document_frame_state.dart';
import 'package:supy_scanner/src/models/ui/supy_document_guidance_configuration.dart';

SupyDocumentFrameMetrics _good({
  double stability = 1.0,
  double interior = 50.0,
}) {
  return SupyDocumentFrameMetrics(
    quad: const [
      Offset(0.1, 0.1),
      Offset(0.9, 0.1),
      Offset(0.9, 0.9),
      Offset(0.1, 0.9),
    ],
    coverageRatio: 0.6,
    tiltDegrees: 2.0,
    meanLuma: 150.0,
    blurScore: 200.0,
    quadStability: stability,
    interiorVariance: interior,
  );
}

void main() {
  group('SupyDocumentStateMachine holdSteady', () {
    test('enters holdSteady when checks pass but stability is low', () {
      final fsm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          readyStableFrames: 1,
        ),
      );
      final frame = fsm.tick(_good(stability: 0.2));
      expect(frame.state, SupyDocumentFrameState.holdSteady);
    });

    test(
      'promotes holdSteady -> ready after holdSteadyFrames stable ticks',
      () {
        final fsm = SupyDocumentStateMachine(
          configuration: const SupyDocumentGuidanceConfiguration(
            smoothingAlpha: 1.0,
            readyStableFrames: 1,
            holdSteadyFrames: 3,
          ),
        );
        fsm.tick(_good(stability: 0.2));
        fsm.tick(_good(stability: 0.9));
        fsm.tick(_good(stability: 0.9));
        final frame = fsm.tick(_good(stability: 0.9));
        expect(frame.state, SupyDocumentFrameState.ready);
      },
    );

    test('rejects on low interiorVariance (screen-like surface)', () {
      final fsm = SupyDocumentStateMachine(
        configuration: const SupyDocumentGuidanceConfiguration(
          smoothingAlpha: 1.0,
          interiorVarianceFloor: 10.0,
        ),
      );
      final frame = fsm.tick(_good(interior: 1.0));
      expect(frame.state, SupyDocumentFrameState.noDocument);
    });
  });
}
