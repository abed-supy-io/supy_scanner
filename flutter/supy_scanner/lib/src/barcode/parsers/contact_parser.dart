import '../../models/barcode/supy_barcode_document.dart';

/// Parses vCard and MeCard contact payloads into a [SupyContactBarcode].
abstract final class ContactParser {
  /// Returns a [SupyContactBarcode] for a `BEGIN:VCARD` payload, else `null`.
  static SupyContactBarcode? tryParseVCard(String raw) {
    final upper = raw.trimLeft().toUpperCase();
    if (!upper.startsWith('BEGIN:VCARD')) return null;

    String? formattedName;
    String? firstName;
    String? lastName;
    String? organization;
    String? title;
    String? note;
    final phones = <String>[];
    final emails = <String>[];
    final urls = <String>[];
    final addresses = <String>[];

    for (final rawLine in _unfold(raw)) {
      final colon = rawLine.indexOf(':');
      if (colon < 0) continue;
      final left = rawLine.substring(0, colon);
      final value = rawLine.substring(colon + 1).trim();
      if (value.isEmpty) continue;
      final property = left.split(';').first.toUpperCase();

      switch (property) {
        case 'FN':
          formattedName = value;
        case 'N':
          final parts = value.split(';');
          if (parts.isNotEmpty && parts[0].isNotEmpty) lastName = parts[0];
          if (parts.length > 1 && parts[1].isNotEmpty) firstName = parts[1];
        case 'ORG':
          organization = value.split(';').first;
        case 'TITLE':
          title = value;
        case 'TEL':
          phones.add(value);
        case 'EMAIL':
          emails.add(value);
        case 'URL':
          urls.add(value);
        case 'ADR':
          final joined = value.split(';').where((p) => p.isNotEmpty).join(', ');
          if (joined.isNotEmpty) addresses.add(joined);
        case 'NOTE':
          note = value;
      }
    }

    return SupyContactBarcode(
      formattedName: formattedName,
      firstName: firstName,
      lastName: lastName,
      organization: organization,
      title: title,
      phones: phones,
      emails: emails,
      urls: urls,
      addresses: addresses,
      note: note,
    );
  }

  /// Returns a [SupyContactBarcode] for a `MECARD:` payload, else `null`.
  static SupyContactBarcode? tryParseMeCard(String raw) {
    final trimmed = raw.trimLeft();
    if (!trimmed.toUpperCase().startsWith('MECARD:')) return null;
    final body = trimmed.substring('MECARD:'.length);

    String? firstName;
    String? lastName;
    String? organization;
    String? note;
    final phones = <String>[];
    final emails = <String>[];
    final urls = <String>[];
    final addresses = <String>[];

    for (final entry in _splitMeCard(body)) {
      final colon = entry.indexOf(':');
      if (colon < 0) continue;
      final key = entry.substring(0, colon).toUpperCase();
      final value = entry.substring(colon + 1).trim();
      if (value.isEmpty) continue;

      switch (key) {
        case 'N':
          final parts = value.split(',');
          if (parts.isNotEmpty && parts[0].isNotEmpty) lastName = parts[0];
          if (parts.length > 1 && parts[1].isNotEmpty) firstName = parts[1];
        case 'TEL':
          phones.add(value);
        case 'EMAIL':
          emails.add(value);
        case 'URL':
          urls.add(value);
        case 'ADR':
          addresses.add(value);
        case 'ORG':
          organization = value;
        case 'NOTE':
          note = value;
      }
    }

    final name = [firstName, lastName].where((p) => p != null).join(' ').trim();
    return SupyContactBarcode(
      formattedName: name.isEmpty ? null : name,
      firstName: firstName,
      lastName: lastName,
      organization: organization,
      phones: phones,
      emails: emails,
      urls: urls,
      addresses: addresses,
      note: note,
    );
  }

  /// Splits vCard content into logical lines, joining RFC-6350 folded
  /// continuation lines (those beginning with a space or tab).
  static List<String> _unfold(String raw) {
    final out = <String>[];
    for (final line in raw.split(RegExp(r'\r\n|\r|\n'))) {
      if (line.isEmpty) continue;
      if ((line[0] == ' ' || line[0] == '\t') && out.isNotEmpty) {
        out[out.length - 1] += line.substring(1);
      } else {
        out.add(line);
      }
    }
    return out;
  }

  /// Splits a MeCard body on unescaped `;` separators (`\;` is a literal).
  static List<String> _splitMeCard(String body) {
    final out = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (ch == r'\' && i + 1 < body.length) {
        buffer.write(body[i + 1]);
        i++;
      } else if (ch == ';') {
        out.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) out.add(buffer.toString());
    return out;
  }
}
