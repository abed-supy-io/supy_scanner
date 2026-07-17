import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:supy_scanner/supy_scanner.dart';

import '../../branding/supy_brand.dart';
import 'invoice_capture_screen.dart';

/// Outcome of the per-page editor, returned via `Navigator.pop`.
class InvoicePageEditResult {
  const InvoicePageEditResult._({this.page, this.removed = false});

  /// The user edited (rotated / re-scanned) the page; carries the new page.
  const InvoicePageEditResult.updated(SupyDocumentPage page)
    : this._(page: page);

  /// The user removed the page.
  const InvoicePageEditResult.removed() : this._(removed: true);

  /// Updated page, or `null` when [removed].
  final SupyDocumentPage? page;

  /// Whether the page was removed.
  final bool removed;
}

/// Full edit path for a single captured invoice page.
///
/// Crop on the embedded path is the auto-dewarp the scanner already runs, so
/// "re-crop" is a re-scan; rotate re-encodes the JPEG on-device; remove drops
/// the page. No paid SDK, no network — all on-device.
class InvoicePageEditor extends StatefulWidget {
  const InvoicePageEditor({super.key, required this.page, required this.index});

  final SupyDocumentPage page;
  final int index;

  @override
  State<InvoicePageEditor> createState() => _InvoicePageEditorState();
}

class _InvoicePageEditorState extends State<InvoicePageEditor> {
  late SupyDocumentPage _page = widget.page;
  bool _busy = false;

  File get _file => File(Uri.parse(_page.uri).toFilePath());

  Future<void> _rotate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw const FormatException('Cannot decode page');
      final rotated = img.copyRotate(decoded, angle: 90);
      final out = File(
        '${_file.parent.path}/rot_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(img.encodeJpg(rotated, quality: 92));
      if (!mounted) return;
      setState(() {
        _page = SupyDocumentPage(
          uri: Uri.file(out.path).toString(),
          width: rotated.width,
          height: rotated.height,
          quality: _page.quality,
          qualityScore: _page.qualityScore,
          enhancedStages: _page.enhancedStages,
          enhanceMs: _page.enhanceMs,
        );
      });
    } on Object catch (e) {
      _snack('Rotate failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rescan() async {
    final result = await Navigator.of(context).push<List<SupyDocumentPage>>(
      MaterialPageRoute(
        builder: (_) => const InvoiceCaptureScreen(singlePage: true),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() => _page = result.first);
  }

  void _remove() {
    Navigator.of(context).pop(const InvoicePageEditResult.removed());
  }

  void _save() {
    Navigator.of(context).pop(InvoicePageEditResult.updated(_page));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Page ${widget.index + 1}'),
          actions: [
            TextButton(
              onPressed: _save,
              style: TextButton.styleFrom(foregroundColor: SupyBrand.onNavy),
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: SupyBrand.surfaceAlt,
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                child:
                    _file.existsSync()
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(_file, fit: BoxFit.contain),
                        )
                        : const Icon(
                          Icons.image_not_supported_outlined,
                          color: SupyBrand.onSurfaceMuted,
                          size: 48,
                        ),
              ),
            ),
            if (_page.quality != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Quality: ${_page.quality!.name}'
                    '${_page.qualityScore != null ? ' (${_page.qualityScore!.toStringAsFixed(2)})' : ''}',
                    style: const TextStyle(
                      color: SupyBrand.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                children: [
                  _EditAction(
                    icon: Icons.rotate_right,
                    label: 'Rotate',
                    onTap: _busy ? null : _rotate,
                  ),
                  _EditAction(
                    icon: Icons.crop_rotate,
                    label: 'Re-scan',
                    onTap: _busy ? null : _rescan,
                  ),
                  _EditAction(
                    icon: Icons.delete_outline,
                    label: 'Remove',
                    color: SupyBrand.critical,
                    onTap: _busy ? null : _remove,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditAction extends StatelessWidget {
  const _EditAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = SupyBrand.navy,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(
                icon,
                color: onTap == null ? SupyBrand.onSurfaceMuted : color,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null ? SupyBrand.onSurfaceMuted : color,
                  fontWeight: FontWeight.w600,
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
