import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Visibility/style spec for a single button in the action bar.
@immutable
class SupyActionButtonSpec {
  /// Creates a button spec.
  const SupyActionButtonSpec({
    this.visible = true,
    this.backgroundColor = const Color(0x66000000),
    this.foregroundColor = const Color(0xFFFFFFFF),
    this.activeBackgroundColor = const Color(0xFFFFFFFF),
    this.activeForegroundColor = const Color(0xFF000000),
  });

  /// Whether the button is rendered.
  final bool visible;

  /// Fill color in the default (off) state.
  final Color backgroundColor;

  /// Icon/label color in the default (off) state.
  final Color foregroundColor;

  /// Fill color in the active (on) state — for toggles like flash and
  /// close-focus.
  final Color activeBackgroundColor;

  /// Icon/label color in the active (on) state.
  final Color activeForegroundColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyActionButtonSpec &&
          other.visible == visible &&
          other.backgroundColor == backgroundColor &&
          other.foregroundColor == foregroundColor &&
          other.activeBackgroundColor == activeBackgroundColor &&
          other.activeForegroundColor == activeForegroundColor;

  @override
  int get hashCode => Object.hash(
    visible,
    backgroundColor,
    foregroundColor,
    activeBackgroundColor,
    activeForegroundColor,
  );

  @override
  String toString() => 'SupyActionButtonSpec(visible: $visible)';
}

/// Action-bar configuration. Mirrors Scanbot's `actionBar` config block —
/// the row of circular controls (flash, zoom, flip-camera, close-focus)
/// that floats above the bottom edge of the camera preview.
@immutable
class SupyActionBarConfiguration {
  /// Creates an action-bar config with all four buttons visible by default.
  const SupyActionBarConfiguration({
    this.visible = true,
    this.flashButton = const SupyActionButtonSpec(),
    this.zoomButton = const SupyActionButtonSpec(),
    this.flipCameraButton = const SupyActionButtonSpec(),
    this.closeFocusButton = const SupyActionButtonSpec(),
    this.zoomFactor = 2.0,
  }) : assert(zoomFactor > 0, 'zoomFactor must be > 0');

  /// Whether the action bar is rendered at all.
  final bool visible;

  /// Flash/torch toggle.
  final SupyActionButtonSpec flashButton;

  /// Zoom step button — each press multiplies zoom by [zoomFactor] up to a
  /// hardware-defined ceiling; tapping at max resets to 1.0.
  final SupyActionButtonSpec zoomButton;

  /// Front/back camera flip.
  final SupyActionButtonSpec flipCameraButton;

  /// Close-focus / `minFocusDistanceLock` toggle.
  final SupyActionButtonSpec closeFocusButton;

  /// Step factor for the zoom button. Default 2x per press.
  final double zoomFactor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyActionBarConfiguration &&
          other.visible == visible &&
          other.flashButton == flashButton &&
          other.zoomButton == zoomButton &&
          other.flipCameraButton == flipCameraButton &&
          other.closeFocusButton == closeFocusButton &&
          other.zoomFactor == zoomFactor;

  @override
  int get hashCode => Object.hash(
    visible,
    flashButton,
    zoomButton,
    flipCameraButton,
    closeFocusButton,
    zoomFactor,
  );

  @override
  String toString() =>
      'SupyActionBarConfiguration(visible: $visible, '
      'zoomFactor: $zoomFactor)';
}
