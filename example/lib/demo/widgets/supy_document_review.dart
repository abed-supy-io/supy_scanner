import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../../branding/supy_brand.dart';

/// Branded review surface for captured document pages + OCR text.
class SupyDocumentReview extends StatefulWidget {
  const SupyDocumentReview({super.key, required this.data});

  final SupyDocumentData data;

  @override
  State<SupyDocumentReview> createState() => _SupyDocumentReviewState();
}

class _SupyDocumentReviewState extends State<SupyDocumentReview> {
  bool _ocrExpanded = true;

  @override
  Widget build(BuildContext context) {
    final pages = widget.data.pages;
    final ocr = widget.data.ocrText;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text(
              '${pages.length} page${pages.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: SupyBrand.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (ocr.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: SupyBrand.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${ocr.length} OCR chars',
                  style: const TextStyle(
                    color: SupyBrand.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: pages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _PageThumb(page: pages[i], index: i),
          ),
        ),
        const SizedBox(height: 20),
        if (ocr.isNotEmpty)
          Card(
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _ocrExpanded = !_ocrExpanded),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.text_snippet_outlined,
                          color: SupyBrand.navy,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'OCR text',
                          style: TextStyle(
                            color: SupyBrand.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _ocrExpanded ? Icons.expand_less : Icons.expand_more,
                          color: SupyBrand.onSurfaceMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_ocrExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SelectableText(
                      ocr,
                      style: const TextStyle(
                        color: SupyBrand.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PageThumb extends StatelessWidget {
  const _PageThumb({required this.page, required this.index});

  final SupyDocumentPage page;
  final int index;

  @override
  Widget build(BuildContext context) {
    final file = File(Uri.parse(page.uri).toFilePath());
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: SupyBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x140F1E3A)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (file.existsSync())
            Image.file(file, fit: BoxFit.cover)
          else
            Container(
              color: SupyBrand.surfaceAlt,
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_not_supported_outlined,
                color: SupyBrand.onSurfaceMuted,
              ),
            ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: SupyBrand.navy,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: SupyBrand.onNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
