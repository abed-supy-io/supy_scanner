import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Inspects the two theming primitives every scanner surface takes: a
/// `SupyScannerPalette` (colors) and a `SupyScannerStrings` bundle (localized
/// labels, incl. Arabic / RTL). Presentation-only — no camera.
class ThemingDemo extends StatefulWidget {
  const ThemingDemo({super.key});

  @override
  State<ThemingDemo> createState() => _ThemingDemoState();
}

enum _PaletteChoice { supy, dark, light }

class _ThemingDemoState extends State<ThemingDemo> {
  _PaletteChoice _palette = _PaletteChoice.supy;
  String _lang = 'en';

  SupyScannerPalette get _activePalette => switch (_palette) {
    _PaletteChoice.supy => const SupyScannerPalette.supyDark(),
    _PaletteChoice.dark => const SupyScannerPalette.scanbotDark(),
    _PaletteChoice.light => const SupyScannerPalette.scanbotLight(),
  };

  @override
  Widget build(BuildContext context) {
    final p = _activePalette;
    final strings = SupyScannerStrings.of(_lang);
    return DemoScaffold(
      title: 'Theming & localization',
      description:
          'Every scanner screen and overlay is driven by a SupyScannerPalette '
          '(colors) and a SupyScannerStrings bundle (labels). Both are frozen '
          'value types you pass in — swap them to rebrand the UI or localize '
          'it, including full Arabic / RTL.',
      apiSummary:
          'SupyScannerPalette.supyDark() / .supyLight() / .scanbotDark() / '
          '.scanbotLight()  ·  SupyScannerStrings.of(languageCode) / .en() / .ar()',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Palette', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<_PaletteChoice>(
            segments: const [
              ButtonSegment(
                value: _PaletteChoice.supy,
                label: Text('Supy'),
                icon: Icon(Icons.auto_awesome),
              ),
              ButtonSegment(
                value: _PaletteChoice.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode),
              ),
              ButtonSegment(
                value: _PaletteChoice.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode),
              ),
            ],
            selected: {_palette},
            onSelectionChanged: (s) => setState(() => _palette = s.first),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _swatch('primary', p.primary),
              _swatch('onPrimary', p.onPrimary),
              _swatch('secondary', p.secondary),
              _swatch('surface', p.surface),
              _swatch('onSurface', p.onSurface),
              _swatch('outline', p.outline),
              _swatch('positive', p.positive),
              _swatch('negative', p.negative),
              _swatch('warning', p.warning),
            ],
          ),
          const SizedBox(height: 24),
          Text('Strings', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'ar', label: Text('العربية')),
            ],
            selected: {_lang},
            onSelectionChanged: (s) => setState(() => _lang = s.first),
          ),
          const SizedBox(height: 12),
          Directionality(
            textDirection:
                _lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('cancel', strings.cancel),
                    _kv('done', strings.done),
                    _kv('retry', strings.retry),
                    _kv('flash', strings.flash),
                    _kv('barcodeDetected', strings.barcodeDetected),
                    _kv('aimAtDocument', strings.aimAtDocument),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _swatch(String name, Color color) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black26),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
}
