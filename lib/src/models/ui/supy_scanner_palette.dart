import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Token-based color palette for the Supy embedded barcode scanner UI.
///
/// Mirrors Scanbot's RTU UI `sbColor*` vocabulary so that retailer call sites
/// migrating off Scanbot keep the same mental model. All 16 tokens are
/// non-nullable — callers either accept a preset ([scanbotDark] /
/// [scanbotLight]) or specify every value.
///
/// Use [copyWith] to override a small number of tokens on top of a preset.
@immutable
class SupyScannerPalette {
  /// Creates a fully-specified palette. Prefer the named presets unless a
  /// host app already has a brand color system to bind here.
  const SupyScannerPalette({
    required this.primary,
    required this.primaryDisabled,
    required this.onPrimary,
    required this.secondary,
    required this.secondaryDisabled,
    required this.onSecondary,
    required this.surface,
    required this.surfaceLow,
    required this.surfaceHigh,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.negative,
    required this.positive,
    required this.warning,
    required this.modalOverlay,
  });

  /// Dark-themed default — matches Scanbot RTU UI's out-of-the-box look:
  /// dark scrim over the camera preview, bright accent for actionable controls.
  const SupyScannerPalette.scanbotDark()
    : primary = const Color(0xFF1AC0E5),
      primaryDisabled = const Color(0xFF1AC0E5),
      onPrimary = const Color(0xFFFFFFFF),
      secondary = const Color(0xFFFFCE5C),
      secondaryDisabled = const Color(0xFFFFCE5C),
      onSecondary = const Color(0xFF000000),
      surface = const Color(0xFF1C1B1F),
      surfaceLow = const Color(0xCC000000),
      surfaceHigh = const Color(0xFF2A2A2D),
      onSurface = const Color(0xFFFFFFFF),
      onSurfaceVariant = const Color(0xB3FFFFFF),
      outline = const Color(0x66FFFFFF),
      negative = const Color(0xFFFF3B30),
      positive = const Color(0xFF34C759),
      warning = const Color(0xFFFF4D4D),
      modalOverlay = const Color(0x99000000);

  /// Light-themed default — for hosts that want a brighter chrome over the
  /// camera preview (still uses a translucent scrim for legibility).
  const SupyScannerPalette.scanbotLight()
    : primary = const Color(0xFF0073E6),
      primaryDisabled = const Color(0x800073E6),
      onPrimary = const Color(0xFFFFFFFF),
      secondary = const Color(0xFFFFB000),
      secondaryDisabled = const Color(0x80FFB000),
      onSecondary = const Color(0xFF000000),
      surface = const Color(0xFFFFFFFF),
      surfaceLow = const Color(0xCCFFFFFF),
      surfaceHigh = const Color(0xFFF2F2F7),
      onSurface = const Color(0xFF1C1B1F),
      onSurfaceVariant = const Color(0xB31C1B1F),
      outline = const Color(0x661C1B1F),
      negative = const Color(0xFFD32F2F),
      positive = const Color(0xFF2E7D32),
      warning = const Color(0xFFED6C02),
      modalOverlay = const Color(0x66000000);

  /// Accent for primary actions (top-bar cancel, submit, AR-overlay highlight).
  final Color primary;

  /// [primary] in its disabled state (e.g., grayed submit button).
  final Color primaryDisabled;

  /// Foreground (text/icon) color drawn on top of [primary].
  final Color onPrimary;

  /// Secondary accent (zoom button, counter chip).
  final Color secondary;

  /// [secondary] in its disabled state.
  final Color secondaryDisabled;

  /// Foreground (text/icon) color drawn on top of [secondary].
  final Color onSecondary;

  /// Base sheet / card surface (multi-scan bottom sheet, single-scan
  /// confirmation card).
  final Color surface;

  /// Low-elevation surface (typically a translucent scrim over the camera
  /// preview — top-bar gradient bottom, action-bar gradient top).
  final Color surfaceLow;

  /// High-elevation surface (pressed state, contrast row inside a sheet).
  final Color surfaceHigh;

  /// Foreground (text/icon) color drawn on top of [surface].
  final Color onSurface;

  /// Muted foreground (secondary text, hints) drawn on top of [surface].
  final Color onSurfaceVariant;

  /// Divider / border / finder stroke fallback.
  final Color outline;

  /// Error indication (failed scan badge, exceeded-count chip).
  final Color negative;

  /// Success indication (confirmed scan, completed expected barcode).
  final Color positive;

  /// Warning indication (low-light hint, near-edge-of-frame warning).
  final Color warning;

  /// Scrim drawn over the camera preview when a modal sheet is open.
  final Color modalOverlay;

  /// Returns a copy with the given tokens replaced — every parameter is
  /// optional; unspecified tokens are inherited from this palette.
  SupyScannerPalette copyWith({
    Color? primary,
    Color? primaryDisabled,
    Color? onPrimary,
    Color? secondary,
    Color? secondaryDisabled,
    Color? onSecondary,
    Color? surface,
    Color? surfaceLow,
    Color? surfaceHigh,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? outline,
    Color? negative,
    Color? positive,
    Color? warning,
    Color? modalOverlay,
  }) => SupyScannerPalette(
    primary: primary ?? this.primary,
    primaryDisabled: primaryDisabled ?? this.primaryDisabled,
    onPrimary: onPrimary ?? this.onPrimary,
    secondary: secondary ?? this.secondary,
    secondaryDisabled: secondaryDisabled ?? this.secondaryDisabled,
    onSecondary: onSecondary ?? this.onSecondary,
    surface: surface ?? this.surface,
    surfaceLow: surfaceLow ?? this.surfaceLow,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
    outline: outline ?? this.outline,
    negative: negative ?? this.negative,
    positive: positive ?? this.positive,
    warning: warning ?? this.warning,
    modalOverlay: modalOverlay ?? this.modalOverlay,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyScannerPalette &&
          other.primary == primary &&
          other.primaryDisabled == primaryDisabled &&
          other.onPrimary == onPrimary &&
          other.secondary == secondary &&
          other.secondaryDisabled == secondaryDisabled &&
          other.onSecondary == onSecondary &&
          other.surface == surface &&
          other.surfaceLow == surfaceLow &&
          other.surfaceHigh == surfaceHigh &&
          other.onSurface == onSurface &&
          other.onSurfaceVariant == onSurfaceVariant &&
          other.outline == outline &&
          other.negative == negative &&
          other.positive == positive &&
          other.warning == warning &&
          other.modalOverlay == modalOverlay;

  @override
  int get hashCode => Object.hashAll(<Object>[
    primary,
    primaryDisabled,
    onPrimary,
    secondary,
    secondaryDisabled,
    onSecondary,
    surface,
    surfaceLow,
    surfaceHigh,
    onSurface,
    onSurfaceVariant,
    outline,
    negative,
    positive,
    warning,
    modalOverlay,
  ]);

  @override
  String toString() =>
      'SupyScannerPalette(primary: $primary, surface: $surface)';
}
