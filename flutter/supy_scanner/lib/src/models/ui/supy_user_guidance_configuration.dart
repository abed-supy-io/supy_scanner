import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// User-guidance card configuration — the hint that floats over the camera
/// preview to tell the user what to do ("Point the camera at a barcode").
///
/// Mirrors Scanbot's `userGuidance` config block.
@immutable
class SupyUserGuidanceConfiguration {
  /// Creates a user-guidance config. Defaults to a visible hint card with
  /// dark scrim background and white text.
  const SupyUserGuidanceConfiguration({
    this.visible = true,
    this.titleText,
    this.titleColor,
    this.backgroundFillColor,
    this.fontSize = 14.0,
  });

  /// Whether the guidance card is rendered.
  final bool visible;

  /// Hint text shown inside the card. Resolves to the string bundle's
  /// `barcodeGuidanceTitle` when null; pass `''` to render an empty card.
  final String? titleText;

  /// Foreground color of the hint text. Resolves to the palette `onSurface`
  /// when null.
  final Color? titleColor;

  /// Background fill color of the card (alpha allowed for scrim effect).
  /// Resolves to the palette `modalOverlay` when null.
  final Color? backgroundFillColor;

  /// Hint font size in logical pixels.
  final double fontSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyUserGuidanceConfiguration &&
          other.visible == visible &&
          other.titleText == titleText &&
          other.titleColor == titleColor &&
          other.backgroundFillColor == backgroundFillColor &&
          other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(
    visible,
    titleText,
    titleColor,
    backgroundFillColor,
    fontSize,
  );

  @override
  String toString() =>
      'SupyUserGuidanceConfiguration(visible: $visible, "$titleText")';
}
