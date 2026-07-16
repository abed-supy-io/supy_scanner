import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

class _RecordingSink extends SupyLogSink {
  _RecordingSink();
  final List<SupyLogRecord> records = <SupyLogRecord>[];

  @override
  void emit(SupyLogRecord record) => records.add(record);
}

void main() {
  group('SupyLog', () {
    tearDown(SupyLog.resetForTest);

    test('default sink is SupyDebugPrintLogSink', () {
      expect(SupyLog.sink, isA<SupyDebugPrintLogSink>());
    });

    test('installSink swaps the active sink and returns the previous one', () {
      final firstReplacement = _RecordingSink();
      final original = SupyLog.installSink(firstReplacement);
      expect(original, isA<SupyDebugPrintLogSink>());
      expect(SupyLog.sink, same(firstReplacement));

      final secondReplacement = _RecordingSink();
      final returned = SupyLog.installSink(secondReplacement);
      expect(returned, same(firstReplacement));
      expect(SupyLog.sink, same(secondReplacement));
    });

    test('emits one record per level with the right metadata', () {
      final sink = _RecordingSink();
      SupyLog.installSink(sink);

      SupyLog.debug('barcode', 'preview-ready');
      SupyLog.info('barcode', 'preview-started');
      SupyLog.warn('document', 'corner lost', error: 'soft');
      final st = StackTrace.current;
      SupyLog.error(
        'document',
        'capture failed',
        error: StateError('boom'),
        stackTrace: st,
      );

      expect(sink.records.map((r) => r.level).toList(), <SupyLogLevel>[
        SupyLogLevel.debug,
        SupyLogLevel.info,
        SupyLogLevel.warn,
        SupyLogLevel.error,
      ]);
      expect(sink.records[0].tag, 'barcode');
      expect(sink.records[0].message, 'preview-ready');
      expect(sink.records[2].error, 'soft');
      expect(sink.records[3].stackTrace, same(st));
      expect(sink.records[3].error, isA<StateError>());
    });

    test('SupyNullLogSink swallows everything', () {
      const sink = SupyNullLogSink();
      sink.emit(
        const SupyLogRecord(
          level: SupyLogLevel.error,
          tag: 't',
          message: 'm',
        ),
      );
      // no expectation — must not throw.
    });

    test('resetForTest restores the default sink', () {
      SupyLog.installSink(_RecordingSink());
      SupyLog.resetForTest();
      expect(SupyLog.sink, isA<SupyDebugPrintLogSink>());
    });

    test('SupyLogRecord.toString mentions level/tag/message', () {
      const r = SupyLogRecord(
        level: SupyLogLevel.warn,
        tag: 'document',
        message: 'corner lost',
      );
      expect(r.toString(), contains('warn'));
      expect(r.toString(), contains('document'));
      expect(r.toString(), contains('corner lost'));
    });
  });
}
