import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// One row of a pick-list passed into the **Find-and-Pick** use case —
/// Scanbot's `FindAndPickScanningMode`. The accumulator matches detected
/// barcodes against [rawValue] (case-sensitive) and tracks per-row
/// progress against [expectedCount].
@immutable
class SupyExpectedBarcode {
  /// Creates an expected pick-list entry.
  const SupyExpectedBarcode({
    required this.rawValue,
    this.expectedCount = 1,
    this.label,
  }) : assert(expectedCount >= 1, 'expectedCount must be >= 1');

  /// Exact `rawValue` to match against (case-sensitive).
  final String rawValue;

  /// How many scans of this payload are expected before the row is
  /// considered complete. Defaults to 1.
  final int expectedCount;

  /// Optional human-readable label rendered next to the payload in the
  /// sheet (e.g. SKU name).
  final String? label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyExpectedBarcode &&
          other.rawValue == rawValue &&
          other.expectedCount == expectedCount &&
          other.label == label;

  @override
  int get hashCode => Object.hash(rawValue, expectedCount, label);

  @override
  String toString() =>
      'SupyExpectedBarcode(rawValue: $rawValue, expectedCount: $expectedCount)';
}

/// Configuration for the **Find-and-Pick** use case — Scanbot's
/// `FindAndPickScanningMode`.
@immutable
class SupyFindAndPickUseCaseConfiguration {
  /// Creates a find-and-pick use case configuration.
  const SupyFindAndPickUseCaseConfiguration({
    this.expected = const <SupyExpectedBarcode>[],
    this.sheetTitle,
    this.initiallyCollapsed = false,
    this.submitButtonText,
    this.clearButtonText,
    this.allowUnexpected = false,
    this.sheetBackgroundColor,
    this.titleColor,
    this.bodyColor,
    this.matchedRowColor,
    this.pendingRowColor,
    this.submitButtonBackgroundColor,
    this.submitButtonForegroundColor,
    this.clearButtonForegroundColor,
  });

  /// The pick-list. Order is preserved in the sheet.
  final List<SupyExpectedBarcode> expected;

  /// Title rendered at the top of the collapsible sheet. Resolves to the
  /// string bundle's `pickList` when null.
  final String? sheetTitle;

  /// Whether the sheet starts collapsed (header only) or expanded.
  /// Find-and-pick defaults to expanded — operators need the list in view.
  final bool initiallyCollapsed;

  /// Label on the primary submit button. Resolves to the string bundle's
  /// `done` when null.
  final String? submitButtonText;

  /// Label on the secondary reset button. Resolves to the string bundle's
  /// `reset` when null.
  final String? clearButtonText;

  /// When true, detected payloads not in [expected] are still recorded
  /// (in an "Unexpected" section). When false, they are dropped silently.
  final bool allowUnexpected;

  /// Sheet background fill. Resolves to the palette `surface` when null.
  final Color? sheetBackgroundColor;

  /// Title color. Resolves to the palette `onSurface` when null.
  final Color? titleColor;

  /// Body color (used by the count line and unmatched-row payload). Resolves to
  /// the palette `onSurfaceVariant` when null.
  final Color? bodyColor;

  /// Color for fully-matched rows. Resolves to the palette `positive` when
  /// null.
  final Color? matchedRowColor;

  /// Color for pending rows. Resolves to the palette `onSurfaceVariant` when
  /// null.
  final Color? pendingRowColor;

  /// Primary button fill. Resolves to the palette `primary` when null.
  final Color? submitButtonBackgroundColor;

  /// Primary button label color. Resolves to the palette `onPrimary` when null.
  final Color? submitButtonForegroundColor;

  /// Secondary (reset) button label color. Resolves to the palette `onSurface`
  /// when null.
  final Color? clearButtonForegroundColor;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SupyFindAndPickUseCaseConfiguration) return false;
    if (other.expected.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (other.expected[i] != expected[i]) return false;
    }
    return other.sheetTitle == sheetTitle &&
        other.initiallyCollapsed == initiallyCollapsed &&
        other.submitButtonText == submitButtonText &&
        other.clearButtonText == clearButtonText &&
        other.allowUnexpected == allowUnexpected &&
        other.sheetBackgroundColor == sheetBackgroundColor &&
        other.titleColor == titleColor &&
        other.bodyColor == bodyColor &&
        other.matchedRowColor == matchedRowColor &&
        other.pendingRowColor == pendingRowColor &&
        other.submitButtonBackgroundColor == submitButtonBackgroundColor &&
        other.submitButtonForegroundColor == submitButtonForegroundColor &&
        other.clearButtonForegroundColor == clearButtonForegroundColor;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(expected),
    sheetTitle,
    initiallyCollapsed,
    submitButtonText,
    clearButtonText,
    allowUnexpected,
    sheetBackgroundColor,
    titleColor,
    bodyColor,
    matchedRowColor,
    pendingRowColor,
    submitButtonBackgroundColor,
    submitButtonForegroundColor,
    clearButtonForegroundColor,
  );

  @override
  String toString() =>
      'SupyFindAndPickUseCaseConfiguration('
      'expected: ${expected.length} rows, '
      'allowUnexpected: $allowUnexpected)';
}
