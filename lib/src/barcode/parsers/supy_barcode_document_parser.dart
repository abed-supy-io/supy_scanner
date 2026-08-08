import '../../models/barcode/supy_barcode_document.dart';
import '../../models/supy_barcode.dart';
import 'aamva_parser.dart';
import 'bcbp_parser.dart';
import 'contact_parser.dart';
import 'gs1_parser.dart';
import 'payment_parser.dart';

/// Interprets a decoded barcode string as a strongly-typed
/// [SupyBarcodeDocument].
///
/// The single public entry point is the [SupyBarcodeParse.parseDocument]
/// extension on [SupyBarcode]; this class holds the format detection and the
/// scheme parsers that have no dedicated file.
abstract final class SupyBarcodeDocumentParser {
  /// Attempts to parse [raw] into a document. Returns `null` when the payload
  /// matches no known format — callers fall back to the raw string.
  ///
  /// Detection runs most-specific first so that, e.g., a GiroCode is not
  /// misread as plain text.
  static SupyBarcodeDocument? parse(String raw) {
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();

    // Structured multi-line / prefixed payments and contacts first.
    if (raw.startsWith('BCD\n') || raw.startsWith('BCD\r')) {
      final giro = PaymentParser.tryParseGiroCode(raw);
      if (giro != null) return giro;
    }
    if (raw.startsWith('SPC\n') || raw.startsWith('SPC\r')) {
      final swiss = PaymentParser.tryParseSwissQrBill(raw);
      if (swiss != null) return swiss;
    }
    if (lower.contains('begin:vcard')) {
      final vcard = ContactParser.tryParseVCard(raw);
      if (vcard != null) return vcard;
    }
    if (lower.startsWith('mecard:')) {
      final mecard = ContactParser.tryParseMeCard(raw);
      if (mecard != null) return mecard;
    }
    if (lower.contains('begin:vevent')) {
      final event = _tryParseCalendar(raw);
      if (event != null) return event;
    }
    if (raw.startsWith('@')) {
      final dl = AamvaParser.tryParse(raw);
      if (dl != null) return dl;
    }
    if (raw.startsWith('M') && raw.length >= 60) {
      final pass = BcbpParser.tryParse(raw);
      if (pass != null) return pass;
    }

    // URI schemes.
    if (lower.startsWith('wifi:')) return _tryParseWifi(raw);
    if (lower.startsWith('mailto:')) return _tryParseMailto(raw);
    if (lower.startsWith('matmsg:')) return _tryParseMatMsg(raw);
    if (lower.startsWith('mebkm:')) return _tryParseBookmark(raw);
    if (lower.startsWith('tel:')) {
      final n = raw.substring(4).trim();
      return n.isEmpty ? null : SupyPhoneBarcode(number: n);
    }
    if (lower.startsWith('smsto:') || lower.startsWith('sms:')) {
      return _tryParseSms(raw);
    }
    if (lower.startsWith('geo:')) return _tryParseGeo(raw);

    // GS1 element strings (AIM `]` prefix or a leading recognized AI).
    final gs1 = Gs1Parser.tryParse(raw);
    if (gs1 != null) return gs1;

    // Bare URL / URI with an authority.
    final url = _tryParseUrl(raw);
    if (url != null) return url;

    return null;
  }

  static SupyWifiBarcode? _tryParseWifi(String raw) {
    final fields = _keyValues(raw.substring(raw.indexOf(':') + 1));
    final ssid = fields['S'];
    if (ssid == null || ssid.isEmpty) return null;
    return SupyWifiBarcode(
      ssid: ssid,
      encryption: _wifiEncryption(fields['T']),
      password: fields['P'],
      hidden: (fields['H'] ?? '').toLowerCase() == 'true',
    );
  }

  static SupyWifiEncryption _wifiEncryption(String? t) {
    switch ((t ?? '').toUpperCase()) {
      case 'WEP':
        return SupyWifiEncryption.wep;
      case 'WPA':
      case 'WPA2':
      case 'WPA3':
        return SupyWifiEncryption.wpa;
      case 'WPA2-EAP':
        return SupyWifiEncryption.wpa2Enterprise;
      case 'NOPASS':
      case '':
        return SupyWifiEncryption.none;
      default:
        return SupyWifiEncryption.wpa;
    }
  }

  static SupyEmailBarcode? _tryParseMailto(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final address = uri.path.trim();
    if (address.isEmpty) return null;
    return SupyEmailBarcode(
      address: address,
      subject: uri.queryParameters['subject'],
      body: uri.queryParameters['body'],
    );
  }

  static SupyEmailBarcode? _tryParseMatMsg(String raw) {
    final fields = _keyValues(raw.substring(raw.indexOf(':') + 1));
    final to = fields['TO'];
    if (to == null || to.isEmpty) return null;
    return SupyEmailBarcode(
      address: to,
      subject: fields['SUB'],
      body: fields['BODY'],
    );
  }

  static SupyUrlBarcode? _tryParseBookmark(String raw) {
    final fields = _keyValues(raw.substring(raw.indexOf(':') + 1));
    final url = fields['URL'];
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return SupyUrlBarcode(url: uri, title: fields['TITLE']);
  }

  static SupySmsBarcode? _tryParseSms(String raw) {
    final scheme = raw.substring(0, raw.indexOf(':')).toLowerCase();
    final rest = raw.substring(raw.indexOf(':') + 1);
    if (scheme == 'smsto') {
      // SMSTO:number:message
      final sep = rest.indexOf(':');
      final number = sep < 0 ? rest : rest.substring(0, sep);
      final message = sep < 0 ? null : rest.substring(sep + 1);
      if (number.trim().isEmpty) return null;
      return SupySmsBarcode(
        number: number.trim(),
        message: (message == null || message.isEmpty) ? null : message,
      );
    }
    // sms:number?body=...
    final uri = Uri.tryParse(raw);
    final number = uri?.path.trim() ?? rest.trim();
    if (number.isEmpty) return null;
    return SupySmsBarcode(
      number: number,
      message: uri?.queryParameters['body'],
    );
  }

  static SupyGeoBarcode? _tryParseGeo(String raw) {
    var body = raw.substring(4);
    String? query;
    final q = body.indexOf('?');
    if (q >= 0) {
      final uri = Uri.tryParse(raw);
      query = uri?.queryParameters['q'];
      body = body.substring(0, q);
    }
    final coords = body.split(',');
    if (coords.length < 2) return null;
    final lat = double.tryParse(coords[0]);
    final lon = double.tryParse(coords[1]);
    if (lat == null || lon == null) return null;
    return SupyGeoBarcode(latitude: lat, longitude: lon, query: query);
  }

  static SupyCalendarEventBarcode? _tryParseCalendar(String raw) {
    String? valueOf(String prop) {
      final match = RegExp(
        '^$prop(?:;[^:\r\n]*)?:(.*)\$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(raw);
      final v = match?.group(1)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return SupyCalendarEventBarcode(
      summary: valueOf('SUMMARY'),
      location: valueOf('LOCATION'),
      description: valueOf('DESCRIPTION'),
      start: _icalDate(valueOf('DTSTART')),
      end: _icalDate(valueOf('DTEND')),
    );
  }

  static SupyUrlBarcode? _tryParseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return SupyUrlBarcode(url: uri);
  }

  /// Parses an iCalendar `DTSTART`/`DTEND` value (`YYYYMMDD` or
  /// `YYYYMMDDTHHMMSS` with an optional trailing `Z`) to a [DateTime].
  static DateTime? _icalDate(String? value) {
    if (value == null) return null;
    final m = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2}))?(Z)?$',
    ).firstMatch(value);
    if (m == null) return null;
    final utc = m.group(7) == 'Z';
    int g(int i) => int.parse(m.group(i)!);
    final y = g(1), mo = g(2), d = g(3);
    final hh = m.group(4) != null ? g(4) : 0;
    final mm = m.group(5) != null ? g(5) : 0;
    final ss = m.group(6) != null ? g(6) : 0;
    return utc
        ? DateTime.utc(y, mo, d, hh, mm, ss)
        : DateTime(y, mo, d, hh, mm, ss);
  }

  /// Splits a `KEY:value;KEY:value;;` body (WIFI/MECARD/MATMSG/MEBKM style)
  /// into a map. Backslash-escaped separators (`\;`, `\:`, `\\`) are honored.
  static Map<String, String> _keyValues(String body) {
    final out = <String, String>{};
    final entries = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (ch == r'\' && i + 1 < body.length) {
        buffer.write(body[i + 1]);
        i++;
      } else if (ch == ';') {
        entries.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) entries.add(buffer.toString());

    for (final entry in entries) {
      final colon = entry.indexOf(':');
      if (colon <= 0) continue;
      final key = entry.substring(0, colon).toUpperCase();
      final value = entry.substring(colon + 1);
      if (value.isNotEmpty) out[key] = value;
    }
    return out;
  }
}

/// Adds opt-in structured-payload parsing to [SupyBarcode].
extension SupyBarcodeParse on SupyBarcode {
  /// Interprets [SupyBarcode.rawValue] as a [SupyBarcodeDocument], or returns
  /// `null` if it matches no known format.
  ///
  /// This is a pure-Dart, on-device operation; it performs no I/O and never
  /// mutates the barcode. Mirrors Scanbot's `BarcodeDocumentFormat` concept.
  SupyBarcodeDocument? parseDocument() =>
      SupyBarcodeDocumentParser.parse(rawValue);
}
