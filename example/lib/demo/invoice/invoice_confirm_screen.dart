import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../../branding/supy_brand.dart';
import 'invoice_capture_screen.dart';
import 'invoice_page_editor.dart';

/// Mock supplier — demo-only; the real app sources these from its catalog.
class _Supplier {
  const _Supplier(this.id, this.name);
  final String id;
  final String name;
}

const List<_Supplier> _mockSuppliers = [
  _Supplier('s1', 'Fresh Farms Trading LLC'),
  _Supplier('s2', 'Gulf Beverages Co.'),
  _Supplier('s3', 'Metro Dairy Supplies'),
  _Supplier('s4', 'Sunrise Produce Market'),
];

/// Outcome of the confirm step.
enum InvoiceConfirmOutcome { uploaded, cancelled }

/// Option B — the Supy-branded "Confirm invoice" step that sits between
/// document capture and upload.
///
/// The raw Scanbot flow leaves the camera open with no confirmation. This
/// screen gives the user an explicit review: a page-count badge, tappable
/// page thumbnails (each opening the full edit path — rotate / re-scan /
/// remove), an "Add page" affordance, a supplier selector, and a primary
/// "Upload invoice" button. On success it shows the "Invoice uploaded" state.
class InvoiceConfirmScreen extends StatefulWidget {
  const InvoiceConfirmScreen({super.key, required this.pages});

  /// Pages captured by [InvoiceCaptureScreen].
  final List<SupyDocumentPage> pages;

  @override
  State<InvoiceConfirmScreen> createState() => _InvoiceConfirmScreenState();
}

class _InvoiceConfirmScreenState extends State<InvoiceConfirmScreen> {
  late final List<SupyDocumentPage> _pages =
      List<SupyDocumentPage>.of(widget.pages);
  _Supplier? _supplier;
  bool _uploading = false;
  bool _uploaded = false;

  Future<void> _editPage(int index) async {
    final result = await Navigator.of(context).push<InvoicePageEditResult>(
      MaterialPageRoute(
        builder: (_) => InvoicePageEditor(page: _pages[index], index: index),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.removed) {
        _pages.removeAt(index);
      } else if (result.page != null) {
        _pages[index] = result.page!;
      }
    });
  }

  Future<void> _addPage() async {
    final result = await Navigator.of(context).push<List<SupyDocumentPage>>(
      MaterialPageRoute(
        builder: (_) => const InvoiceCaptureScreen(singlePage: true),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() => _pages.addAll(result));
  }

  Future<void> _upload() async {
    setState(() => _uploading = true);
    // Demo-only: simulate the upload round-trip. The real app posts pages +
    // supplier to its backend here. No network call ships in the library.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _uploaded = true;
    });
  }

  void _rescanAll() {
    Navigator.of(context).pop(InvoiceConfirmOutcome.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Confirm invoice'),
          leading: _uploaded
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      Navigator.of(context).pop(InvoiceConfirmOutcome.cancelled),
                ),
          automaticallyImplyLeading: false,
        ),
        body: _uploaded ? _buildUploaded() : _buildReview(),
      ),
    );
  }

  Widget _buildUploaded() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: SupyBrand.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 24),
            const Text(
              'Invoice uploaded',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: SupyBrand.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_pages.length} ${_pages.length == 1 ? 'page' : 'pages'}'
              '${_supplier != null ? ' • ${_supplier!.name}' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: SupyBrand.onSurfaceMuted),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(InvoiceConfirmOutcome.uploaded),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReview() {
    final canUpload = _pages.isNotEmpty && _supplier != null && !_uploading;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              _PageCountHeader(count: _pages.length),
              const SizedBox(height: 16),
              _PageGrid(
                pages: _pages,
                onEdit: _editPage,
                onAdd: _addPage,
              ),
              const SizedBox(height: 24),
              const Text(
                'Supplier',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SupyBrand.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              _SupplierDropdown(
                value: _supplier,
                onChanged: (s) => setState(() => _supplier = s),
              ),
            ],
          ),
        ),
        _BottomBar(
          uploading: _uploading,
          canUpload: canUpload,
          onUpload: _upload,
          onRescan: _rescanAll,
        ),
      ],
    );
  }
}

class _PageCountHeader extends StatelessWidget {
  const _PageCountHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: SupyBrand.accentSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count ${count == 1 ? 'page' : 'pages'}',
            style: const TextStyle(
              color: SupyBrand.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Tap a page to rotate, re-scan, or remove it.',
            style: TextStyle(color: SupyBrand.onSurfaceMuted, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _PageGrid extends StatelessWidget {
  const _PageGrid({
    required this.pages,
    required this.onEdit,
    required this.onAdd,
  });

  final List<SupyDocumentPage> pages;
  final void Function(int index) onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.72,
      children: [
        for (var i = 0; i < pages.length; i++)
          _PageTile(
            page: pages[i],
            index: i,
            onTap: () => onEdit(i),
          ),
        _AddPageTile(onTap: onAdd),
      ],
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.index,
    required this.onTap,
  });

  final SupyDocumentPage page;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final file = File(Uri.parse(page.uri).toFilePath());
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: SupyBrand.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x140F1E3A)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: file.existsSync()
                  ? Image.file(file, fit: BoxFit.cover)
                  : Container(
                      color: SupyBrand.surfaceAlt,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: SupyBrand.onSurfaceMuted,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Page ${index + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SupyBrand.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 12, color: SupyBrand.accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPageTile extends StatelessWidget {
  const _AddPageTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SupyBrand.accentSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SupyBrand.accent.withValues(alpha: 0.4)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: SupyBrand.accent),
            SizedBox(height: 6),
            Text(
              'Add page',
              style: TextStyle(
                color: SupyBrand.accent,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierDropdown extends StatelessWidget {
  const _SupplierDropdown({required this.value, required this.onChanged});

  final _Supplier? value;
  final ValueChanged<_Supplier?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: SupyBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x140F1E3A)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_Supplier>(
          isExpanded: true,
          value: value,
          hint: const Text('Select supplier'),
          items: [
            for (final s in _mockSuppliers)
              DropdownMenuItem(value: s, child: Text(s.name)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.uploading,
    required this.canUpload,
    required this.onUpload,
    required this.onRescan,
  });

  final bool uploading;
  final bool canUpload;
  final VoidCallback onUpload;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: SupyBrand.surface,
        border: Border(top: BorderSide(color: Color(0x140F1E3A))),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: uploading ? null : onRescan,
            style: TextButton.styleFrom(foregroundColor: SupyBrand.navy),
            child: const Text(
              'Rescan',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: canUpload ? onUpload : null,
              child: uploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Upload invoice'),
            ),
          ),
        ],
      ),
    );
  }
}
