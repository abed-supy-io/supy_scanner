import 'package:flutter/material.dart';

import 'branding/supy_brand.dart';
import 'catalog/catalog_home.dart';
import 'catalog/example_license.dart';
import 'debug/supy_debug_hud.dart';

void main() {
  // Open the Phase PAID license gate in debug builds so every catalog demo can
  // exercise the scan path. Never ships a real token — see [ensureExampleLicense].
  ensureExampleLicense();
  runApp(const SupyScannerExampleApp());
}

class SupyScannerExampleApp extends StatelessWidget {
  const SupyScannerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'supy_scanner example',
      debugShowCheckedModeBanner: false,
      theme: SupyBrand.theme(),
      home: const SupyDebugHudScope(child: CatalogHome()),
    );
  }
}
