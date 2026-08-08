import '../../models/barcode/supy_barcode_document.dart';
import '../../models/ocr/supy_id_document.dart';
import '../../models/ocr/supy_mrz_document.dart';
import '../../models/ocr/supy_recognized_text.dart';

/// Composes an identity document from the individual data-capture sources.
///
/// This is a pure-Dart, on-device aggregation over the DC4 MRZ parser, the DC2
/// AAMVA barcode parser, and DC3 front-side OCR — it performs no I/O and
/// mutates nothing. It normalizes fields across whichever sources are supplied
/// and infers the [SupyIdDocumentType].
abstract final class SupyIdParser {
  /// Composes a [SupyIdDocument] from any combination of an [mrz], a
  /// [driverLicense] barcode, and [frontText] OCR. Returns `null` only when no
  /// source is supplied.
  static SupyIdDocument? compose({
    SupyMrzDocument? mrz,
    SupyDriverLicenseBarcode? driverLicense,
    SupyRecognizedText? frontText,
  }) {
    if (mrz == null && driverLicense == null && frontText == null) return null;
    return SupyIdDocument(
      type: _inferType(mrz, driverLicense),
      mrz: mrz,
      driverLicense: driverLicense,
      frontText: frontText?.fullText,
    );
  }

  /// Infers the document type, preferring the MRZ document-type character.
  static SupyIdDocumentType _inferType(
    SupyMrzDocument? mrz,
    SupyDriverLicenseBarcode? driverLicense,
  ) {
    final code = mrz?.documentType.trim().toUpperCase();
    if (code != null && code.isNotEmpty) {
      switch (code[0]) {
        case 'P':
          return SupyIdDocumentType.passport;
        case 'V':
          return SupyIdDocumentType.visa;
        case 'I':
        case 'A':
        case 'C':
          return SupyIdDocumentType.idCard;
      }
    }
    if (driverLicense != null) return SupyIdDocumentType.driverLicense;
    return SupyIdDocumentType.unknown;
  }
}
