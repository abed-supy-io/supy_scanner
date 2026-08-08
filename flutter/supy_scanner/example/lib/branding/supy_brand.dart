import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// Supy brand tokens for the example showcase chrome (app bars, cards, list
/// tiles) — the Supy purple design system, primary `#6448C3`.
///
/// Lives in the example app only. The *scanner-surface* half of this palette
/// now has a first-party home in the library as
/// `SupyScannerPalette.supyDark()` / `.supyLight()`; [palette] below stays for
/// the example's light-chrome showcase.
class SupyBrand {
  SupyBrand._();

  // Brand color tokens — Supy purple design system (primary `#6448C3`).
  // `navy`/`navyDeep` keep their historical names but now carry the deep-purple
  // chrome so existing call sites don't churn.
  static const Color navy = Color(0xFF2A1E5C);
  static const Color navyDeep = Color(0xFF1C1340);
  static const Color accent = Color(0xFF6448C3);
  static const Color accentSoft = Color(0xFFEDE9FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF5F3FC);
  static const Color success = Color(0xFF1FB57A);
  static const Color warning = Color(0xFFF0A91B);
  static const Color critical = Color(0xFFE5484D);
  static const Color onNavy = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1C1340);
  static const Color onSurfaceMuted = Color(0xB31C1340);

  /// Scanner-surface palette built from brand tokens.
  static const SupyScannerPalette palette = SupyScannerPalette(
    primary: accent,
    primaryDisabled: Color(0x806448C3),
    onPrimary: onNavy,
    secondary: navy,
    secondaryDisabled: Color(0x802A1E5C),
    onSecondary: onNavy,
    surface: surface,
    surfaceLow: Color(0xCC2A1E5C),
    surfaceHigh: surfaceAlt,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceMuted,
    outline: Color(0x331C1340),
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
          side: const BorderSide(color: Color(0x141C1340)),
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
