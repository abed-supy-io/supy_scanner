import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Counting strategy for the multi-scan use case. Mirrors Scanbot's
/// `MultipleScanningMode` modes.
enum SupyMultipleScanMode {
  /// Every detection increments the count; repeated scans of the same
  /// payload are accepted as long as they happen at least
  /// [SupyMultipleScanUseCaseConfiguration.countingRepeatDelay] apart.
  counting,

  /// A given `rawValue` is accepted at most once; subsequent detections of
  /// the same payload are ignored.
  unique,
}

/// Configuration for the **multi-scan** use case — Scanbot's
/// `MultipleScanningMode`.
@immutable
class SupyMultipleScanUseCaseConfiguration {
  /// Creates a multi-scan use case configuration.
  const SupyMultipleScanUseCaseConfiguration({
    this.mode = SupyMultipleScanMode.unique,
    this.countingRepeatDelay = const Duration(milliseconds: 1000),
    this.sheetTitle,
    this.initiallyCollapsed = true,
    this.submitButtonText,
    this.clearButtonText,
    this.sheetBackgroundColor,
    this.titleColor,
    this.bodyColor,
    this.submitButtonBackgroundColor,
    this.submitButtonForegroundColor,
    this.clearButtonForegroundColor,
  });

  /// Counting vs unique behaviour.
  final SupyMultipleScanMode mode;

  /// Debounce window for repeated scans in [SupyMultipleScanMode.counting].
  /// Ignored in [SupyMultipleScanMode.unique].
  final Duration countingRepeatDelay;

  /// Title rendered at the top of the collapsible sheet. Resolves to the
  /// string bundle's `itemsScanned` when null.
  final String? sheetTitle;

  /// Whether the sheet starts collapsed (header only) or expanded (header
  /// + scrollable list).
  final bool initiallyCollapsed;

  /// Label on the primary submit button. Resolves to the string bundle's
  /// `submit` when null.
  final String? submitButtonText;

  /// Label on the secondary clear button. Resolves to the string bundle's
  /// `clear` when null.
  final String? clearButtonText;

  /// Sheet background fill. Resolves to the palette `surface` when null.
  final Color? sheetBackgroundColor;

  /// Title color. Resolves to the palette `onSurface` when null.
  final Color? titleColor;

  /// Body / list-item color. Resolves to the palette `onSurfaceVariant` when
  /// null.
  final Color? bodyColor;

  /// Primary button fill. Resolves to the palette `primary` when null.
  final Color? submitButtonBackgroundColor;

  /// Primary button label color. Resolves to the palette `onPrimary` when null.
  final Color? submitButtonForegroundColor;

  /// Secondary (clear) button label color. Resolves to the palette `onSurface`
  /// when null.
  final Color? clearButtonForegroundColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyMultipleScanUseCaseConfiguration &&
          other.mode == mode &&
          other.countingRepeatDelay == countingRepeatDelay &&
          other.sheetTitle == sheetTitle &&
          other.initiallyCollapsed == initiallyCollapsed &&
          other.submitButtonText == submitButtonText &&
          other.clearButtonText == clearButtonText &&
          other.sheetBackgroundColor == sheetBackgroundColor &&
          other.titleColor == titleColor &&
          other.bodyColor == bodyColor &&
          other.submitButtonBackgroundColor == submitButtonBackgroundColor &&
          other.submitButtonForegroundColor == submitButtonForegroundColor &&
          other.clearButtonForegroundColor == clearButtonForegroundColor;

  @override
  int get hashCode => Object.hash(
    mode,
    countingRepeatDelay,
    sheetTitle,
    initiallyCollapsed,
    submitButtonText,
    clearButtonText,
    sheetBackgroundColor,
    titleColor,
    bodyColor,
    submitButtonBackgroundColor,
    submitButtonForegroundColor,
    clearButtonForegroundColor,
  );

  @override
  String toString() =>
      'SupyMultipleScanUseCaseConfiguration('
      'mode: ${mode.name}, '
      'countingRepeatDelay: ${countingRepeatDelay.inMilliseconds}ms)';
}
