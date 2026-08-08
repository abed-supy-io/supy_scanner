import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../../debug/supy_debug_hud.dart';
import '../demo_scaffold.dart';

/// Emits `SupyLog` records at each level and toggles the in-app debug HUD that
/// tails them. Shows how the library's structured logging surfaces on-device
/// for QA without a wired-up console.
class LogHudDemo extends StatelessWidget {
  const LogHudDemo({super.key});

  static const String _tag = 'catalog';

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Logging & debug HUD',
      description:
          'The library logs through a pluggable SupyLog sink. The example app '
          'installs a HUD sink app-wide, so records tail on-device — handy for '
          'QA on a real phone with no debugger attached. Emit a few records, '
          'then toggle the HUD to see them.',
      apiSummary:
          'SupyLog.debug/info/warn/error(tag, message)  ·  '
          'SupyDebugHud.of(context)?.toggle()',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => SupyLog.debug(_tag, 'A debug record'),
                icon: const Icon(Icons.bug_report),
                label: const Text('debug'),
              ),
              OutlinedButton.icon(
                onPressed: () => SupyLog.info(_tag, 'An info record'),
                icon: const Icon(Icons.info_outline),
                label: const Text('info'),
              ),
              OutlinedButton.icon(
                onPressed:
                    () =>
                        SupyLog.warn(_tag, 'A warning record', error: 'sample'),
                icon: const Icon(Icons.warning_amber),
                label: const Text('warn'),
              ),
              OutlinedButton.icon(
                onPressed:
                    () => SupyLog.error(
                      _tag,
                      'An error record',
                      error: StateError('sample failure'),
                    ),
                icon: const Icon(Icons.error_outline),
                label: const Text('error'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              final hud = SupyDebugHud.of(context);
              if (hud == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('HUD is only mounted in debug builds.'),
                  ),
                );
                return;
              }
              hud.toggle();
            },
            icon: const Icon(Icons.terminal),
            label: const Text('Toggle debug HUD'),
          ),
        ],
      ),
    );
  }
}
