import 'package:flutter/material.dart';

import '../models/ui/supy_find_and_pick_use_case_configuration.dart';
import 'supy_find_and_pick_accumulator.dart';

/// Collapsible bottom sheet rendered by the find-and-pick use case.
/// Renders the pick-list with per-row progress, a completion summary, and
/// (optionally) an Unexpected section.
class SupyFindAndPickSheet extends StatefulWidget {
  /// Creates a find-and-pick sheet.
  const SupyFindAndPickSheet({
    required this.accumulator,
    required this.config,
    required this.onSubmit,
    required this.onClear,
    super.key,
  });

  /// State source; the sheet listens for updates.
  final SupyFindAndPickAccumulator accumulator;

  /// Visibility / text / color knobs.
  final SupyFindAndPickUseCaseConfiguration config;

  /// Invoked on submit-button tap.
  final VoidCallback onSubmit;

  /// Invoked on reset-button tap. The sheet does NOT auto-clear.
  final VoidCallback onClear;

  @override
  State<SupyFindAndPickSheet> createState() => _SupyFindAndPickSheetState();
}

class _SupyFindAndPickSheetState extends State<SupyFindAndPickSheet> {
  late bool _expanded = !widget.config.initiallyCollapsed;

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return Material(
      color: cfg.sheetBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: widget.accumulator,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                if (_expanded) _body(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    final cfg = widget.config;
    final acc = widget.accumulator;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cfg.sheetTitle,
                    style: TextStyle(
                      color: cfg.titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${acc.completedRowCount}/${acc.totalRowCount} picked',
                    style: TextStyle(color: cfg.bodyColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              _expanded ? Icons.expand_more : Icons.expand_less,
              color: cfg.titleColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final cfg = widget.config;
    final acc = widget.accumulator;
    final rows = acc.rows;
    final unexpected = acc.unexpected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    'No expected items',
                    style: TextStyle(color: cfg.bodyColor, fontSize: 13),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    for (final r in rows) _row(r),
                    if (unexpected.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Unexpected',
                        style: TextStyle(
                          color: cfg.bodyColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final b in unexpected)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            b.rawValue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cfg.bodyColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: rows.isEmpty ? null : widget.onClear,
                  style: TextButton.styleFrom(
                    foregroundColor: cfg.clearButtonForegroundColor,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(cfg.clearButtonText),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      rows.isEmpty || !acc.isComplete ? null : widget.onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cfg.submitButtonBackgroundColor,
                    foregroundColor: cfg.submitButtonForegroundColor,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(cfg.submitButtonText),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(SupyFindAndPickRow row) {
    final cfg = widget.config;
    final color = row.isComplete ? cfg.matchedRowColor : cfg.pendingRowColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            row.isComplete
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.expected.label ?? row.expected.rawValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: row.isComplete
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                if (row.expected.label != null)
                  Text(
                    row.expected.rawValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cfg.bodyColor, fontSize: 11),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${row.foundCount}/${row.expected.expectedCount}',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
