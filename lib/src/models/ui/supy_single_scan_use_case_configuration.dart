import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Configuration for the **single-scan** use case — Scanbot's
/// `SingleScanningMode`.
///
/// When [confirmationSheetEnabled] is `true`, the embedded scanner pauses on
/// the first valid detection and shows a bottom sheet asking the user to
/// accept or retry. When `false`, the first detection is returned
/// immediately (drop-in behaviour for callers migrating from Scanbot's
/// `SingleScanningMode` with confirmation disabled).
@immutable
class SupySingleScanUseCaseConfiguration {
  /// Creates a single-scan use case configuration.
  const SupySingleScanUseCaseConfiguration({
    this.confirmationSheetEnabled = true,
    this.title,
    this.showBarcodeFormat = true,
    this.showRawValue = true,
    this.confirmButtonText,
    this.retryButtonText,
    this.sheetBackgroundColor,
    this.titleColor,
    this.bodyColor,
    this.confirmButtonBackgroundColor,
    this.confirmButtonForegroundColor,
    this.retryButtonForegroundColor,
  });

  /// When `false`, the first detection is returned without showing the
  /// confirmation sheet.
  final bool confirmationSheetEnabled;

  /// Title rendered at the top of the confirmation sheet. Resolves to the
  /// string bundle's `barcodeDetected` when null.
  final String? title;

  /// Whether the symbology name is rendered as a chip on the sheet.
  final bool showBarcodeFormat;

  /// Whether the raw decoded value is rendered on the sheet.
  final bool showRawValue;

  /// Label on the primary (accept) button. Resolves to the string bundle's
  /// `submit` when null.
  final String? confirmButtonText;

  /// Label on the secondary (retry) button. Resolves to the string bundle's
  /// `retry` when null.
  final String? retryButtonText;

  /// Sheet background fill. Resolves to the palette `surface` when null.
  final Color? sheetBackgroundColor;

  /// Color of the [title] text. Resolves to the palette `onSurface` when null.
  final Color? titleColor;

  /// Color of the body text (raw value, format chip). Resolves to the palette
  /// `onSurfaceVariant` when null.
  final Color? bodyColor;

  /// Primary button fill. Resolves to the palette `primary` when null.
  final Color? confirmButtonBackgroundColor;

  /// Primary button label color. Resolves to the palette `onPrimary` when null.
  final Color? confirmButtonForegroundColor;

  /// Secondary (retry) button label color. The retry button renders as a
  /// text button without a fill. Resolves to the palette `onSurface` when null.
  final Color? retryButtonForegroundColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupySingleScanUseCaseConfiguration &&
          other.confirmationSheetEnabled == confirmationSheetEnabled &&
          other.title == title &&
          other.showBarcodeFormat == showBarcodeFormat &&
          other.showRawValue == showRawValue &&
          other.confirmButtonText == confirmButtonText &&
          other.retryButtonText == retryButtonText &&
          other.sheetBackgroundColor == sheetBackgroundColor &&
          other.titleColor == titleColor &&
          other.bodyColor == bodyColor &&
          other.confirmButtonBackgroundColor == confirmButtonBackgroundColor &&
          other.confirmButtonForegroundColor == confirmButtonForegroundColor &&
          other.retryButtonForegroundColor == retryButtonForegroundColor;

  @override
  int get hashCode => Object.hash(
    confirmationSheetEnabled,
    title,
    showBarcodeFormat,
    showRawValue,
    confirmButtonText,
    retryButtonText,
    sheetBackgroundColor,
    titleColor,
    bodyColor,
    confirmButtonBackgroundColor,
    confirmButtonForegroundColor,
    retryButtonForegroundColor,
  );

  @override
  String toString() =>
      'SupySingleScanUseCaseConfiguration('
      'confirmationSheetEnabled: $confirmationSheetEnabled, '
      'title: $title)';
}
