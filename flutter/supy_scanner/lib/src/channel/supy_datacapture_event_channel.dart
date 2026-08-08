import 'package:flutter/services.dart';

import '../models/ocr/supy_recognized_text.dart';
import '../models/supy_scan_error.dart';
import 'supy_scanner_channel.dart';

/// Events streamed from a per-view EventChannel during live text-pattern
/// (generic data-capture) scanning.
///
/// Same split as the document `frame_metrics` stream: the native side runs OCR
/// per frame and ships the recognized-text geometry; the Dart
/// `SupyTextPatternMatcher` runs the caller's patterns over it. Native side is
/// wired by the `datacapture` PlatformView; this is the contract it emits
/// against.
sealed class SupyDataCaptureEvent {
  /// Const constructor for subclasses.
  const SupyDataCaptureEvent();

  /// Parses a raw event map from the platform channel.
  factory SupyDataCaptureEvent.fromMap(Map<Object?, Object?> map) {
    final type = map['type'] as String?;
    switch (type) {
      case 'frame_text':
        return SupyDataCaptureFrameEvent(text: SupyRecognizedText.fromMap(map));
      case 'preview_started':
        return SupyDataCapturePreviewStartedEvent(
          flashAvailable: (map['flashAvailable'] as bool?) ?? false,
        );
      case 'error':
        return SupyDataCaptureErrorEvent(
          error: SupyScanError(
            code: SupyScanErrorCode.fromWire(map['code'] as String?),
            message:
                (map['message'] as String?) ?? 'Unknown data-capture error',
          ),
        );
      default:
        return SupyDataCaptureErrorEvent(
          error: SupyScanError(
            code: SupyScanErrorCode.unknown,
            message: 'Unrecognized data-capture event type: $type',
          ),
        );
    }
  }
}

/// One frame's worth of recognized text from the native OCR analyzer.
class SupyDataCaptureFrameEvent extends SupyDataCaptureEvent {
  /// Creates a frame-text event.
  const SupyDataCaptureFrameEvent({required this.text});

  /// The recognized-text tree for this frame, to feed into
  /// `SupyTextPatternMatcher.match`.
  final SupyRecognizedText text;
}

/// Emitted once the native camera preview has actually started rendering.
class SupyDataCapturePreviewStartedEvent extends SupyDataCaptureEvent {
  /// Creates a preview-started event.
  const SupyDataCapturePreviewStartedEvent({required this.flashAvailable});

  /// `true` when the active camera has a torch / flash unit.
  final bool flashAvailable;
}

/// A native error reported via the data-capture EventChannel.
class SupyDataCaptureErrorEvent extends SupyDataCaptureEvent {
  /// Creates an error event.
  const SupyDataCaptureErrorEvent({required this.error});

  /// The wrapped scanner error.
  final SupyScanError error;
}

/// Builds a per-view [EventChannel] for the live text-pattern scanner.
///
/// The native side opens
/// `io.supy.scanner/v1/datacapture/<viewId>/events` as the EventChannel for
/// each `SupyTextPatternScannerView` PlatformView.
EventChannel supyDataCaptureEventChannel(int viewId) {
  return EventChannel(
    'io.supy.scanner/$kSupyScannerChannelVersion/datacapture/$viewId/events',
  );
}

/// Convenience: maps raw EventChannel payloads to typed [SupyDataCaptureEvent]s.
Stream<SupyDataCaptureEvent> supyDataCaptureEventStream(int viewId) {
  return supyDataCaptureEventChannel(viewId).receiveBroadcastStream().map((
    event,
  ) {
    if (event is Map) {
      return SupyDataCaptureEvent.fromMap(event.cast<Object?, Object?>());
    }
    return const SupyDataCaptureErrorEvent(
      error: SupyScanError(
        code: SupyScanErrorCode.unknown,
        message: 'Unexpected non-map event payload from native channel',
      ),
    );
  });
}
