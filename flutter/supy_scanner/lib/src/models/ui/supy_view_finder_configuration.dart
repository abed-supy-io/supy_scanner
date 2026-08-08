import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Aspect ratio for the scanner view-finder rectangle.
///
/// Mirrors Scanbot's `AspectRatio(width, height)`. Width and height are
/// unit-less ratio components — `SupyAspectRatio(16, 9)` and
/// `SupyAspectRatio(160, 90)` are equivalent.
@immutable
class SupyAspectRatio {
  /// Creates a ratio with the given unit-less components. Both must be > 0.
  const SupyAspectRatio(this.width, this.height)
    : assert(width > 0, 'aspect width must be > 0'),
      assert(height > 0, 'aspect height must be > 0');

  /// Width component of the ratio.
  final double width;

  /// Height component of the ratio.
  final double height;

  /// Convenience: ratio as a single number (`width / height`).
  double get value => width / height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyAspectRatio &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'SupyAspectRatio($width:$height)';
}

/// Visual style for the finder rectangle border. Currently only the cornered
/// style ships — additional styles (full border, dashed, etc.) can be added
/// as additional const subtypes without breaking callers.
@immutable
sealed class SupyFinderStyle {
  const SupyFinderStyle();
}

/// Scanbot-style cornered finder: only the four corner brackets are drawn,
/// not a full rectangle. [strokeWidth] is in logical pixels.
@immutable
class SupyFinderCorneredStyle extends SupyFinderStyle {
  /// Creates a cornered finder style.
  const SupyFinderCorneredStyle({
    this.strokeColor,
    this.strokeWidth = 3.0,
    this.cornerLength = 24.0,
    this.cornerRadius = 4.0,
  }) : assert(strokeWidth > 0, 'strokeWidth must be > 0'),
       assert(cornerLength > 0, 'cornerLength must be > 0'),
       assert(cornerRadius >= 0, 'cornerRadius must be >= 0');

  /// Color of the corner brackets. Resolves to the palette `primary` when null.
  final Color? strokeColor;

  /// Stroke width of the corner brackets, in logical pixels.
  final double strokeWidth;

  /// Length of each corner bracket arm, in logical pixels.
  final double cornerLength;

  /// Inner-corner radius — applied as a rounded join between the two arms of
  /// each bracket. 0 = sharp L-shape.
  final double cornerRadius;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyFinderCorneredStyle &&
          other.strokeColor == strokeColor &&
          other.strokeWidth == strokeWidth &&
          other.cornerLength == cornerLength &&
          other.cornerRadius == cornerRadius;

  @override
  int get hashCode =>
      Object.hash(strokeColor, strokeWidth, cornerLength, cornerRadius);

  @override
  String toString() =>
      'SupyFinderCorneredStyle(color: $strokeColor, stroke: $strokeWidth, '
      'arm: $cornerLength, radius: $cornerRadius)';
}

/// Configuration for the camera-preview view-finder rectangle and its border.
///
/// Mirrors Scanbot's `BarcodeScannerScreenConfiguration.viewFinder`.
@immutable
class SupyViewFinderConfiguration {
  /// Creates a view-finder config. Defaults match Scanbot's RTU UI:
  /// visible, 16:9 finder, cyan cornered brackets.
  const SupyViewFinderConfiguration({
    this.visible = true,
    this.aspectRatio = const SupyAspectRatio(16, 9),
    this.style = const SupyFinderCorneredStyle(),
  });

  /// Whether the finder is drawn over the camera preview.
  final bool visible;

  /// Finder rectangle aspect ratio.
  final SupyAspectRatio aspectRatio;

  /// Border style for the finder rectangle.
  final SupyFinderStyle style;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyViewFinderConfiguration &&
          other.visible == visible &&
          other.aspectRatio == aspectRatio &&
          other.style == style;

  @override
  int get hashCode => Object.hash(visible, aspectRatio, style);

  @override
  String toString() =>
      'SupyViewFinderConfiguration(visible: $visible, '
      'aspectRatio: $aspectRatio, style: $style)';
}
