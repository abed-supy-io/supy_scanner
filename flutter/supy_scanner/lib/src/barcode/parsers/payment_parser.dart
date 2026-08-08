import '../../models/barcode/supy_barcode_document.dart';

/// Parses SEPA GiroCode (EPC069-12) and Swiss QR-bill (SPC) payment payloads.
abstract final class PaymentParser {
  /// Returns a [SupyGiroCodeBarcode] for an EPC "BCD" payload, else `null`.
  static SupyGiroCodeBarcode? tryParseGiroCode(String raw) {
    final lines = _lines(raw);
    if (lines.isEmpty || lines[0].trim() != 'BCD') return null;
    // Fields: 0 BCD, 1 version, 2 charset, 3 SCT, 4 BIC, 5 name, 6 IBAN,
    // 7 amount (e.g. EUR12.5), 8 purpose, 9 ref, 10 text, 11 info.
    if (lines.length < 7) return null;
    final name = _at(lines, 5);
    final iban = _at(lines, 6);
    if (name == null || iban == null) return null;

    final amountField = _at(lines, 7);
    var currency = 'EUR';
    double? amount;
    if (amountField != null && amountField.length > 3) {
      currency = amountField.substring(0, 3);
      amount = double.tryParse(amountField.substring(3));
    }

    return SupyGiroCodeBarcode(
      name: name,
      iban: iban,
      bic: _at(lines, 4),
      amount: amount,
      currency: currency,
      purpose: _at(lines, 8),
      remittanceReference: _at(lines, 9),
      remittanceText: _at(lines, 10),
    );
  }

  /// Returns a [SupySwissQrBillBarcode] for an "SPC" payload, else `null`.
  static SupySwissQrBillBarcode? tryParseSwissQrBill(String raw) {
    final lines = _lines(raw);
    if (lines.isEmpty || lines[0].trim() != 'SPC') return null;
    // Header: 0 SPC, 1 version, 2 coding, 3 IBAN, 4 creditor addr type,
    // 5 creditor name, ... 18 amount, 19 currency, 20 debtor addr type,
    // 21 debtor name, ... 27 ref type, 28 reference, 29 unstructured message.
    final iban = _at(lines, 3);
    final creditor = _at(lines, 5);
    if (iban == null || creditor == null) return null;

    return SupySwissQrBillBarcode(
      iban: iban,
      creditorName: creditor,
      amount: double.tryParse(_at(lines, 18) ?? ''),
      currency: _at(lines, 19) ?? 'CHF',
      debtorName: _at(lines, 21),
      reference: _at(lines, 28),
      additionalInfo: _at(lines, 29),
    );
  }

  static List<String> _lines(String raw) => raw.split(RegExp(r'\r\n|\r|\n'));

  static String? _at(List<String> lines, int i) {
    if (i >= lines.length) return null;
    final v = lines[i].trim();
    return v.isEmpty ? null : v;
  }
}
