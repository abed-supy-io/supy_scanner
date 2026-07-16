import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// Debug HUD overlay for the example app.
///
/// Wraps a [child] in a [Stack] and, when [visible] is true, paints a
/// bottom-anchored panel showing the most recent [SupyLogRecord]s captured by
/// a delegating [SupyLogSink].
///
/// Off by default — host apps installing this widget must pass `initialVisible:
/// true` explicitly, or flip the toggle returned via the AppBar action helper.
///
/// Lives in the example app (not the library) so consumers can copy/paste it
/// into their own dev tooling without pulling Material into `lib/`.
class SupyDebugHud extends StatefulWidget {
  const SupyDebugHud({
    super.key,
    required this.child,
    this.initialVisible = false,
    this.maxRecords = 200,
  });

  final Widget child;
  final bool initialVisible;
  final int maxRecords;

  /// Lookup helper so AppBar actions can flip visibility without a
  /// GlobalKey shotgun.
  static SupyDebugHudController? of(BuildContext context) =>
      context.findAncestorStateOfType<_SupyDebugHudState>();

  @override
  State<SupyDebugHud> createState() => _SupyDebugHudState();
}

/// Public surface of the HUD state — toggle/clear hooks for AppBar buttons.
abstract class SupyDebugHudController {
  bool get visible;
  void toggle();
  void clear();
}

class _SupyDebugHudState extends State<SupyDebugHud>
    implements SupyDebugHudController {
  late final _HudSink _sink;
  SupyLogSink? _previousSink;
  bool _visible = false;

  @override
  bool get visible => _visible;

  @override
  void initState() {
    super.initState();
    _visible = widget.initialVisible;
    _sink = _HudSink(
      delegate: SupyLog.sink,
      maxRecords: widget.maxRecords,
    );
    _previousSink = SupyLog.installSink(_sink);
  }

  @override
  void dispose() {
    final restore = _previousSink;
    if (restore != null && identical(SupyLog.sink, _sink)) {
      SupyLog.installSink(restore);
    }
    _sink.dispose();
    super.dispose();
  }

  @override
  void toggle() => setState(() => _visible = !_visible);

  @override
  void clear() => _sink.clear();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_visible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _HudPanel(sink: _sink, onClear: clear, onClose: toggle),
            ),
          ),
      ],
    );
  }
}

class _HudSink extends SupyLogSink {
  _HudSink({required this.delegate, required this.maxRecords});

  final SupyLogSink delegate;
  final int maxRecords;
  final ValueNotifier<List<SupyLogRecord>> records =
      ValueNotifier<List<SupyLogRecord>>(const <SupyLogRecord>[]);

  @override
  void emit(SupyLogRecord record) {
    delegate.emit(record);
    final current = records.value;
    final next = <SupyLogRecord>[...current, record];
    if (next.length > maxRecords) {
      next.removeRange(0, next.length - maxRecords);
    }
    records.value = next;
  }

  void clear() => records.value = const <SupyLogRecord>[];

  void dispose() => records.dispose();
}

class _HudPanel extends StatelessWidget {
  const _HudPanel({
    required this.sink,
    required this.onClear,
    required this.onClose,
  });

  final _HudSink sink;
  final VoidCallback onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'SupyLog HUD',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  const _TierOverridePicker(),
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.cleaning_services,
                        color: Colors.white70, size: 18),
                    onPressed: onClear,
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 18),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Flexible(
              child: ValueListenableBuilder<List<SupyLogRecord>>(
                valueListenable: sink.records,
                builder: (context, records, _) {
                  if (records.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No records yet. Exercise a scan flow.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[records.length - 1 - index];
                      return _HudRow(record: record);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HudRow extends StatelessWidget {
  const _HudRow({required this.record});

  final SupyLogRecord record;

  @override
  Widget build(BuildContext context) {
    final color = switch (record.level) {
      SupyLogLevel.debug => Colors.white60,
      SupyLogLevel.info => Colors.lightBlueAccent,
      SupyLogLevel.warn => Colors.amberAccent,
      SupyLogLevel.error => Colors.redAccent,
    };
    final prefix = switch (record.level) {
      SupyLogLevel.debug => 'D',
      SupyLogLevel.info => 'I',
      SupyLogLevel.warn => 'W',
      SupyLogLevel.error => 'E',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: Colors.white,
            height: 1.25,
          ),
          children: [
            TextSpan(
              text: '$prefix/${record.tag} ',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            TextSpan(text: record.message),
            if (record.error != null)
              TextSpan(
                text: '\n  cause: ${record.error}',
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}

/// Debug-only tier override popup. Surfaces `SupyScannerChannel.debugForceTier`
/// so engineers can pin a tier to reproduce tier-low behaviour on a flagship
/// (or vice versa). The Dart wrapper is a no-op in release builds and the
/// native side is FLAG_DEBUGGABLE / `#if DEBUG` gated.
class _TierOverridePicker extends StatefulWidget {
  const _TierOverridePicker();

  @override
  State<_TierOverridePicker> createState() => _TierOverridePickerState();
}

class _TierOverridePickerState extends State<_TierOverridePicker> {
  SupyDeviceTier? _selected;

  @override
  Widget build(BuildContext context) {
    final label = switch (_selected) {
      SupyDeviceTier.high => 'HIGH',
      SupyDeviceTier.mid => 'MID',
      SupyDeviceTier.low => 'LOW',
      _ => 'AUTO',
    };
    return PopupMenuButton<SupyDeviceTier?>(
      tooltip: 'Force device tier',
      initialValue: _selected,
      onSelected: (tier) async {
        await SupyScannerChannel.instance.debugForceTier(tier);
        if (!mounted) return;
        setState(() => _selected = tier);
      },
      itemBuilder: (_) => const <PopupMenuEntry<SupyDeviceTier?>>[
        PopupMenuItem(value: null, child: Text('Auto (clear override)')),
        PopupMenuItem(value: SupyDeviceTier.high, child: Text('Force HIGH')),
        PopupMenuItem(value: SupyDeviceTier.mid, child: Text('Force MID')),
        PopupMenuItem(value: SupyDeviceTier.low, child: Text('Force LOW')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'tier:$label',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// Stand-in to keep `kDebugMode` reachable without importing foundation
/// elsewhere — wraps [SupyDebugHud] only when debug-mode is on. In release
/// builds it returns [child] verbatim so the HUD path is tree-shaken away.
class SupyDebugHudScope extends StatelessWidget {
  const SupyDebugHudScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;
    return SupyDebugHud(child: child);
  }
}
