import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Probes the native scanning core across the MethodChannel and reports its
/// version / ABI. A quick end-to-end health check that the platform side is
/// wired up on this device.
class NativeCoreDemo extends StatefulWidget {
  const NativeCoreDemo({super.key});

  @override
  State<NativeCoreDemo> createState() => _NativeCoreDemoState();
}

class _NativeCoreDemoState extends State<NativeCoreDemo> {
  SupyNativeCoreProbe? _probe;
  String? _error;
  bool _busy = false;

  Future<void> _probeCore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final probe = await SupyScannerChannel.instance.nativeCoreProbe();
      if (!mounted) return;
      setState(() {
        _probe = probe;
        _busy = false;
      });
    } on SupyScanError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code.name}: ${e.message}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final probe = _probe;
    return DemoScaffold(
      title: 'Native core probe',
      description:
          'Round-trips a call to the native side over the versioned '
          'io.supy.scanner/v1 MethodChannel and reports the native core '
          'version and ABI. Use it as a smoke test that the plugin is '
          'correctly registered on this device.',
      apiSummary:
          'SupyScannerChannel.instance.nativeCoreProbe() → SupyNativeCoreProbe',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _probeCore,
            icon: const Icon(Icons.memory),
            label: Text(_busy ? 'Probing…' : 'Probe native core'),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Card(
              color: Colors.red.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.error, color: Colors.red),
                title: const Text('Probe failed'),
                subtitle: Text(_error!),
              ),
            ),
          if (probe != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('Version', probe.version),
                    _kv('ABI version', probe.abiVersion.toString()),
                    _kv(
                      'GMS doc scanner',
                      probe.gmsDocumentScannerAvailable
                          ? 'available'
                          : 'unavailable',
                    ),
                  ],
                ),
              ),
            ),
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
          width: 130,
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
