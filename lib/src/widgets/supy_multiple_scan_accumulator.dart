import 'package:flutter/foundation.dart';

import '../models/supy_barcode.dart';
import '../models/ui/supy_multiple_scan_use_case_configuration.dart';

/// One row in the multi-scan accumulator. [count] is always 1 in
/// [SupyMultipleScanMode.unique].
@immutable
class SupyMultipleScanItem {
  /// Creates an accumulator item.
  const SupyMultipleScanItem({required this.barcode, required this.count})
    : assert(count >= 1, 'count must be >= 1');

  /// The decoded barcode (first-seen instance carries the row).
  final SupyBarcode barcode;

  /// Number of times this `rawValue` has been counted.
  final int count;

  /// Returns a copy with [count] replaced.
  SupyMultipleScanItem withCount(int next) =>
      SupyMultipleScanItem(barcode: barcode, count: next);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyMultipleScanItem &&
          other.barcode == barcode &&
          other.count == count;

  @override
  int get hashCode => Object.hash(barcode, count);

  @override
  String toString() => 'SupyMultipleScanItem(${barcode.rawValue} x$count)';
}

/// Accumulates barcode detections per the configured [SupyMultipleScanMode].
///
/// In `counting` mode, repeated detections of the same `rawValue` increment
/// the row's count, but only when separated by at least
/// [SupyMultipleScanUseCaseConfiguration.countingRepeatDelay]. In `unique`
/// mode, each `rawValue` is recorded at most once.
class SupyMultipleScanAccumulator extends ChangeNotifier {
  /// Creates an accumulator.
  SupyMultipleScanAccumulator({required this.config});

  /// Active configuration. Mutating mid-flight is not supported — build a
  /// new accumulator instead.
  final SupyMultipleScanUseCaseConfiguration config;

  final Map<String, SupyMultipleScanItem> _items = {};
  final Map<String, DateTime> _lastSeen = {};

  /// Items in insertion order.
  List<SupyMultipleScanItem> get items => List.unmodifiable(_items.values);

  /// Total count: sum of per-row counts in `counting`, row count in
  /// `unique`.
  int get totalCount {
    if (config.mode == SupyMultipleScanMode.unique) {
      return _items.length;
    }
    var sum = 0;
    for (final v in _items.values) {
      sum += v.count;
    }
    return sum;
  }

  /// Number of distinct payloads (always == [items].length).
  int get uniqueCount => _items.length;

  /// Offers a fresh detection to the accumulator. [now] is injectable so
  /// callers (and tests) can drive the debounce deterministically.
  void offer(SupyBarcode barcode, {required DateTime now}) {
    final key = barcode.rawValue;
    if (config.mode == SupyMultipleScanMode.unique) {
      if (_items.containsKey(key)) return;
      _items[key] = SupyMultipleScanItem(barcode: barcode, count: 1);
      notifyListeners();
      return;
    }
    // counting
    final last = _lastSeen[key];
    if (last != null && now.difference(last) < config.countingRepeatDelay) {
      return;
    }
    _lastSeen[key] = now;
    final existing = _items[key];
    _items[key] =
        existing == null
            ? SupyMultipleScanItem(barcode: barcode, count: 1)
            : existing.withCount(existing.count + 1);
    notifyListeners();
  }

  /// Drops all accumulated items.
  void clear() {
    if (_items.isEmpty && _lastSeen.isEmpty) return;
    _items.clear();
    _lastSeen.clear();
    notifyListeners();
  }
}
