import 'package:flutter/material.dart';

import '../branding/supy_brand.dart';
import '../debug/supy_debug_hud.dart';
import 'catalog_entry.dart';
import 'catalog_registry.dart';

/// The one and only home screen: a single scrollable catalog of every
/// `supy_scanner` feature, grouped by category. Each row is a self-describing
/// card that opens a live demo. Replaces the old tab/grid duplication.
class CatalogHome extends StatelessWidget {
  const CatalogHome({super.key});

  @override
  Widget build(BuildContext context) {
    final grouped = catalogByCategory();
    final categories = CatalogCategory.values
        .where((c) => grouped.containsKey(c))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('supy_scanner catalog'),
        actions: [
          Builder(
            builder: (innerContext) {
              final hud = SupyDebugHud.of(innerContext);
              if (hud == null) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Toggle SupyLog HUD',
                icon: const Icon(Icons.bug_report_outlined),
                onPressed: hud.toggle,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Intro(),
          for (final category in categories) ...[
            _SectionHeader(category: category),
            for (final entry in grouped[category]!) _EntryCard(entry: entry),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        'Every feature of the scanner, one tap away. Pick a card to read what '
        'it does and run it live.',
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: SupyBrand.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.category});

  final CatalogCategory category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Icon(category.icon, size: 20, color: SupyBrand.accent),
          const SizedBox(width: 8),
          Text(
            category.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: SupyBrand.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final CatalogEntry entry;

  void _open(BuildContext context) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: entry.builder));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: SupyBrand.accentSoft,
          child: Icon(entry.icon, color: SupyBrand.accent),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(entry.description),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context),
      ),
    );
  }
}
