import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyDataCaptureEvent.fromMap', () {
    test('decodes a frame_text event into a recognized-text tree', () {
      final event = SupyDataCaptureEvent.fromMap(<Object?, Object?>{
        'type': 'frame_text',
        'fullText': 'HELLO',
        'blocks': <Object?>[
          <Object?, Object?>{
            'text': 'HELLO',
            'boundingBox': <Object?, Object?>{
              'left': 0.0,
              'top': 0.0,
              'width': 1.0,
              'height': 0.2,
            },
            'lines': <Object?>[
              <Object?, Object?>{
                'text': 'HELLO',
                'boundingBox': <Object?, Object?>{
                  'left': 0.0,
                  'top': 0.0,
                  'width': 1.0,
                  'height': 0.2,
                },
                'elements': <Object?>[],
              },
            ],
          },
        ],
      });
      expect(event, isA<SupyDataCaptureFrameEvent>());
      final frame = event as SupyDataCaptureFrameEvent;
      expect(frame.text.fullText, 'HELLO');
      expect(frame.text.blocks.single.lines.single.text, 'HELLO');
    });

    test('decodes a preview_started event', () {
      final event = SupyDataCaptureEvent.fromMap(<Object?, Object?>{
        'type': 'preview_started',
        'flashAvailable': true,
      });
      expect(event, isA<SupyDataCapturePreviewStartedEvent>());
      expect(
        (event as SupyDataCapturePreviewStartedEvent).flashAvailable,
        isTrue,
      );
    });

    test('decodes an error event', () {
      final event = SupyDataCaptureEvent.fromMap(<Object?, Object?>{
        'type': 'error',
        'code': 'permission_denied',
        'message': 'nope',
      });
      expect(event, isA<SupyDataCaptureErrorEvent>());
      final err = (event as SupyDataCaptureErrorEvent).error;
      expect(err.message, 'nope');
      expect(err.code, SupyScanErrorCode.permissionDenied);
    });

    test('an unrecognized type decodes to an error event', () {
      final event = SupyDataCaptureEvent.fromMap(<Object?, Object?>{
        'type': 'nonsense',
      });
      expect(event, isA<SupyDataCaptureErrorEvent>());
      expect(
        (event as SupyDataCaptureErrorEvent).error.code,
        SupyScanErrorCode.unknown,
      );
    });
  });
}
