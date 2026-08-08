import 'package:flutter/foundation.dart';

import '../models/supy_barcode.dart';
import '../models/ui/supy_find_and_pick_use_case_configuration.dart';

/// Per-expected-row progress in the find-and-pick accumulator.
@immutable
class SupyFindAndPickRow {
  /// Creates a progress row.
  const SupyFindAndPickRow({required this.expected, required this.foundCount})
    : assert(foundCount >= 0, 'foundCount must be >= 0');

  /// The pick-list entry this row tracks.
  final SupyExpectedBarcode expected;

  /// How many matching detections have been recorded so far.
  final int foundCount;

  /// Whether this row has reached its expected count.
  bool get isComplete => foundCount >= expected.expectedCount;

  /// Returns a copy with [foundCount] replaced.
  SupyFindAndPickRow withFound(int next) =>
      SupyFindAndPickRow(expected: expected, foundCount: next);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyFindAndPickRow &&
          other.expected == expected &&
          other.foundCount == foundCount;

  @override
  int get hashCode => Object.hash(expected, foundCount);

  @override
  String toString() =>
      'SupyFindAndPickRow(${expected.rawValue}: $foundCount/${expected.expectedCount})';
}

/// Accumulates barcode detections against a fixed pick-list.
///
/// Detections whose `rawValue` matches an expected row increment that row's
/// found count (capped at the row's `expectedCount`). When
/// [SupyFindAndPickUseCaseConfiguration.allowUnexpected] is true, detections
/// not in the pick-list are recorded under [unexpected]; otherwise they are
/// dropped.
class SupyFindAndPickAccumulator extends ChangeNotifier {
  /// Creates a find-and-pick accumulator.
  SupyFindAndPickAccumulator({required this.config})
    : _rows = {
        for (final e in config.expected)
          e.rawValue: SupyFindAndPickRow(expected: e, foundCount: 0),
      },
      _order = config.expected.map((e) => e.rawValue).toList(growable: false);

  /// Active configuration.
  final SupyFindAndPickUseCaseConfiguration config;

  final Map<String, SupyFindAndPickRow> _rows;
  final List<String> _order;
  final Map<String, SupyBarcode> _unexpected = {};

  /// Pick-list rows in the configuration's original order.
  List<SupyFindAndPickRow> get rows =>
      List.unmodifiable(_order.map((k) => _rows[k]!));

  /// Unexpected detections (only populated when
  /// [SupyFindAndPickUseCaseConfiguration.allowUnexpected] is true).
  List<SupyBarcode> get unexpected => List.unmodifiable(_unexpected.values);

  /// Number of pick-list rows that have reached their expected count.
  int get completedRowCount => _rows.values.where((r) => r.isComplete).length;

  /// Total pick-list rows.
  int get totalRowCount => _rows.length;

  /// True iff every pick-list row is complete.
  bool get isComplete =>
      _rows.isNotEmpty && _rows.values.every((r) => r.isComplete);

  /// Offers a fresh detection. Returns true iff the detection was applied
  /// (matched a pending row, or recorded as unexpected).
  bool offer(SupyBarcode barcode) {
    final key = barcode.rawValue;
    final row = _rows[key];
    if (row != null) {
      if (row.isComplete) return false;
      _rows[key] = row.withFound(row.foundCount + 1);
      notifyListeners();
      return true;
    }
    if (!config.allowUnexpected) return false;
    if (_unexpected.containsKey(key)) return false;
    _unexpected[key] = barcode;
    notifyListeners();
    return true;
  }

  /// Resets all rows to zero and clears unexpected detections.
  void clear() {
    if (_unexpected.isEmpty && _rows.values.every((r) => r.foundCount == 0)) {
      return;
    }
    for (final k in _order) {
      _rows[k] = _rows[k]!.withFound(0);
    }
    _unexpected.clear();
    notifyListeners();
  }
}
