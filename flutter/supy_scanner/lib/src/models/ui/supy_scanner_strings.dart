import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import '../supy_document_page.dart';
import 'supy_document_guidance_configuration.dart';

/// The single source of default user-facing copy for the branded scanner UI —
/// the string counterpart to [SupyScannerPalette].
///
/// Every screen, sheet, and overlay resolves its text as
/// `config.field ?? strings.field`, exactly as colors resolve
/// `config.color ?? palette.token`. Ship [SupyScannerStrings.en] or
/// [SupyScannerStrings.ar] (pick automatically with [SupyScannerStrings.of]);
/// override any individual string on the relevant `Supy*Configuration` to
/// deviate from the bundle.
///
/// This is the only place localized default copy lives — do not hardcode
/// user-facing strings in widgets.
@immutable
class SupyScannerStrings {
  /// Creates a fully-specified string bundle. Prefer the [SupyScannerStrings.en]
  /// / [SupyScannerStrings.ar] presets; use this constructor (or [copyWith])
  /// only to assemble a custom bundle.
  const SupyScannerStrings({
    required this.languageCode,
    required this.cancel,
    required this.submit,
    required this.done,
    required this.retry,
    required this.clear,
    required this.reset,
    required this.flash,
    required this.zoom,
    required this.flipCamera,
    required this.closeFocus,
    required this.documentPage,
    required this.deletePage,
    required this.barcodeGuidanceTitle,
    required this.barcodeDetected,
    required this.itemsScanned,
    required this.noItemsYet,
    required this.scansWord,
    required this.uniqueWord,
    required this.pickList,
    required this.noExpectedItems,
    required this.unexpected,
    required this.pickedWord,
    required this.aimAtDocument,
    required this.maxPagesReached,
    required this.capturePage,
    required this.captureFailed,
    required this.importFromGallery,
    required this.unsupportedPlatform,
    required this.brandTitle,
    required this.holdSteady,
    required this.modeSingle,
    required this.modeMulti,
    required this.modeReceipt,
    required this.adjustEdges,
    required this.back,
    required this.continueAction,
    required this.exportAction,
    required this.exportAsPdf,
    required this.addPage,
    required this.pageSingular,
    required this.pagePlural,
    required this.scanDocumentTitle,
    required this.scanInstruction,
    required this.help,
    required this.helpTitle,
    required this.helpBody,
    required this.autoCapture,
    required this.documentHints,
  });

  /// English defaults. Matches the copy Scanbot RTU UI shipped, so an
  /// unlocalized migration reads identically.
  const SupyScannerStrings.en()
    : languageCode = 'en',
      cancel = 'Cancel',
      submit = 'Submit',
      done = 'Done',
      retry = 'Retry',
      clear = 'Clear',
      reset = 'Reset',
      flash = 'Flash',
      zoom = 'Zoom',
      flipCamera = 'Flip camera',
      closeFocus = 'Close-up focus',
      documentPage = 'Page',
      deletePage = 'Delete page',
      barcodeGuidanceTitle = 'Point the camera at a barcode',
      barcodeDetected = 'Barcode detected',
      itemsScanned = 'Items scanned',
      noItemsYet = 'No items yet',
      scansWord = 'scans',
      uniqueWord = 'unique',
      pickList = 'Pick list',
      noExpectedItems = 'No expected items',
      unexpected = 'Unexpected',
      pickedWord = 'picked',
      aimAtDocument = 'Aim at the document',
      maxPagesReached = 'Max pages reached',
      capturePage = 'Capture page',
      captureFailed = "Couldn't capture the page. Try again.",
      importFromGallery = 'Import from gallery',
      unsupportedPlatform = 'Scanning is not supported on this platform.',
      brandTitle = 'supy',
      holdSteady = 'Hold steady',
      modeSingle = 'Single',
      modeMulti = 'Multi',
      modeReceipt = 'Receipt',
      adjustEdges = 'Adjust edges',
      back = 'Back',
      continueAction = 'Continue',
      exportAction = 'Export',
      exportAsPdf = 'Export as PDF',
      addPage = 'Add page',
      pageSingular = 'page',
      pagePlural = 'pages',
      scanDocumentTitle = 'Scan Document',
      scanInstruction = 'Scan each page of your document.',
      help = 'Help',
      helpTitle = 'Scanning tips',
      helpBody =
          'Place the document on a flat, contrasting surface. '
              'Keep the whole page inside the frame and hold the camera '
              'steady and level until the frame turns green.',
      autoCapture = 'Auto',
      documentHints = const SupyDocumentGuidanceHints();

  /// Arabic defaults. Pairs with [textDirection] == [TextDirection.rtl] so the
  /// branded chrome mirrors correctly.
  const SupyScannerStrings.ar()
    : languageCode = 'ar',
      cancel = 'إلغاء',
      submit = 'إرسال',
      done = 'تم',
      retry = 'إعادة المحاولة',
      clear = 'مسح',
      reset = 'إعادة تعيين',
      flash = 'الفلاش',
      zoom = 'تكبير',
      flipCamera = 'قلب الكاميرا',
      closeFocus = 'التركيز القريب',
      documentPage = 'صفحة',
      deletePage = 'حذف الصفحة',
      barcodeGuidanceTitle = 'وجّه الكاميرا نحو الباركود',
      barcodeDetected = 'تم اكتشاف الباركود',
      itemsScanned = 'العناصر الممسوحة',
      noItemsYet = 'لا توجد عناصر بعد',
      scansWord = 'مسح',
      uniqueWord = 'فريد',
      pickList = 'قائمة الانتقاء',
      noExpectedItems = 'لا توجد عناصر متوقعة',
      unexpected = 'غير متوقع',
      pickedWord = 'تم انتقاؤه',
      aimAtDocument = 'وجّه نحو المستند',
      maxPagesReached = 'تم بلوغ الحد الأقصى للصفحات',
      capturePage = 'التقاط الصفحة',
      captureFailed = 'تعذّر التقاط الصفحة. حاول مرة أخرى.',
      importFromGallery = 'استيراد من المعرض',
      unsupportedPlatform = 'المسح غير مدعوم على هذا النظام.',
      brandTitle = 'supy',
      holdSteady = 'ثبّت الكاميرا',
      modeSingle = 'مفردة',
      modeMulti = 'متعددة',
      modeReceipt = 'إيصال',
      adjustEdges = 'ضبط الحواف',
      back = 'رجوع',
      continueAction = 'متابعة',
      exportAction = 'تصدير',
      exportAsPdf = 'تصدير كملف PDF',
      addPage = 'إضافة صفحة',
      pageSingular = 'صفحة',
      pagePlural = 'صفحات',
      scanDocumentTitle = 'مسح المستند',
      scanInstruction = 'امسح كل صفحة من مستندك.',
      help = 'مساعدة',
      helpTitle = 'نصائح المسح',
      helpBody =
          'ضع المستند على سطح مستوٍ ومتباين اللون. '
              'أبقِ الصفحة بالكامل داخل الإطار وامسك الكاميرا '
              'ثابتة ومستوية حتى يتحول الإطار إلى اللون الأخضر.',
      autoCapture = 'تلقائي',
      documentHints = const SupyDocumentGuidanceHints.ar();

  /// Returns the bundle for [languageCode] — [SupyScannerStrings.ar] for
  /// `'ar'`, [SupyScannerStrings.en] for everything else (including null). The
  /// language code is what `Localizations.maybeLocaleOf(context)?.languageCode`
  /// returns.
  factory SupyScannerStrings.of(String? languageCode) =>
      languageCode == 'ar'
          ? const SupyScannerStrings.ar()
          : const SupyScannerStrings.en();

  /// BCP-47 language subtag this bundle carries (`'en'` / `'ar'`). Drives
  /// [textDirection] and equality.
  final String languageCode;

  /// Cancel-button label (top bar, document top bar).
  final String cancel;

  /// Primary submit-button label (single-scan confirmation, multi-scan sheet).
  final String submit;

  /// Primary confirm label for find-and-pick, and the document done button.
  final String done;

  /// Retry-button label on the single-scan confirmation sheet.
  final String retry;

  /// Clear-button label on the multi-scan sheet.
  final String clear;

  /// Reset-button label on the find-and-pick sheet, and on the document
  /// "Adjust edges" editor.
  final String reset;

  /// Flash / torch toggle label (document top bar, action bar).
  final String flash;

  /// Accessibility label for the action-bar zoom control. Combined with the
  /// live zoom factor by [zoomLabel].
  final String zoom;

  /// Accessibility label for the action-bar flip-camera control.
  final String flipCamera;

  /// Accessibility label for the action-bar close-up (macro) focus-lock control.
  final String closeFocus;

  /// Base noun for a captured document page. Combined with the 1-based page
  /// number by [documentPageLabel].
  final String documentPage;

  /// Base label for the document page-tray delete control. Combined with the
  /// 1-based page number by [deletePageLabel].
  final String deletePage;

  /// Live-guidance title shown over the barcode camera preview.
  final String barcodeGuidanceTitle;

  /// Title on the single-scan confirmation sheet.
  final String barcodeDetected;

  /// Title on the multi-scan sheet header.
  final String itemsScanned;

  /// Empty-state line on the multi-scan sheet body.
  final String noItemsYet;

  /// Noun used in the multi-scan counting summary (e.g. `12 scans`). Built by
  /// [scanCountSummary].
  final String scansWord;

  /// Noun used in the multi-scan / find-and-pick summaries (e.g. `3 unique`).
  /// Built by [scanCountSummary] / [uniqueSummary].
  final String uniqueWord;

  /// Title on the find-and-pick sheet header.
  final String pickList;

  /// Empty-state line on the find-and-pick sheet body.
  final String noExpectedItems;

  /// Section header for detected payloads that aren't on the pick-list.
  final String unexpected;

  /// Verb used in the find-and-pick progress line (e.g. `2/5 picked`). Built by
  /// [pickedProgress].
  final String pickedWord;

  /// Live-guidance title shown over the document camera preview.
  final String aimAtDocument;

  /// Banner shown when the document page cap is hit.
  final String maxPagesReached;

  /// Accessibility label for the document capture shutter button.
  final String capturePage;

  /// Feedback shown when a shutter tap fails to produce a page (e.g. no frame
  /// could be captured). Keeps the shutter from ever failing silently.
  final String captureFailed;

  /// Label / accessibility text for the document gallery-import control that
  /// opens the platform photo picker.
  final String importFromGallery;

  /// Placeholder shown when a scanner view is built on an unsupported platform.
  final String unsupportedPlatform;

  /// Brand wordmark shown centered in the document viewfinder top bar.
  final String brandTitle;

  /// Steadiness prompt pill shown under the viewfinder frame while aiming.
  final String holdSteady;

  /// Document capture-mode tab: capture one page, then go straight to review.
  final String modeSingle;

  /// Document capture-mode tab: accumulate many pages before review.
  final String modeMulti;

  /// Document capture-mode tab: receipt-tuned capture (tall frame).
  final String modeReceipt;

  /// Title of the per-page crop / edges editor.
  final String adjustEdges;

  /// Back-navigation label (edges editor + page review top bars).
  final String back;

  /// Primary "accept this page" action on the edges editor.
  final String continueAction;

  /// Top-bar finish action on the page-review screen.
  final String exportAction;

  /// Full-width terminal action on the page-review screen. Returns the captured
  /// page images to the host (see the Phase 9 decision in `TODO.md`): a branded
  /// finish label, not a PDF-generation step.
  final String exportAsPdf;

  /// Label for the "add another page" affordances (editor FAB, review tile).
  final String addPage;

  /// Singular page noun used by [pagesCountLabel] (e.g. `1 page`).
  final String pageSingular;

  /// Plural page noun used by [pagesCountLabel] (e.g. `3 pages`).
  final String pagePlural;

  /// Center title in the branded document scanner top bar (e.g. Scanbot's
  /// "Scan Document").
  final String scanDocumentTitle;

  /// Instruction banner shown under the top bar in the document scanner.
  final String scanInstruction;

  /// Accessibility label for the document scanner help ("?") button.
  final String help;

  /// Title of the document scanner help sheet.
  final String helpTitle;

  /// Body copy of the document scanner help sheet.
  final String helpBody;

  /// Label for the document scanner auto-capture toggle.
  final String autoCapture;

  /// Per-state document-guidance hint copy for this locale. Consumed when a
  /// [SupyDocumentGuidanceConfiguration] leaves its `hints` unset.
  final SupyDocumentGuidanceHints documentHints;

  /// Layout direction implied by [languageCode]. Wrap the branded scanner
  /// chrome in a `Directionality` using this so Arabic mirrors correctly.
  TextDirection get textDirection =>
      languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

  /// Multi-scan counting summary, e.g. `12 scans · 3 unique`.
  String scanCountSummary(int total, int unique) =>
      '$total $scansWord · $unique $uniqueWord';

  /// Multi-scan unique-mode summary, e.g. `3 unique`.
  String uniqueSummary(int unique) => '$unique $uniqueWord';

  /// Find-and-pick progress line, e.g. `2/5 picked`.
  String pickedProgress(int completed, int total) =>
      '$completed/$total $pickedWord';

  /// Accessibility label for the zoom control at the given factor, e.g.
  /// `Zoom 2x`. Falls back to bare [zoom] at 1× (no visible factor).
  String zoomLabel(String? factor) => factor == null ? zoom : '$zoom $factor';

  /// Accessibility label for a page-tray thumbnail, e.g. `Page 3`.
  String documentPageLabel(int page) => '$documentPage $page';

  /// Accessibility label for a page-tray delete control, e.g. `Delete page 3`.
  String deletePageLabel(int page) => '$deletePage $page';

  /// Page-count title for the review screen, e.g. `3 pages` / `1 page`.
  /// Arabic applies singular/dual/plural agreement.
  String pagesCountLabel(int count) {
    if (languageCode == 'ar') {
      if (count == 1) return 'صفحة واحدة';
      if (count == 2) return 'صفحتان';
      if (count >= 3 && count <= 10) return '$count $pagePlural';
      return '$count $pageSingular';
    }
    return '$count ${count == 1 ? pageSingular : pagePlural}';
  }

  /// Short, user-facing label for a captured page's quality bucket, shown on
  /// the review-grid quality badge. Informational only - never gates capture.
  String documentQualityLabel(SupyDocumentPageQuality quality) {
    if (languageCode == 'ar') {
      switch (quality) {
        case SupyDocumentPageQuality.veryPoor:
          return 'رديئة جدًا';
        case SupyDocumentPageQuality.poor:
          return 'رديئة';
        case SupyDocumentPageQuality.ok:
          return 'مقبولة';
        case SupyDocumentPageQuality.good:
          return 'جيدة';
        case SupyDocumentPageQuality.excellent:
          return 'ممتازة';
      }
    }
    switch (quality) {
      case SupyDocumentPageQuality.veryPoor:
        return 'Very poor';
      case SupyDocumentPageQuality.poor:
        return 'Poor';
      case SupyDocumentPageQuality.ok:
        return 'OK';
      case SupyDocumentPageQuality.good:
        return 'Good';
      case SupyDocumentPageQuality.excellent:
        return 'Excellent';
    }
  }

  /// Returns a copy with the given fields replaced.
  SupyScannerStrings copyWith({
    String? languageCode,
    String? cancel,
    String? submit,
    String? done,
    String? retry,
    String? clear,
    String? reset,
    String? flash,
    String? zoom,
    String? flipCamera,
    String? closeFocus,
    String? documentPage,
    String? deletePage,
    String? barcodeGuidanceTitle,
    String? barcodeDetected,
    String? itemsScanned,
    String? noItemsYet,
    String? scansWord,
    String? uniqueWord,
    String? pickList,
    String? noExpectedItems,
    String? unexpected,
    String? pickedWord,
    String? aimAtDocument,
    String? maxPagesReached,
    String? capturePage,
    String? captureFailed,
    String? importFromGallery,
    String? unsupportedPlatform,
    String? brandTitle,
    String? holdSteady,
    String? modeSingle,
    String? modeMulti,
    String? modeReceipt,
    String? adjustEdges,
    String? back,
    String? continueAction,
    String? exportAction,
    String? exportAsPdf,
    String? addPage,
    String? pageSingular,
    String? pagePlural,
    String? scanDocumentTitle,
    String? scanInstruction,
    String? help,
    String? helpTitle,
    String? helpBody,
    String? autoCapture,
    SupyDocumentGuidanceHints? documentHints,
  }) {
    return SupyScannerStrings(
      languageCode: languageCode ?? this.languageCode,
      cancel: cancel ?? this.cancel,
      submit: submit ?? this.submit,
      done: done ?? this.done,
      retry: retry ?? this.retry,
      clear: clear ?? this.clear,
      reset: reset ?? this.reset,
      flash: flash ?? this.flash,
      zoom: zoom ?? this.zoom,
      flipCamera: flipCamera ?? this.flipCamera,
      closeFocus: closeFocus ?? this.closeFocus,
      documentPage: documentPage ?? this.documentPage,
      deletePage: deletePage ?? this.deletePage,
      barcodeGuidanceTitle: barcodeGuidanceTitle ?? this.barcodeGuidanceTitle,
      barcodeDetected: barcodeDetected ?? this.barcodeDetected,
      itemsScanned: itemsScanned ?? this.itemsScanned,
      noItemsYet: noItemsYet ?? this.noItemsYet,
      scansWord: scansWord ?? this.scansWord,
      uniqueWord: uniqueWord ?? this.uniqueWord,
      pickList: pickList ?? this.pickList,
      noExpectedItems: noExpectedItems ?? this.noExpectedItems,
      unexpected: unexpected ?? this.unexpected,
      pickedWord: pickedWord ?? this.pickedWord,
      aimAtDocument: aimAtDocument ?? this.aimAtDocument,
      maxPagesReached: maxPagesReached ?? this.maxPagesReached,
      capturePage: capturePage ?? this.capturePage,
      captureFailed: captureFailed ?? this.captureFailed,
      importFromGallery: importFromGallery ?? this.importFromGallery,
      unsupportedPlatform: unsupportedPlatform ?? this.unsupportedPlatform,
      brandTitle: brandTitle ?? this.brandTitle,
      holdSteady: holdSteady ?? this.holdSteady,
      modeSingle: modeSingle ?? this.modeSingle,
      modeMulti: modeMulti ?? this.modeMulti,
      modeReceipt: modeReceipt ?? this.modeReceipt,
      adjustEdges: adjustEdges ?? this.adjustEdges,
      back: back ?? this.back,
      continueAction: continueAction ?? this.continueAction,
      exportAction: exportAction ?? this.exportAction,
      exportAsPdf: exportAsPdf ?? this.exportAsPdf,
      addPage: addPage ?? this.addPage,
      pageSingular: pageSingular ?? this.pageSingular,
      pagePlural: pagePlural ?? this.pagePlural,
      scanDocumentTitle: scanDocumentTitle ?? this.scanDocumentTitle,
      scanInstruction: scanInstruction ?? this.scanInstruction,
      help: help ?? this.help,
      helpTitle: helpTitle ?? this.helpTitle,
      helpBody: helpBody ?? this.helpBody,
      autoCapture: autoCapture ?? this.autoCapture,
      documentHints: documentHints ?? this.documentHints,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyScannerStrings &&
          other.languageCode == languageCode &&
          other.cancel == cancel &&
          other.submit == submit &&
          other.done == done &&
          other.retry == retry &&
          other.clear == clear &&
          other.reset == reset &&
          other.flash == flash &&
          other.zoom == zoom &&
          other.flipCamera == flipCamera &&
          other.closeFocus == closeFocus &&
          other.documentPage == documentPage &&
          other.deletePage == deletePage &&
          other.barcodeGuidanceTitle == barcodeGuidanceTitle &&
          other.barcodeDetected == barcodeDetected &&
          other.itemsScanned == itemsScanned &&
          other.noItemsYet == noItemsYet &&
          other.scansWord == scansWord &&
          other.uniqueWord == uniqueWord &&
          other.pickList == pickList &&
          other.noExpectedItems == noExpectedItems &&
          other.unexpected == unexpected &&
          other.pickedWord == pickedWord &&
          other.aimAtDocument == aimAtDocument &&
          other.maxPagesReached == maxPagesReached &&
          other.capturePage == capturePage &&
          other.captureFailed == captureFailed &&
          other.importFromGallery == importFromGallery &&
          other.unsupportedPlatform == unsupportedPlatform &&
          other.brandTitle == brandTitle &&
          other.holdSteady == holdSteady &&
          other.modeSingle == modeSingle &&
          other.modeMulti == modeMulti &&
          other.modeReceipt == modeReceipt &&
          other.adjustEdges == adjustEdges &&
          other.back == back &&
          other.continueAction == continueAction &&
          other.exportAction == exportAction &&
          other.exportAsPdf == exportAsPdf &&
          other.addPage == addPage &&
          other.pageSingular == pageSingular &&
          other.pagePlural == pagePlural &&
          other.scanDocumentTitle == scanDocumentTitle &&
          other.scanInstruction == scanInstruction &&
          other.help == help &&
          other.helpTitle == helpTitle &&
          other.helpBody == helpBody &&
          other.autoCapture == autoCapture &&
          other.documentHints == documentHints;

  @override
  int get hashCode => Object.hashAll([
    languageCode,
    cancel,
    submit,
    done,
    retry,
    clear,
    reset,
    flash,
    zoom,
    flipCamera,
    closeFocus,
    documentPage,
    deletePage,
    barcodeGuidanceTitle,
    barcodeDetected,
    itemsScanned,
    noItemsYet,
    scansWord,
    uniqueWord,
    pickList,
    noExpectedItems,
    unexpected,
    pickedWord,
    aimAtDocument,
    maxPagesReached,
    capturePage,
    captureFailed,
    importFromGallery,
    unsupportedPlatform,
    brandTitle,
    holdSteady,
    modeSingle,
    modeMulti,
    modeReceipt,
    adjustEdges,
    back,
    continueAction,
    exportAction,
    exportAsPdf,
    addPage,
    pageSingular,
    pagePlural,
    scanDocumentTitle,
    scanInstruction,
    help,
    helpTitle,
    helpBody,
    autoCapture,
    documentHints,
  ]);

  @override
  String toString() => 'SupyScannerStrings($languageCode)';
}
