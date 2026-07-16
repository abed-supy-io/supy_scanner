import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Visual style for the AR bounding-box overlay rendered over the camera
/// preview. Mirrors Scanbot's `BarcodePolygonStyle` + label style.
@immutable
class SupyArOverlayConfiguration {
  /// Creates an AR overlay configuration.
  const SupyArOverlayConfiguration({
    this.enabled = true,
    this.strokeColor = const Color(0xFF1F8A4C),
    this.fillColor = const Color(0x331F8A4C),
    this.strokeWidth = 2.0,
    this.cornerRadius = 6.0,
    this.showLabel = true,
    this.labelBackgroundColor = const Color(0xCC000000),
    this.labelTextColor = const Color(0xFFFFFFFF),
    this.labelTextSize = 12.0,
  }) : assert(strokeWidth >= 0, 'strokeWidth must be non-negative'),
       assert(cornerRadius >= 0, 'cornerRadius must be non-negative'),
       assert(labelTextSize > 0, 'labelTextSize must be > 0');

  /// Master switch. When false the overlay paints nothing.
  final bool enabled;

  /// Box outline color.
  final Color strokeColor;

  /// Box fill color (typically a translucent variant of [strokeColor]).
  final Color fillColor;

  /// Outline width in logical pixels.
  final double strokeWidth;

  /// Rounded-corner radius in logical pixels.
  final double cornerRadius;

  /// Whether to paint a small label chip with the barcode's `rawValue`.
  final bool showLabel;

  /// Label chip background fill.
  final Color labelBackgroundColor;

  /// Label text color.
  final Color labelTextColor;

  /// Label font size.
  final double labelTextSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyArOverlayConfiguration &&
          other.enabled == enabled &&
          other.strokeColor == strokeColor &&
          other.fillColor == fillColor &&
          other.strokeWidth == strokeWidth &&
          other.cornerRadius == cornerRadius &&
          other.showLabel == showLabel &&
          other.labelBackgroundColor == labelBackgroundColor &&
          other.labelTextColor == labelTextColor &&
          other.labelTextSize == labelTextSize;

  @override
  int get hashCode => Object.hash(
    enabled,
    strokeColor,
    fillColor,
    strokeWidth,
    cornerRadius,
    showLabel,
    labelBackgroundColor,
    labelTextColor,
    labelTextSize,
  );

  @override
  String toString() =>
      'SupyArOverlayConfiguration('
      'enabled: $enabled, strokeWidth: $strokeWidth, showLabel: $showLabel)';
}
