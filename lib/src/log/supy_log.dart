import 'package:flutter/foundation.dart';

/// Severity of a [SupyLogRecord].
enum SupyLogLevel {
  /// Verbose diagnostics. Disabled in release.
  debug,

  /// Lifecycle events of interest (scan started, page captured).
  info,

  /// Recoverable anomaly the host may want to surface.
  warn,

  /// Failure that prevented the operation from completing.
  error,
}

/// Frozen log record emitted by anything inside `supy_scanner` that needs to
/// surface diagnostics.
///
/// Records are intentionally PII-free at the call site: barcode payloads, OCR
/// text, and file URIs MUST NOT be passed in [message] or [error]. See
/// `docs/SECURITY.md` §8.
@immutable
class SupyLogRecord {
  /// Construct an immutable record. [tag] groups related sites
  /// (e.g. `'barcode'`, `'document'`); [message] is engineering-controlled.
  const SupyLogRecord({
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  /// Severity of this record.
  final SupyLogLevel level;

  /// Subsystem tag (`'barcode'`, `'document'`, …).
  final String tag;

  /// Engineering-controlled message. Never include PII.
  final String message;

  /// Optional originating error.
  final Object? error;

  /// Optional stack trace; usually only attached to [SupyLogLevel.error].
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'SupyLogRecord($level, $tag, $message${error == null ? '' : ', $error'})';
}

/// Pluggable destination for [SupyLog] records.
///
/// Host apps can install their own sink (e.g. routing to Sentry / Crashlytics)
/// via [SupyLog.installSink]. The library never depends on a specific sink —
/// the default ([SupyDebugPrintLogSink]) is a no-op in release builds.
abstract class SupyLogSink {
  /// Subclasses must be `const`-constructible so they can be used in field
  /// initializers.
  const SupyLogSink();

  /// Consume a single record. Implementations MUST NOT throw.
  void emit(SupyLogRecord record);
}

/// Default sink: forwards to [debugPrint] in debug/profile builds, no-op in
/// release.
///
/// Chosen so that:
///   1. Library code is never coupled to `dart:io` (host may run in a Web
///      Worker / headless context),
///   2. Release builds emit nothing by default — matches the zero-telemetry
///      posture in `docs/SECURITY.md`.
class SupyDebugPrintLogSink extends SupyLogSink {
  /// Default sink constructor.
  const SupyDebugPrintLogSink();

  @override
  void emit(SupyLogRecord record) {
    if (kReleaseMode) return;
    final prefix = switch (record.level) {
      SupyLogLevel.debug => 'D',
      SupyLogLevel.info => 'I',
      SupyLogLevel.warn => 'W',
      SupyLogLevel.error => 'E',
    };
    debugPrint('[$prefix/${record.tag}] ${record.message}');
    final err = record.error;
    if (err != null) {
      debugPrint('  cause: $err');
    }
    final st = record.stackTrace;
    if (st != null && record.level == SupyLogLevel.error) {
      debugPrint('$st');
    }
  }
}

/// Drops every record. Useful in tests or in hosts that ship their own log
/// pipeline and want to silence the library entirely.
class SupyNullLogSink extends SupyLogSink {
  /// Const constructor — sink holds no state.
  const SupyNullLogSink();

  @override
  void emit(SupyLogRecord record) {}
}

/// Static facade used by everything inside `lib/` that needs to log.
///
/// ```dart
/// SupyLog.info('barcode', 'preview started');
/// SupyLog.error('document', 'scan failed', error: e, stackTrace: s);
/// ```
///
/// Tests can swap in a recording sink:
///
/// ```dart
/// final records = <SupyLogRecord>[];
/// SupyLog.installSink(_RecordingSink(records));
/// ```
class SupyLog {
  SupyLog._();

  static SupyLogSink _sink = const SupyDebugPrintLogSink();

  /// Replace the active sink. Returns the previously installed sink so tests
  /// can restore it.
  static SupyLogSink installSink(SupyLogSink sink) {
    final previous = _sink;
    _sink = sink;
    return previous;
  }

  /// Currently installed sink. Exposed for tests and host apps that want to
  /// wrap an existing sink (delegate-and-forward).
  static SupyLogSink get sink => _sink;

  /// Emit a [SupyLogLevel.debug] record.
  static void debug(String tag, String message) => _sink.emit(
        SupyLogRecord(
          level: SupyLogLevel.debug,
          tag: tag,
          message: message,
        ),
      );

  /// Emit a [SupyLogLevel.info] record.
  static void info(String tag, String message) => _sink.emit(
        SupyLogRecord(
          level: SupyLogLevel.info,
          tag: tag,
          message: message,
        ),
      );

  /// Emit a [SupyLogLevel.warn] record with an optional cause.
  static void warn(
    String tag,
    String message, {
    Object? error,
  }) =>
      _sink.emit(
        SupyLogRecord(
          level: SupyLogLevel.warn,
          tag: tag,
          message: message,
          error: error,
        ),
      );

  /// Emit a [SupyLogLevel.error] record with an optional cause + stack trace.
  static void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _sink.emit(
        SupyLogRecord(
          level: SupyLogLevel.error,
          tag: tag,
          message: message,
          error: error,
          stackTrace: stackTrace,
        ),
      );

  /// Resets the sink to [SupyDebugPrintLogSink]. Test-only.
  @visibleForTesting
  static void resetForTest() {
    _sink = const SupyDebugPrintLogSink();
  }
}
