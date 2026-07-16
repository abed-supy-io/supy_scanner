import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyDocumentEvent.fromMap', () {
    test('decodes frame_metrics with a full quad', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'frame_metrics',
        'quad': <Map<Object?, Object?>>[
          <Object?, Object?>{'x': 0.1, 'y': 0.1},
          <Object?, Object?>{'x': 0.9, 'y': 0.1},
          <Object?, Object?>{'x': 0.9, 'y': 0.9},
          <Object?, Object?>{'x': 0.1, 'y': 0.9},
        ],
        'coverageRatio': 0.64,
        'tiltDegrees': 3.5,
        'meanLuma': 142.0,
        'blurScore': 220.0,
        'clipsEdge': false,
      });

      expect(event, isA<SupyDocumentFrameMetricsEvent>());
      final m = (event as SupyDocumentFrameMetricsEvent).metrics;
      expect(m.hasDocument, isTrue);
      expect(m.quad, hasLength(4));
      expect(m.quad.first, const Offset(0.1, 0.1));
      expect(m.coverageRatio, 0.64);
      expect(m.tiltDegrees, 3.5);
      expect(m.meanLuma, 142.0);
      expect(m.blurScore, 220.0);
      expect(m.clipsEdge, isFalse);
    });

    test('frame_metrics with missing fields uses defaults', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'frame_metrics',
      });

      final m = (event as SupyDocumentFrameMetricsEvent).metrics;
      expect(m.quad, isEmpty);
      expect(m.hasDocument, isFalse);
      expect(m.coverageRatio, 0.0);
      expect(m.tiltDegrees, 0.0);
      expect(m.meanLuma, 0.0);
      expect(m.blurScore, 0.0);
      expect(m.clipsEdge, isFalse);
    });

    test(
      'frame_metrics with malformed quad (wrong length) yields empty quad',
      () {
        final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
          'type': 'frame_metrics',
          'quad': <Map<Object?, Object?>>[
            <Object?, Object?>{'x': 0.1, 'y': 0.1},
            <Object?, Object?>{'x': 0.9, 'y': 0.1},
            <Object?, Object?>{'x': 0.9, 'y': 0.9},
          ],
        });

        final m = (event as SupyDocumentFrameMetricsEvent).metrics;
        expect(m.quad, isEmpty);
        expect(m.hasDocument, isFalse);
      },
    );

    test('frame_metrics drops quad points with missing x or y', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'frame_metrics',
        'quad': <Map<Object?, Object?>>[
          <Object?, Object?>{'x': 0.1, 'y': 0.1},
          <Object?, Object?>{'x': 0.9}, // missing y → dropped
          <Object?, Object?>{'x': 0.9, 'y': 0.9},
          <Object?, Object?>{'x': 0.1, 'y': 0.9},
        ],
      });

      // 3 valid points → not a complete quad → empty result.
      final m = (event as SupyDocumentFrameMetricsEvent).metrics;
      expect(m.quad, isEmpty);
    });

    test('frame_metrics accepts num types for coordinates (int + double)', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'frame_metrics',
        'quad': <Map<Object?, Object?>>[
          <Object?, Object?>{'x': 0, 'y': 0},
          <Object?, Object?>{'x': 1, 'y': 0},
          <Object?, Object?>{'x': 1, 'y': 1},
          <Object?, Object?>{'x': 0, 'y': 1},
        ],
        'coverageRatio': 1, // int → coerced to double
      });

      final m = (event as SupyDocumentFrameMetricsEvent).metrics;
      expect(m.quad, hasLength(4));
      expect(m.coverageRatio, 1.0);
    });

    test('frame_metrics carries no nativeState when state key is absent', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'frame_metrics',
      });

      expect((event as SupyDocumentFrameMetricsEvent).nativeState, isNull);
    });

    test('frame_metrics maps native state ordinal via the wire index', () {
      // Wire index 7 = ready, 8 = glare — distinct from the Dart enum
      // declaration order, which is exactly what the wire-index guards.
      final ready = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'frame_metrics',
        'state': 7,
      });
      final glare = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'frame_metrics',
        'state': 8,
      });

      expect(
        (ready as SupyDocumentFrameMetricsEvent).nativeState,
        SupyDocumentFrameState.ready,
      );
      expect(
        (glare as SupyDocumentFrameMetricsEvent).nativeState,
        SupyDocumentFrameState.glare,
      );
    });

    test('frame_metrics ignores an out-of-range native state ordinal', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'frame_metrics',
        'state': 99,
      });

      expect((event as SupyDocumentFrameMetricsEvent).nativeState, isNull);
    });

    test('decodes preview_started with flashAvailable=true', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'preview_started',
        'flashAvailable': true,
      });

      expect(event, isA<SupyDocumentPreviewStartedEvent>());
      expect((event as SupyDocumentPreviewStartedEvent).flashAvailable, isTrue);
    });

    test('preview_started with missing flashAvailable defaults to false', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'preview_started',
      });

      expect(
        (event as SupyDocumentPreviewStartedEvent).flashAvailable,
        isFalse,
      );
    });

    test('decodes error with mapped code', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'error',
        'code': 'permission_denied',
        'message': 'Camera denied',
      });

      expect(event, isA<SupyDocumentErrorEvent>());
      final err = (event as SupyDocumentErrorEvent).error;
      expect(err.code, SupyScanErrorCode.permissionDenied);
      expect(err.message, 'Camera denied');
    });

    test('error with missing message falls back to default copy', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'error',
        'code': 'camera_unavailable',
      });

      final err = (event as SupyDocumentErrorEvent).error;
      expect(err.code, SupyScanErrorCode.cameraUnavailable);
      expect(err.message, 'Unknown document scanner error');
    });

    test('error with unrecognized code maps to SupyScanErrorCode.unknown', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'error',
        'code': 'not_a_real_code',
        'message': 'oops',
      });

      expect(
        (event as SupyDocumentErrorEvent).error.code,
        SupyScanErrorCode.unknown,
      );
    });

    test('unknown event type yields error event with the bad type echoed', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'type': 'not_a_real_type',
      });

      final err = (event as SupyDocumentErrorEvent).error;
      expect(err.code, SupyScanErrorCode.unknown);
      expect(err.message, contains('not_a_real_type'));
    });

    test('missing type entirely yields error event', () {
      final event = SupyDocumentEvent.fromMap(const <Object?, Object?>{
        'foo': 'bar',
      });
      expect(event, isA<SupyDocumentErrorEvent>());
      expect(
        (event as SupyDocumentErrorEvent).error.code,
        SupyScanErrorCode.unknown,
      );
    });
  });

  group('supyDocumentEventChannel', () {
    test('channel name embeds the version and viewId under document/', () {
      final ch = supyDocumentEventChannel(42);
      expect(ch.name, 'io.supy.scanner/v1/document/42/events');
    });
  });
}
