import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Requests camera permission through the library's own helper and renders the
/// returned status. The library requests permission itself before scanning;
/// this exposes the primitive so hosts can pre-flight it.
class PermissionsDemo extends StatefulWidget {
  const PermissionsDemo({super.key});

  @override
  State<PermissionsDemo> createState() => _PermissionsDemoState();
}

class _PermissionsDemoState extends State<PermissionsDemo> {
  SupyCameraPermissionStatus? _status;
  bool _busy = false;

  Future<void> _request() async {
    setState(() => _busy = true);
    final status = await SupyPermissions.requestCamera();
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  ({Color color, IconData icon, String note}) _describe(
    SupyCameraPermissionStatus s,
  ) => switch (s) {
    SupyCameraPermissionStatus.granted => (
      color: Colors.green,
      icon: Icons.check_circle,
      note: 'Camera is available — scanners will start.',
    ),
    SupyCameraPermissionStatus.denied => (
      color: Colors.orange,
      icon: Icons.help,
      note: 'Denied for now; you can ask again.',
    ),
    SupyCameraPermissionStatus.permanentlyDenied => (
      color: Colors.red,
      icon: Icons.block,
      note: 'Permanently denied — route the user to system Settings.',
    ),
    SupyCameraPermissionStatus.unknown => (
      color: Colors.grey,
      icon: Icons.device_unknown,
      note: 'Undetermined (e.g. a simulator or unsupported platform).',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return DemoScaffold(
      title: 'Camera permission',
      description:
          'Pre-flight camera access. The scanners request permission on their '
          'own, but SupyPermissions.requestCamera() lets you check or prompt '
          'ahead of time and branch on the four-state result — including the '
          'permanentlyDenied case that needs a trip to system Settings.',
      apiSummary:
          'SupyPermissions.requestCamera() → Future<SupyCameraPermissionStatus>',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _request,
            icon: const Icon(Icons.photo_camera),
            label: Text(_busy ? 'Requesting…' : 'Request camera permission'),
          ),
          const SizedBox(height: 16),
          if (status != null)
            Builder(
              builder: (_) {
                final d = _describe(status);
                return Card(
                  color: d.color.withValues(alpha: 0.12),
                  child: ListTile(
                    leading: Icon(d.icon, color: d.color),
                    title: Text(status.name),
                    subtitle: Text(d.note),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
