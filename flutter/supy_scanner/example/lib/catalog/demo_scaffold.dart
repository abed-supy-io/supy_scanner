import 'package:flutter/material.dart';

import '../branding/supy_brand.dart';

/// Shared layout for every catalog detail page.
///
/// Renders a consistent, self-describing header — **What it is** + **API used**
/// — above the live [child] demo, so every showcase explains itself the same
/// way. Pass [fullBleed] for demos that own the whole viewport (embedded camera
/// views); the header then collapses into an info sheet reachable from the app
/// bar instead of stacking above the demo.
class DemoScaffold extends StatelessWidget {
  const DemoScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.apiSummary,
    required this.child,
    this.fullBleed = false,
    this.scrollable = true,
  });

  final String title;
  final String description;
  final String apiSummary;
  final Widget child;

  /// When true the [child] fills the body and the description is moved behind
  /// an info button in the app bar (used for live camera demos).
  final bool fullBleed;

  /// When true (and not [fullBleed]) the body scrolls. Set false for demos that
  /// manage their own scrolling / need a bounded height.
  final bool scrollable;

  void _showInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (_) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _DescriptionBlock(description: description),
                const SizedBox(height: 16),
                _ApiBlock(apiSummary: apiSummary),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (fullBleed)
            IconButton(
              tooltip: 'About this demo',
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showInfo(context),
            ),
        ],
      ),
      body: fullBleed ? child : _buildStacked(context),
    );
  }

  Widget _buildStacked(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DescriptionBlock(description: description),
          const SizedBox(height: 12),
          _ApiBlock(apiSummary: apiSummary),
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],
      ),
    );

    if (!scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, Expanded(child: child)],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class _DescriptionBlock extends StatelessWidget {
  const _DescriptionBlock({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    return Text(
      description,
      style: const TextStyle(
        fontSize: 15,
        height: 1.4,
        color: SupyBrand.onSurface,
      ),
    );
  }
}

class _ApiBlock extends StatelessWidget {
  const _ApiBlock({required this.apiSummary});

  final String apiSummary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SupyBrand.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.code, size: 16, color: SupyBrand.accent),
              SizedBox(width: 6),
              Text(
                'API USED',
                style: TextStyle(
                  color: SupyBrand.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            apiSummary,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
              color: SupyBrand.navy,
            ),
          ),
        ],
      ),
    );
  }
}
