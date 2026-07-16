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
    this.title = 'Barcode detected',
    this.showBarcodeFormat = true,
    this.showRawValue = true,
    this.confirmButtonText = 'Submit',
    this.retryButtonText = 'Retry',
    this.sheetBackgroundColor = const Color(0xFFFFFFFF),
    this.titleColor = const Color(0xFF000000),
    this.bodyColor = const Color(0xCC000000),
    this.confirmButtonBackgroundColor = const Color(0xFF000000),
    this.confirmButtonForegroundColor = const Color(0xFFFFFFFF),
    this.retryButtonForegroundColor = const Color(0xFF000000),
  });

  /// When `false`, the first detection is returned without showing the
  /// confirmation sheet.
  final bool confirmationSheetEnabled;

  /// Title rendered at the top of the confirmation sheet.
  final String title;

  /// Whether the symbology name is rendered as a chip on the sheet.
  final bool showBarcodeFormat;

  /// Whether the raw decoded value is rendered on the sheet.
  final bool showRawValue;

  /// Label on the primary (accept) button.
  final String confirmButtonText;

  /// Label on the secondary (retry) button.
  final String retryButtonText;

  /// Sheet background fill.
  final Color sheetBackgroundColor;

  /// Color of the [title] text.
  final Color titleColor;

  /// Color of the body text (raw value, format chip).
  final Color bodyColor;

  /// Primary button fill.
  final Color confirmButtonBackgroundColor;

  /// Primary button label color.
  final Color confirmButtonForegroundColor;

  /// Secondary (retry) button label color. The retry button renders as a
  /// text button without a fill.
  final Color retryButtonForegroundColor;

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
