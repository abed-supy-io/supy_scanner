import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Showcases every `SupyBarcodeScannerScreen` use-case variant behind one
/// screen, plus a live palette switch. Migrated from the old "Gallery" tab.
class UseCasesDemo extends StatefulWidget {
  const UseCasesDemo({super.key});

  @override
  State<UseCasesDemo> createState() => _UseCasesDemoState();
}

enum _PaletteChoice { supy, dark, light }

class _UseCasesDemoState extends State<UseCasesDemo> {
  _PaletteChoice _palette = _PaletteChoice.supy;

  SupyScannerPalette get _activePalette => switch (_palette) {
    _PaletteChoice.supy => const SupyScannerPalette.supyDark(),
    _PaletteChoice.dark => const SupyScannerPalette.scanbotDark(),
    _PaletteChoice.light => const SupyScannerPalette.scanbotLight(),
  };

  Future<void> _launch(BuildContext context, SupyScanUseCase useCase) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final palette = _activePalette;
    await navigator.push<void>(
      MaterialPageRoute(
        builder:
            (_) => SupyBarcodeScannerScreen(
              useCase: useCase,
              palette: palette,
              onCancel: () => navigator.maybePop(),
              onSingleScan: (b) {
                navigator.maybePop();
                messenger.showSnackBar(
                  SnackBar(content: Text('Single: ${b.rawValue}')),
                );
              },
              onMultipleScan: (items) {
                navigator.maybePop();
                messenger.showSnackBar(
                  SnackBar(content: Text('Multi: ${items.length} items')),
                );
              },
              onFindAndPick: (rows) {
                navigator.maybePop();
                messenger.showSnackBar(
                  SnackBar(content: Text('FindAndPick: ${rows.length} rows')),
                );
              },
              onError:
                  (e) => messenger.showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Scan use-cases',
      description:
          'One full-screen scanner, five Scanbot-parity use-cases. Pick a '
          'palette, then launch each variant to see how single / immediate / '
          'counting / unique / find-and-pick behave.',
      apiSummary:
          'SupyBarcodeScannerScreen(useCase: SupySingleScanUseCase | '
          'SupyMultipleScanUseCase | SupyFindAndPickUseCase, palette: …)',
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
                label: Text('Scanbot Dark'),
                icon: Icon(Icons.dark_mode),
              ),
              ButtonSegment(
                value: _PaletteChoice.light,
                label: Text('Scanbot Light'),
                icon: Icon(Icons.light_mode),
              ),
            ],
            selected: {_palette},
            onSelectionChanged: (s) => setState(() => _palette = s.first),
          ),
          const SizedBox(height: 24),
          Text('Use cases', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('Single scan'),
              subtitle: const Text('Pauses on first detection · confirm sheet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _launch(context, const SupySingleScanUseCase()),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bolt),
              title: const Text('Single scan (immediate)'),
              subtitle: const Text('Returns first detection without sheet'),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _launch(
                    context,
                    const SupySingleScanUseCase(
                      config: SupySingleScanUseCaseConfiguration(
                        confirmationSheetEnabled: false,
                      ),
                    ),
                  ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.format_list_numbered),
              title: const Text('Multiple scan — counting'),
              subtitle: const Text('Same code increments count'),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _launch(
                    context,
                    const SupyMultipleScanUseCase(
                      config: SupyMultipleScanUseCaseConfiguration(
                        mode: SupyMultipleScanMode.counting,
                      ),
                    ),
                  ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Multiple scan — unique'),
              subtitle: const Text('Deduplicates by raw value'),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _launch(
                    context,
                    const SupyMultipleScanUseCase(
                      config: SupyMultipleScanUseCaseConfiguration(
                        mode: SupyMultipleScanMode.unique,
                      ),
                    ),
                  ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Find and pick'),
              subtitle: const Text('Pick-list with per-row progress'),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _launch(
                    context,
                    const SupyFindAndPickUseCase(
                      config: SupyFindAndPickUseCaseConfiguration(
                        expected: [
                          SupyExpectedBarcode(
                            rawValue: '1234567890123',
                            expectedCount: 2,
                            label: 'Sample EAN-13',
                          ),
                          SupyExpectedBarcode(
                            rawValue: '9876543210',
                            expectedCount: 1,
                            label: 'Sample UPC',
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
