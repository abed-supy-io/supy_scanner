import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Top-bar background fill mode.
enum SupyTopBarMode {
  /// Solid background using [SupyTopBarConfiguration.backgroundColor].
  solid,

  /// Vertical gradient from the configured color (top) to transparent
  /// (bottom) — Scanbot RTU UI's default look over the camera preview.
  gradient,
}

/// Status-bar visibility/style policy for the scanner screen.
enum SupyStatusBarMode {
  /// Hide the system status bar while the scanner is on screen.
  hidden,

  /// Show the status bar with light foreground (icons/clock white) — for
  /// scanners with dark chrome.
  light,

  /// Show the status bar with dark foreground — for scanners with light
  /// chrome.
  dark,
}

/// Style for a single-line text element in the top bar (e.g., cancel-button
/// label).
@immutable
class SupyTextStyleSpec {
  /// Creates a text-style spec. Defaults match Scanbot RTU UI.
  const SupyTextStyleSpec({
    this.text,
    this.color,
    this.fontSize = 16.0,
    this.fontWeight = FontWeight.w600,
  });

  /// The string to render. Resolves to the string bundle's `cancel` when null;
  /// pass `''` to hide the element entirely.
  final String? text;

  /// Foreground color. Resolves to the palette `onSurface` when null.
  final Color? color;

  /// Font size in logical pixels.
  final double fontSize;

  /// Font weight.
  final FontWeight fontWeight;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyTextStyleSpec &&
          other.text == text &&
          other.color == color &&
          other.fontSize == fontSize &&
          other.fontWeight == fontWeight;

  @override
  int get hashCode => Object.hash(text, color, fontSize, fontWeight);

  @override
  String toString() => 'SupyTextStyleSpec("$text", $color, $fontSize)';
}

/// Top-bar configuration. Mirrors Scanbot's `topBar` config block.
@immutable
class SupyTopBarConfiguration {
  /// Creates a top-bar config. Defaults: gradient mode, transparent (so the
  /// scrim shows through the camera), status bar hidden, "Cancel" label.
  const SupyTopBarConfiguration({
    this.mode = SupyTopBarMode.gradient,
    this.backgroundColor,
    this.statusBarMode = SupyStatusBarMode.hidden,
    this.cancelButton = const SupyTextStyleSpec(),
  });

  /// Background fill mode.
  final SupyTopBarMode mode;

  /// Background color. With [SupyTopBarMode.gradient] this is the top color
  /// (fades to transparent at the bottom of the bar). Resolves to the palette
  /// `surfaceLow` when null.
  final Color? backgroundColor;

  /// Status-bar policy while the scanner is on screen. The default
  /// [SupyStatusBarMode.hidden] hides the system status bar for the lifetime
  /// of the top bar and restores it on dispose (Scanbot RTU UI parity).
  final SupyStatusBarMode statusBarMode;

  /// Cancel-button label + color. Resolves to the string bundle's `cancel`
  /// when [SupyTextStyleSpec.text] is null; hidden if it is empty.
  final SupyTextStyleSpec cancelButton;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyTopBarConfiguration &&
          other.mode == mode &&
          other.backgroundColor == backgroundColor &&
          other.statusBarMode == statusBarMode &&
          other.cancelButton == cancelButton;

  @override
  int get hashCode =>
      Object.hash(mode, backgroundColor, statusBarMode, cancelButton);

  @override
  String toString() =>
      'SupyTopBarConfiguration(mode: $mode, bg: $backgroundColor)';
}
