import 'package:flutter/services.dart';

import '../models/supy_document_frame_metrics.dart';
import '../models/supy_document_frame_state.dart';
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
          nativeState: _nativeStateFromWire(map['state']),
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

  /// Maps a raw `state` ordinal from the native payload to a
  /// [SupyDocumentFrameState] via the wire-stable index, or `null` when the
  /// platform did not classify this frame (Dart-FSM path). Out-of-range
  /// ordinals fall through to `null` so a stale native build can't crash the
  /// consumer — the Dart state machine then takes over.
  static SupyDocumentFrameState? _nativeStateFromWire(Object? raw) {
    if (raw is! int) return null;
    if (raw < 0 || raw >= kSupyDocumentFrameStateWireIndex.length) return null;
    return kSupyDocumentFrameStateWireIndex[raw];
  }
}

/// One frame's worth of measurements from the native detector.
class SupyDocumentFrameMetricsEvent extends SupyDocumentEvent {
  /// Creates a metrics event.
  const SupyDocumentFrameMetricsEvent({required this.metrics, this.nativeState});

  /// The metrics payload to feed into the state machine.
  final SupyDocumentFrameMetrics metrics;

  /// The frame classification computed natively (C++ `GuidanceClassifier`),
  /// when the platform classifies on-device. `null` means the platform sent
  /// raw metrics only and the Dart [SupyDocumentStateMachine] should classify.
  /// iOS embedded view emits this; Android embedded view does not yet.
  final SupyDocumentFrameState? nativeState;
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
