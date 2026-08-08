import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyScannerStrings presets', () {
    test('en is LTR and carries English copy', () {
      const s = SupyScannerStrings.en();
      expect(s.languageCode, 'en');
      expect(s.textDirection, TextDirection.ltr);
      expect(s.cancel, 'Cancel');
      expect(s.pickList, 'Pick list');
      expect(
        s.unsupportedPlatform,
        'Scanning is not supported on this platform.',
      );
    });

    test('en carries the accessibility-label base copy', () {
      const s = SupyScannerStrings.en();
      expect(s.flash, 'Flash');
      expect(s.zoom, 'Zoom');
      expect(s.flipCamera, 'Flip camera');
      expect(s.closeFocus, 'Close-up focus');
      expect(s.documentPage, 'Page');
      expect(s.deletePage, 'Delete page');
    });

    test('en carries the document capture + import copy', () {
      const s = SupyScannerStrings.en();
      expect(s.capturePage, 'Capture page');
      expect(s.importFromGallery, 'Import from gallery');
    });

    test('ar carries the document capture + import copy', () {
      const s = SupyScannerStrings.ar();
      expect(s.capturePage, 'التقاط الصفحة');
      expect(s.importFromGallery, 'استيراد من المعرض');
    });

    test('ar is RTL and carries Arabic copy', () {
      const s = SupyScannerStrings.ar();
      expect(s.languageCode, 'ar');
      expect(s.textDirection, TextDirection.rtl);
      expect(s.cancel, 'إلغاء');
      expect(s.pickList, 'قائمة الانتقاء');
    });

    test('ar carries the accessibility-label base copy', () {
      const s = SupyScannerStrings.ar();
      expect(s.zoom, 'تكبير');
      expect(s.flipCamera, 'قلب الكاميرا');
      expect(s.closeFocus, 'التركيز القريب');
      expect(s.documentPage, 'صفحة');
      expect(s.deletePage, 'حذف الصفحة');
    });

    test('en and ar are distinct bundles', () {
      expect(
        const SupyScannerStrings.en(),
        isNot(const SupyScannerStrings.ar()),
      );
    });
  });

  group('SupyScannerStrings.of', () {
    test('selects the Arabic bundle for ar', () {
      expect(SupyScannerStrings.of('ar'), const SupyScannerStrings.ar());
    });

    test('falls back to English for null, en, and unknown codes', () {
      expect(SupyScannerStrings.of(null), const SupyScannerStrings.en());
      expect(SupyScannerStrings.of('en'), const SupyScannerStrings.en());
      expect(SupyScannerStrings.of('fr'), const SupyScannerStrings.en());
    });
  });

  group('SupyScannerStrings format helpers', () {
    test('scanCountSummary joins total + unique with the locale nouns', () {
      expect(
        const SupyScannerStrings.en().scanCountSummary(12, 3),
        '12 scans · 3 unique',
      );
    });

    test('uniqueSummary uses the locale noun', () {
      expect(const SupyScannerStrings.en().uniqueSummary(3), '3 unique');
    });

    test('pickedProgress renders completed/total + verb', () {
      expect(const SupyScannerStrings.en().pickedProgress(2, 5), '2/5 picked');
    });

    test('helpers respect the Arabic nouns', () {
      const ar = SupyScannerStrings.ar();
      expect(ar.uniqueSummary(3), '3 ${ar.uniqueWord}');
      expect(ar.pickedProgress(2, 5), '2/5 ${ar.pickedWord}');
    });

    test('zoomLabel appends the factor, or falls back to bare zoom at 1x', () {
      const s = SupyScannerStrings.en();
      expect(s.zoomLabel('2x'), 'Zoom 2x');
      expect(s.zoomLabel(null), 'Zoom');
    });

    test('documentPageLabel + deletePageLabel render the 1-based page', () {
      const s = SupyScannerStrings.en();
      expect(s.documentPageLabel(3), 'Page 3');
      expect(s.deletePageLabel(3), 'Delete page 3');
    });

    test('label helpers respect the Arabic nouns', () {
      const ar = SupyScannerStrings.ar();
      expect(ar.zoomLabel('2x'), 'تكبير 2x');
      expect(ar.documentPageLabel(2), 'صفحة 2');
      expect(ar.deletePageLabel(2), 'حذف الصفحة 2');
    });
  });

  group('SupyScannerStrings copyWith + equality', () {
    test('copyWith overrides a single field and preserves the rest', () {
      const base = SupyScannerStrings.en();
      final custom = base.copyWith(cancel: 'Dismiss');
      expect(custom.cancel, 'Dismiss');
      expect(custom.done, base.done);
      expect(custom, isNot(base));
    });

    test('value equality + hashCode over presets', () {
      expect(const SupyScannerStrings.en(), const SupyScannerStrings.en());
      expect(
        const SupyScannerStrings.en().hashCode,
        const SupyScannerStrings.en().hashCode,
      );
    });

    test('copyWith round-trips the accessibility-label fields', () {
      const base = SupyScannerStrings.en();
      final custom = base.copyWith(
        zoom: 'Magnify',
        flipCamera: 'Switch camera',
        closeFocus: 'Macro',
        documentPage: 'Sheet',
        deletePage: 'Remove sheet',
      );
      expect(custom.zoom, 'Magnify');
      expect(custom.flipCamera, 'Switch camera');
      expect(custom.closeFocus, 'Macro');
      expect(custom.documentPageLabel(1), 'Sheet 1');
      expect(custom.deletePageLabel(1), 'Remove sheet 1');
      expect(custom, isNot(base));
      expect(custom.hashCode, isNot(base.hashCode));
    });
  });
}
