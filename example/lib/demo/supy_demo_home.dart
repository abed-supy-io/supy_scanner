import 'package:flutter/material.dart';

import '../branding/supy_brand.dart';
import 'supy_demo_batch_barcode.dart';
import 'supy_demo_document.dart';
import 'supy_demo_embedded_barcode.dart';
import 'supy_demo_invoice_capture.dart';
import 'supy_demo_single_barcode.dart';
import 'supy_demo_smart_document.dart';

/// Supy-branded landing inside the example app — single tab showcasing
/// barcode + document flows in a product-shaped UI.
class SupyDemoHome extends StatelessWidget {
  const SupyDemoHome({super.key, this.onOpenDevTabs});

  /// Optional callback to jump back to the QA tabs (tab index 0).
  final VoidCallback? onOpenDevTabs;

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SupyBrand.surfaceAlt,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _BrandHeader(),
          const SizedBox(height: 24),
          const Text(
            'SCANNERS',
            style: TextStyle(
              color: SupyBrand.onSurfaceMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: [
              _ActionTile(
                icon: Icons.qr_code_scanner,
                title: 'Scan Barcode',
                subtitle: 'One-shot read',
                onTap: () => _push(context, const SupyDemoSingleBarcodePage()),
              ),
              _ActionTile(
                icon: Icons.dynamic_feed,
                title: 'Batch Count',
                subtitle: 'Many in one go',
                onTap: () => _push(context, const SupyDemoBatchBarcodePage()),
              ),
              _ActionTile(
                icon: Icons.center_focus_strong,
                title: 'Live Camera',
                subtitle: 'Embedded view',
                onTap:
                    () => _push(context, const SupyDemoEmbeddedBarcodePage()),
              ),
              _ActionTile(
                icon: Icons.document_scanner,
                title: 'Capture Document',
                subtitle: 'Multi-page + OCR',
                onTap: () => _push(context, const SupyDemoDocumentPage()),
              ),
              _ActionTile(
                icon: Icons.auto_awesome,
                title: 'Smart Document',
                subtitle: 'Live guidance + auto-snap',
                onTap: () => _push(context, const SupyDemoSmartDocumentPage()),
              ),
              _ActionTile(
                icon: Icons.receipt_long,
                title: 'Invoice Capture',
                subtitle: 'Capture → confirm → upload',
                onTap: () => _push(context, const SupyDemoInvoiceCapture()),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (onOpenDevTabs != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenDevTabs,
                icon: const Icon(Icons.developer_mode, size: 18),
                label: const Text('Open developer tabs'),
                style: TextButton.styleFrom(foregroundColor: SupyBrand.navy),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SupyBrand.navy, SupyBrand.navyDeep],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SupyWordmark(height: 32),
          const SizedBox(height: 12),
          const Text(
            'Scan anything in your restaurant.',
            style: TextStyle(
              color: SupyBrand.onNavy,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Barcodes, batch sessions, documents and OCR — '
            'powered on-device.',
            style: TextStyle(
              color: SupyBrand.onNavy.withValues(alpha: 0.78),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SupyBrand.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: SupyBrand.accentSoft,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x140F1E3A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SupyBrand.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: SupyBrand.accent, size: 24),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: SupyBrand.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: SupyBrand.onSurfaceMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
