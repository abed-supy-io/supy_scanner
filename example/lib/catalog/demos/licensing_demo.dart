import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Phase PAID licensing: shows the active license and lets you toggle the gate.
///
/// The library requires `SupyScanner.activate(<signed token>)` once at startup.
/// This demo NEVER handles a real token — it uses the `@visibleForTesting`
/// `debugSetLicense` seam with a `SupyLicense.forTesting(...)` value so the
/// gate can be opened and closed without shipping any secret.
class LicensingDemo extends StatefulWidget {
  const LicensingDemo({super.key});

  @override
  State<LicensingDemo> createState() => _LicensingDemoState();
}

class _LicensingDemoState extends State<LicensingDemo> {
  void _activateDebug() {
    // ignore: invalid_use_of_visible_for_testing_member
    SupyScanner.debugSetLicense(
      // ignore: invalid_use_of_visible_for_testing_member
      SupyLicense.forTesting(
        id: 'example-catalog-debug',
        product: 'supy_scanner',
        tier: SupyLicenseTier.enterprise,
        seats: 0,
        issuedAt: DateTime.utc(2024),
        expiresAt: DateTime.utc(2099),
        holder: 'Supy Example App',
      ),
    );
    setState(() {});
  }

  void _deactivate() {
    SupyScanner.deactivate();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = SupyScanner.isActivated;
    final license = SupyScanner.license;
    return DemoScaffold(
      title: 'Licensing',
      description:
          'supy_scanner is a paid, on-device-licensed library. Every scan entry '
          'point checks that a signed, unexpired license is active and throws '
          'SupyLicenseException otherwise — verified fully offline, no network '
          'in the scan path. In production you call SupyScanner.activate(token); '
          'this demo uses the debug test seam so no real token is involved.',
      apiSummary:
          'SupyScanner.activate(token) · isActivated · license · deactivate() '
          '· (test) debugSetLicense(SupyLicense.forTesting(…))',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color:
                active
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
            child: ListTile(
              leading: Icon(
                active ? Icons.verified_user : Icons.gpp_bad,
                color: active ? Colors.green : Colors.red,
              ),
              title: Text(active ? 'Gate OPEN — activated' : 'Gate CLOSED'),
              subtitle: Text(
                active
                    ? 'Scanning entry points will run.'
                    : 'Scanning entry points will throw SupyLicenseException.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (license != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('ID', license.id),
                    _kv('Product', license.product),
                    _kv('Tier', license.tier.name),
                    _kv(
                      'Seats',
                      license.seats == 0 ? 'unmetered' : '${license.seats}',
                    ),
                    _kv('Holder', license.holder ?? '—'),
                    _kv('Expires', license.expiresAt.toIso8601String()),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: active ? null : _activateDebug,
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('Activate (debug)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: active ? _deactivate : null,
                  icon: const Icon(Icons.lock),
                  label: const Text('Deactivate'),
                ),
              ),
            ],
          ),
          if (!kDebugMode) ...[
            const SizedBox(height: 12),
            const Text(
              'The debug seam is only available in debug builds.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );
}
