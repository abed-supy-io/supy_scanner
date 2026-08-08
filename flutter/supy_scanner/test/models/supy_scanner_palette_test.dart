import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyScannerPalette presets', () {
    test('scanbotDark preset is stable and self-equal', () {
      const a = SupyScannerPalette.scanbotDark();
      const b = SupyScannerPalette.scanbotDark();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('scanbotLight preset is stable and self-equal', () {
      const a = SupyScannerPalette.scanbotLight();
      const b = SupyScannerPalette.scanbotLight();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('supyDark / supyLight presets are stable and self-equal', () {
      expect(
        const SupyScannerPalette.supyDark(),
        equals(const SupyScannerPalette.supyDark()),
      );
      expect(
        const SupyScannerPalette.supyLight(),
        equals(const SupyScannerPalette.supyLight()),
      );
    });

    test('supy presets use the Supy purple as primary accent', () {
      const purple = Color(0xFF6448C3);
      expect(const SupyScannerPalette.supyDark().primary, equals(purple));
      expect(const SupyScannerPalette.supyLight().primary, equals(purple));
    });

    test('supy presets are branded distinctly from the scanbot presets', () {
      expect(
        const SupyScannerPalette.supyDark(),
        isNot(equals(const SupyScannerPalette.scanbotDark())),
      );
      expect(
        const SupyScannerPalette.supyDark().primary,
        isNot(equals(const SupyScannerPalette.scanbotDark().primary)),
      );
    });

    test('dark and light presets differ', () {
      const dark = SupyScannerPalette.scanbotDark();
      const light = SupyScannerPalette.scanbotLight();
      expect(dark, isNot(equals(light)));
      expect(dark.surface, isNot(equals(light.surface)));
      expect(dark.onSurface, isNot(equals(light.onSurface)));
    });

    test('dark preset has translucent modalOverlay over preview', () {
      const dark = SupyScannerPalette.scanbotDark();
      // Modal overlay must be partially translucent — otherwise it blacks out
      // the camera preview entirely when a sheet is shown.
      expect(dark.modalOverlay.a, lessThan(1.0));
      expect(dark.modalOverlay.a, greaterThan(0.0));
    });

    test('light preset surface is bright enough for dark foreground', () {
      const light = SupyScannerPalette.scanbotLight();
      // Light theme must have a bright surface, otherwise dark on-surface text
      // would be illegible.
      final brightness =
          (light.surface.r + light.surface.g + light.surface.b) / 3 * 255.0;
      expect(brightness, greaterThan(200));
    });
  });

  group('SupyScannerPalette equality + hashCode', () {
    const baseline = SupyScannerPalette.scanbotDark();

    test('differs from a single-token override', () {
      final override = baseline.copyWith(primary: const Color(0xFFAA00FF));
      expect(override, isNot(equals(baseline)));
      expect(override.hashCode, isNot(equals(baseline.hashCode)));
    });

    test('equals after override is reversed', () {
      final override = baseline
          .copyWith(primary: const Color(0xFFAA00FF))
          .copyWith(primary: baseline.primary);
      expect(override, equals(baseline));
      expect(override.hashCode, equals(baseline.hashCode));
    });

    test('cross-token equality discriminates every token', () {
      // For each of the 16 tokens, an override on that token alone must
      // produce a palette that is not equal to baseline. This guards against
      // a typo in operator== leaving a field out.
      final overrides = <String, SupyScannerPalette>{
        'primary': baseline.copyWith(primary: const Color(0xFF111111)),
        'primaryDisabled': baseline.copyWith(
          primaryDisabled: const Color(0xFF111111),
        ),
        'onPrimary': baseline.copyWith(onPrimary: const Color(0xFF111111)),
        'secondary': baseline.copyWith(secondary: const Color(0xFF111111)),
        'secondaryDisabled': baseline.copyWith(
          secondaryDisabled: const Color(0xFF111111),
        ),
        'onSecondary': baseline.copyWith(onSecondary: const Color(0xFF111111)),
        'surface': baseline.copyWith(surface: const Color(0xFF111111)),
        'surfaceLow': baseline.copyWith(surfaceLow: const Color(0xFF111111)),
        'surfaceHigh': baseline.copyWith(surfaceHigh: const Color(0xFF111111)),
        'onSurface': baseline.copyWith(onSurface: const Color(0xFF111111)),
        'onSurfaceVariant': baseline.copyWith(
          onSurfaceVariant: const Color(0xFF111111),
        ),
        'outline': baseline.copyWith(outline: const Color(0xFF111111)),
        'negative': baseline.copyWith(negative: const Color(0xFF111111)),
        'positive': baseline.copyWith(positive: const Color(0xFF111111)),
        'warning': baseline.copyWith(warning: const Color(0xFF111111)),
        'modalOverlay': baseline.copyWith(
          modalOverlay: const Color(0xFF111111),
        ),
      };
      for (final entry in overrides.entries) {
        expect(
          entry.value,
          isNot(equals(baseline)),
          reason: 'overriding ${entry.key} must produce a different palette',
        );
      }
    });
  });

  group('SupyScannerPalette.copyWith', () {
    test('no-arg copyWith equals receiver', () {
      const baseline = SupyScannerPalette.scanbotDark();
      expect(baseline.copyWith(), equals(baseline));
    });

    test('honors every named override', () {
      const baseline = SupyScannerPalette.scanbotDark();
      const c = Color(0xFFAB12CD);
      final copy = baseline.copyWith(
        primary: c,
        primaryDisabled: c,
        onPrimary: c,
        secondary: c,
        secondaryDisabled: c,
        onSecondary: c,
        surface: c,
        surfaceLow: c,
        surfaceHigh: c,
        onSurface: c,
        onSurfaceVariant: c,
        outline: c,
        negative: c,
        positive: c,
        warning: c,
        modalOverlay: c,
      );
      expect(copy.primary, c);
      expect(copy.primaryDisabled, c);
      expect(copy.onPrimary, c);
      expect(copy.secondary, c);
      expect(copy.secondaryDisabled, c);
      expect(copy.onSecondary, c);
      expect(copy.surface, c);
      expect(copy.surfaceLow, c);
      expect(copy.surfaceHigh, c);
      expect(copy.onSurface, c);
      expect(copy.onSurfaceVariant, c);
      expect(copy.outline, c);
      expect(copy.negative, c);
      expect(copy.positive, c);
      expect(copy.warning, c);
      expect(copy.modalOverlay, c);
    });
  });

  test('toString mentions key tokens', () {
    const p = SupyScannerPalette.scanbotDark();
    final s = p.toString();
    expect(s, contains('SupyScannerPalette'));
    expect(s, contains('primary'));
    expect(s, contains('surface'));
  });
}
