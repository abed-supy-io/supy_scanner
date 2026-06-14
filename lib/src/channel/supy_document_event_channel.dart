import 'package:flutter/services.dart';

import '../models/supy_document_frame_metrics.dart';
import '../models/supy_scan_error.dart';
import 'supy_scanner_channel.dart';

/// Events streamed from a per-view EventChannel during embedded document
/// scanning.
///
/// Mirrors the barcode `SupyScannerEvent` shape so consumers can build
/// uniformly. Native side has not been wired yet — this is the contract the
/// upcoming `SupyDocumentScannerView` PlatformView will emit against.
sealed class SupyDocumentEvent {
  /// Const constructor for subclasses.
  const SupyDocumentEvent();

  /// Parses a raw event map from the platform channel.
  factory SupyDocumentEvent.fromMap(Map<Object?, Object?> map) {
    final type = map['type'] as String?;
    switch (type) {
      case 'frame_metrics':
        return SupyDocumentFrameMetricsEvent(
          metrics: SupyDocumentFrameMetrics.fromMap(map),
        );
      case 'preview_started':
        return SupyDocumentPreviewStartedEvent(
          flashAvailable: (map['flashAvailable'] as bool?) ?? false,
        );
      case 'error':
        return SupyDocumentErrorEvent(
          error: SupyScanError(
            code: SupyScanErrorCode.fromWire(map['code'] as String?),
            message:
                (map['message'] as String?) ?? 'Unknown document scanner error',
          ),
        );
      default:
        return SupyDocumentErrorEvent(
          error: SupyScanError(
            code: SupyScanErrorCode.unknown,
            message: 'Unrecognized document event type: $type',
          ),
        );
    }
  }
}

/// One frame's worth of measurements from the native detector.
class SupyDocumentFrameMetricsEvent extends SupyDocumentEvent {
  /// Creates a metrics event.
  const SupyDocumentFrameMetricsEvent({required this.metrics});

  /// The metrics payload to feed into the state machine.
  final SupyDocumentFrameMetrics metrics;
}

/// Emitted once the native camera preview has actually started rendering.
class SupyDocumentPreviewStartedEvent extends SupyDocumentEvent {
  /// Creates a preview-started event.
  const SupyDocumentPreviewStartedEvent({required this.flashAvailable});

  /// `true` when the active camera has a torch / flash unit.
  final bool flashAvailable;
}

/// A native error reported via the document EventChannel.
class SupyDocumentErrorEvent extends SupyDocumentEvent {
  /// Creates an error event.
  const SupyDocumentErrorEvent({required this.error});

  /// The wrapped scanner error.
  final SupyScanError error;
}

/// Builds a per-view [EventChannel] for the embedded document scanner.
///
/// The native side will open
/// `io.supy.scanner/v1/document/<viewId>/events` as the EventChannel for
/// each `SupyDocumentScannerView` PlatformView.
EventChannel supyDocumentEventChannel(int viewId) {
  return EventChannel(
    'io.supy.scanner/$kSupyScannerChannelVersion/document/$viewId/events',
  );
}

/// Convenience: maps raw EventChannel payloads to typed [SupyDocumentEvent]s.
Stream<SupyDocumentEvent> supyDocumentEventStream(int viewId) {
  return supyDocumentEventChannel(viewId).receiveBroadcastStream().map((event) {
    if (event is Map) {
      return SupyDocumentEvent.fromMap(event.cast<Object?, Object?>());
    }
    return const SupyDocumentErrorEvent(
      error: SupyScanError(
        code: SupyScanErrorCode.unknown,
        message: 'Unexpected non-map event payload from native channel',
      ),
    );
  });
}
