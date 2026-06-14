import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// Supy brand tokens for the example showcase tab.
///
/// Lives in the example app only — promotion to the library (as a
/// `SupyScannerPalette.supyBrand()` preset) waits on real brand-design sign-off.
class SupyBrand {
  SupyBrand._();

  // Brand color tokens — derived from supy.io.
  static const Color navy = Color(0xFF0F1E3A);
  static const Color navyDeep = Color(0xFF0A1428);
  static const Color accent = Color(0xFF2F6BFF);
  static const Color accentSoft = Color(0xFFE8EFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF4F6FB);
  static const Color success = Color(0xFF1FB57A);
  static const Color warning = Color(0xFFF0A91B);
  static const Color critical = Color(0xFFE5484D);
  static const Color onNavy = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF0F1E3A);
  static const Color onSurfaceMuted = Color(0xB30F1E3A);

  /// Scanner-surface palette built from brand tokens.
  static const SupyScannerPalette palette = SupyScannerPalette(
    primary: accent,
    primaryDisabled: Color(0x802F6BFF),
    onPrimary: onNavy,
    secondary: navy,
    secondaryDisabled: Color(0x800F1E3A),
    onSecondary: onNavy,
    surface: surface,
    surfaceLow: Color(0xCC0F1E3A),
    surfaceHigh: surfaceAlt,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceMuted,
    outline: Color(0x330F1E3A),
    negative: critical,
    positive: success,
    warning: warning,
    modalOverlay: Color(0x99000000),
  );

  /// Material 3 theme for branded demo screens (light only).
  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: accent,
      scaffoldBackgroundColor: surfaceAlt,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: onNavy,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onNavy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x140F1E3A)),
        ),
      ),
    );
  }
}

/// Code-rendered Supy wordmark — placeholder until Supy design supplies the
/// real wordmark file. Renders at the requested height with brand kerning.
class SupyWordmark extends StatelessWidget {
  const SupyWordmark({
    super.key,
    this.height = 24,
    this.color = SupyBrand.onNavy,
  });

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'supy',
      style: TextStyle(
        fontSize: height,
        height: 1.0,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: color,
      ),
    );
  }
}
