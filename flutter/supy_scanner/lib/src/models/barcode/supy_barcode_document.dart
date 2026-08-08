import 'package:meta/meta.dart';

/// Structured, strongly-typed payload parsed from a [SupyBarcode]'s raw value.
///
/// This is the Supy analogue of Scanbot's `BarcodeDocumentFormat` family: an
/// opt-in interpretation layer over the decoded string. The scanner never
/// returns these directly — call `barcode.parseDocument()` to attempt a parse.
/// A `null` result means the payload matched no known document format and the
/// caller should fall back to the raw [SupyBarcode.rawValue].
///
/// The hierarchy is sealed: switch over it exhaustively.
@immutable
sealed class SupyBarcodeDocument {
  const SupyBarcodeDocument();
}

/// A web/URI link (`http://`, `https://`, or any scheme with an authority).
@immutable
final class SupyUrlBarcode extends SupyBarcodeDocument {
  /// Creates a URL document.
  const SupyUrlBarcode({required this.url, this.title});

  /// The parsed URL.
  final Uri url;

  /// Optional human-readable title (from a `MEBKM:` bookmark payload).
  final String? title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyUrlBarcode && other.url == url && other.title == title;

  @override
  int get hashCode => Object.hash(url, title);

  @override
  String toString() => 'SupyUrlBarcode(url: $url, title: $title)';
}

/// An email address, optionally with a prefilled subject and body
/// (`mailto:` or `MATMSG:`).
@immutable
final class SupyEmailBarcode extends SupyBarcodeDocument {
  /// Creates an email document.
  const SupyEmailBarcode({required this.address, this.subject, this.body});

  /// The recipient address.
  final String address;

  /// Optional prefilled subject line.
  final String? subject;

  /// Optional prefilled message body.
  final String? body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyEmailBarcode &&
          other.address == address &&
          other.subject == subject &&
          other.body == body;

  @override
  int get hashCode => Object.hash(address, subject, body);

  @override
  String toString() =>
      'SupyEmailBarcode(address: $address, subject: $subject, body: $body)';
}

/// A telephone number (`tel:`).
@immutable
final class SupyPhoneBarcode extends SupyBarcodeDocument {
  /// Creates a phone document.
  const SupyPhoneBarcode({required this.number});

  /// The dialable phone number, as encoded (may include `+`).
  final String number;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyPhoneBarcode && other.number == number;

  @override
  int get hashCode => number.hashCode;

  @override
  String toString() => 'SupyPhoneBarcode(number: $number)';
}

/// An SMS message (`sms:` / `smsto:` / `SMSTO:`).
@immutable
final class SupySmsBarcode extends SupyBarcodeDocument {
  /// Creates an SMS document.
  const SupySmsBarcode({required this.number, this.message});

  /// The destination phone number.
  final String number;

  /// Optional prefilled message body.
  final String? message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupySmsBarcode &&
          other.number == number &&
          other.message == message;

  @override
  int get hashCode => Object.hash(number, message);

  @override
  String toString() => 'SupySmsBarcode(number: $number, message: $message)';
}

/// A geographic coordinate (`geo:`).
@immutable
final class SupyGeoBarcode extends SupyBarcodeDocument {
  /// Creates a geo document.
  const SupyGeoBarcode({
    required this.latitude,
    required this.longitude,
    this.query,
  });

  /// Latitude in decimal degrees.
  final double latitude;

  /// Longitude in decimal degrees.
  final double longitude;

  /// Optional free-text query / place label (the `q=` parameter).
  final String? query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyGeoBarcode &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.query == query;

  @override
  int get hashCode => Object.hash(latitude, longitude, query);

  @override
  String toString() =>
      'SupyGeoBarcode(latitude: $latitude, longitude: $longitude, '
      'query: $query)';
}

/// Wi-Fi network credentials (`WIFI:`).
@immutable
final class SupyWifiBarcode extends SupyBarcodeDocument {
  /// Creates a Wi-Fi document.
  const SupyWifiBarcode({
    required this.ssid,
    required this.encryption,
    this.password,
    this.hidden = false,
  });

  /// The network name.
  final String ssid;

  /// The security type.
  final SupyWifiEncryption encryption;

  /// The network password (`null` for open networks).
  final String? password;

  /// Whether the SSID is hidden.
  final bool hidden;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyWifiBarcode &&
          other.ssid == ssid &&
          other.encryption == encryption &&
          other.password == password &&
          other.hidden == hidden;

  @override
  int get hashCode => Object.hash(ssid, encryption, password, hidden);

  @override
  String toString() =>
      'SupyWifiBarcode(ssid: $ssid, encryption: ${encryption.name}, '
      'hidden: $hidden)';
}

/// Wi-Fi security type encoded in a `WIFI:` payload.
enum SupyWifiEncryption {
  /// Open network, no password.
  none,

  /// WEP.
  wep,

  /// WPA / WPA2 / WPA3 personal.
  wpa,

  /// WPA2-Enterprise (`WPA2-EAP`).
  wpa2Enterprise,
}

/// A contact card (`vCard` or `MECARD:`).
@immutable
final class SupyContactBarcode extends SupyBarcodeDocument {
  /// Creates a contact document.
  const SupyContactBarcode({
    this.formattedName,
    this.firstName,
    this.lastName,
    this.organization,
    this.title,
    this.phones = const <String>[],
    this.emails = const <String>[],
    this.urls = const <String>[],
    this.addresses = const <String>[],
    this.note,
  });

  /// The full display name, if present.
  final String? formattedName;

  /// Given name (structured `N` field), if present.
  final String? firstName;

  /// Family name (structured `N` field), if present.
  final String? lastName;

  /// Organization / company.
  final String? organization;

  /// Job title.
  final String? title;

  /// Phone numbers, in encoding order.
  final List<String> phones;

  /// Email addresses, in encoding order.
  final List<String> emails;

  /// URLs, in encoding order.
  final List<String> urls;

  /// Postal addresses, in encoding order.
  final List<String> addresses;

  /// Free-text note.
  final String? note;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyContactBarcode &&
          other.formattedName == formattedName &&
          other.firstName == firstName &&
          other.lastName == lastName &&
          other.organization == organization &&
          other.title == title &&
          _listEquals(other.phones, phones) &&
          _listEquals(other.emails, emails) &&
          _listEquals(other.urls, urls) &&
          _listEquals(other.addresses, addresses) &&
          other.note == note;

  @override
  int get hashCode => Object.hash(
    formattedName,
    firstName,
    lastName,
    organization,
    title,
    Object.hashAll(phones),
    Object.hashAll(emails),
    Object.hashAll(urls),
    Object.hashAll(addresses),
    note,
  );

  @override
  String toString() =>
      'SupyContactBarcode(name: ${formattedName ?? '$firstName $lastName'}, '
      'org: $organization, phones: $phones, emails: $emails)';
}

/// A calendar event (`VEVENT` inside a `BEGIN:VCALENDAR`).
@immutable
final class SupyCalendarEventBarcode extends SupyBarcodeDocument {
  /// Creates a calendar-event document.
  const SupyCalendarEventBarcode({
    this.summary,
    this.location,
    this.description,
    this.start,
    this.end,
  });

  /// The event title (`SUMMARY`).
  final String? summary;

  /// The event location (`LOCATION`).
  final String? location;

  /// The event description (`DESCRIPTION`).
  final String? description;

  /// Start time (`DTSTART`), if parseable.
  final DateTime? start;

  /// End time (`DTEND`), if parseable.
  final DateTime? end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyCalendarEventBarcode &&
          other.summary == summary &&
          other.location == location &&
          other.description == description &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(summary, location, description, start, end);

  @override
  String toString() =>
      'SupyCalendarEventBarcode(summary: $summary, start: $start, '
      'end: $end, location: $location)';
}

/// A SEPA credit-transfer QR ("GiroCode", EPC069-12).
@immutable
final class SupyGiroCodeBarcode extends SupyBarcodeDocument {
  /// Creates a GiroCode document.
  const SupyGiroCodeBarcode({
    required this.name,
    required this.iban,
    this.bic,
    this.amount,
    this.currency = 'EUR',
    this.purpose,
    this.remittanceReference,
    this.remittanceText,
  });

  /// Beneficiary name (field 6).
  final String name;

  /// Beneficiary IBAN (field 7).
  final String iban;

  /// Beneficiary BIC (field 5), if present.
  final String? bic;

  /// Transfer amount in [currency] (field 8, e.g. `12.50`), if present.
  final double? amount;

  /// ISO-4217 currency of [amount]. GiroCode encodes it as `EUR12.5`.
  final String currency;

  /// Purpose code (field 9), if present.
  final String? purpose;

  /// Structured remittance reference (field 10), mutually exclusive with
  /// [remittanceText].
  final String? remittanceReference;

  /// Unstructured remittance text (field 11).
  final String? remittanceText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyGiroCodeBarcode &&
          other.name == name &&
          other.iban == iban &&
          other.bic == bic &&
          other.amount == amount &&
          other.currency == currency &&
          other.purpose == purpose &&
          other.remittanceReference == remittanceReference &&
          other.remittanceText == remittanceText;

  @override
  int get hashCode => Object.hash(
    name,
    iban,
    bic,
    amount,
    currency,
    purpose,
    remittanceReference,
    remittanceText,
  );

  @override
  String toString() =>
      'SupyGiroCodeBarcode(name: $name, iban: $iban, amount: $amount '
      '$currency)';
}

/// A Swiss QR-bill payload (`SPC` header, Swiss Payment Standard).
@immutable
final class SupySwissQrBillBarcode extends SupyBarcodeDocument {
  /// Creates a Swiss QR-bill document.
  const SupySwissQrBillBarcode({
    required this.iban,
    required this.creditorName,
    this.amount,
    this.currency = 'CHF',
    this.debtorName,
    this.reference,
    this.additionalInfo,
  });

  /// Creditor IBAN / QR-IBAN.
  final String iban;

  /// Creditor name.
  final String creditorName;

  /// Amount, if fixed (may be blank for open-amount bills).
  final double? amount;

  /// ISO-4217 currency (`CHF` or `EUR`).
  final String currency;

  /// Ultimate debtor name, if present.
  final String? debtorName;

  /// Payment reference (QRR / SCOR / NON).
  final String? reference;

  /// Unstructured additional information.
  final String? additionalInfo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupySwissQrBillBarcode &&
          other.iban == iban &&
          other.creditorName == creditorName &&
          other.amount == amount &&
          other.currency == currency &&
          other.debtorName == debtorName &&
          other.reference == reference &&
          other.additionalInfo == additionalInfo;

  @override
  int get hashCode => Object.hash(
    iban,
    creditorName,
    amount,
    currency,
    debtorName,
    reference,
    additionalInfo,
  );

  @override
  String toString() =>
      'SupySwissQrBillBarcode(iban: $iban, creditor: $creditorName, '
      'amount: $amount $currency)';
}

/// A GS1 element-string payload (GS1-128, GS1 DataMatrix, GS1 QR, DataBar).
///
/// [elements] maps each recognized Application Identifier to its decoded
/// value. [rawUnknownAis] preserves AI codes that were parsed positionally but
/// are not in the known-AI table, so nothing is silently dropped.
@immutable
final class SupyGs1Barcode extends SupyBarcodeDocument {
  /// Creates a GS1 document.
  const SupyGs1Barcode({
    required this.elements,
    this.rawUnknownAis = const <String, String>{},
  });

  /// Recognized AI → value.
  final Map<SupyGs1ApplicationIdentifier, String> elements;

  /// AI code (string) → value, for AIs outside [SupyGs1ApplicationIdentifier].
  final Map<String, String> rawUnknownAis;

  /// Convenience: the GTIN (AI 01), if present.
  String? get gtin => elements[SupyGs1ApplicationIdentifier.gtin];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyGs1Barcode &&
          _mapEquals(other.elements, elements) &&
          _mapEquals(other.rawUnknownAis, rawUnknownAis);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(elements.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(
      rawUnknownAis.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'SupyGs1Barcode(elements: {${elements.entries.map((e) => '${e.key.name}: ${e.value}').join(', ')}})';
}

/// The GS1 Application Identifiers recognized by [SupyGs1Barcode].
///
/// Each carries its numeric AI [code] and whether it has a [fixedLength]
/// (data length in characters, excluding the AI) — variable-length AIs are
/// terminated by a GS separator or end of payload.
enum SupyGs1ApplicationIdentifier {
  /// (00) Serial Shipping Container Code.
  sscc('00', 18),

  /// (01) Global Trade Item Number.
  gtin('01', 14),

  /// (02) GTIN of contained trade items.
  containedGtin('02', 14),

  /// (10) Batch or lot number (variable, up to 20).
  batchLot('10', null),

  /// (11) Production date (YYMMDD).
  productionDate('11', 6),

  /// (12) Due date (YYMMDD).
  dueDate('12', 6),

  /// (13) Packaging date (YYMMDD).
  packagingDate('13', 6),

  /// (15) Best-before date (YYMMDD).
  bestBeforeDate('15', 6),

  /// (16) Sell-by date (YYMMDD).
  sellByDate('16', 6),

  /// (17) Expiration date (YYMMDD).
  expirationDate('17', 6),

  /// (20) Internal product variant.
  productVariant('20', 2),

  /// (21) Serial number (variable, up to 20).
  serialNumber('21', null),

  /// (240) Additional product identification (variable, up to 30).
  additionalProductId('240', null),

  /// (241) Customer part number (variable, up to 30).
  customerPartNumber('241', null),

  /// (30) Variable count of items (variable, up to 8).
  variableCount('30', null),

  /// (37) Count of trade items in a logistic unit (variable, up to 8).
  itemCount('37', null),

  /// (400) Order number (variable, up to 30).
  orderNumber('400', null),

  /// (410) Ship-to / deliver-to GLN.
  shipToGln('410', 13),

  /// (414) Physical-location GLN.
  locationGln('414', 13),

  /// (8200) Extended packaging URL (variable, up to 70).
  productUrl('8200', null);

  const SupyGs1ApplicationIdentifier(this.code, this.fixedLength);

  /// The numeric AI code as a string (e.g. `'01'`).
  final String code;

  /// The fixed data length in characters, or `null` if variable-length.
  final int? fixedLength;
}

/// An IATA BCBP boarding pass ("M1" bar-coded boarding pass).
///
/// Only the mandatory unique fields plus the first flight leg are surfaced;
/// [legCount] reports how many legs the pass encodes.
@immutable
final class SupyBoardingPassBarcode extends SupyBarcodeDocument {
  /// Creates a boarding-pass document.
  const SupyBoardingPassBarcode({
    required this.passengerName,
    required this.legCount,
    this.pnr,
    this.from,
    this.to,
    this.operatingCarrier,
    this.flightNumber,
    this.julianFlightDate,
    this.cabin,
    this.seat,
    this.sequenceNumber,
  });

  /// Passenger name (`LAST/FIRST`).
  final String passengerName;

  /// Number of flight legs encoded.
  final int legCount;

  /// Booking reference / PNR.
  final String? pnr;

  /// Origin IATA airport code (leg 1).
  final String? from;

  /// Destination IATA airport code (leg 1).
  final String? to;

  /// Operating carrier IATA code (leg 1).
  final String? operatingCarrier;

  /// Flight number (leg 1), trimmed.
  final String? flightNumber;

  /// Day-of-year the flight departs (leg 1), 1–366.
  final int? julianFlightDate;

  /// Compartment / cabin code (leg 1).
  final String? cabin;

  /// Seat number (leg 1), trimmed.
  final String? seat;

  /// Check-in sequence number (leg 1).
  final String? sequenceNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyBoardingPassBarcode &&
          other.passengerName == passengerName &&
          other.legCount == legCount &&
          other.pnr == pnr &&
          other.from == from &&
          other.to == to &&
          other.operatingCarrier == operatingCarrier &&
          other.flightNumber == flightNumber &&
          other.julianFlightDate == julianFlightDate &&
          other.cabin == cabin &&
          other.seat == seat &&
          other.sequenceNumber == sequenceNumber;

  @override
  int get hashCode => Object.hash(
    passengerName,
    legCount,
    pnr,
    from,
    to,
    operatingCarrier,
    flightNumber,
    julianFlightDate,
    cabin,
    seat,
    sequenceNumber,
  );

  @override
  String toString() =>
      'SupyBoardingPassBarcode(passenger: $passengerName, $from→$to, '
      'flight: $operatingCarrier$flightNumber, seat: $seat)';
}

/// An AAMVA driver's-license / ID payload (PDF417 on the back of US/Canadian
/// licenses). Field values are keyed by their 3-letter AAMVA element ID.
@immutable
final class SupyDriverLicenseBarcode extends SupyBarcodeDocument {
  /// Creates a driver's-license document.
  const SupyDriverLicenseBarcode({required this.fields, this.aamvaVersion});

  /// Raw AAMVA element ID → value (e.g. `DAC` → first name).
  final Map<String, String> fields;

  /// The AAMVA standard version byte, if parsed from the header.
  final int? aamvaVersion;

  /// Family name (`DCS`).
  String? get lastName => fields['DCS'];

  /// First name (`DAC` or, on older versions, `DCT`).
  String? get firstName => fields['DAC'] ?? fields['DCT'];

  /// Document / license number (`DAQ`).
  String? get documentNumber => fields['DAQ'];

  /// Date of birth as encoded (`DBB`, `MMDDCCYY` or `CCYYMMDD`).
  String? get dateOfBirth => fields['DBB'];

  /// Expiry date as encoded (`DBA`).
  String? get expiryDate => fields['DBA'];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDriverLicenseBarcode &&
          _mapEquals(other.fields, fields) &&
          other.aamvaVersion == aamvaVersion;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(fields.entries.map((e) => Object.hash(e.key, e.value))),
    aamvaVersion,
  );

  @override
  String toString() =>
      'SupyDriverLicenseBarcode(name: $firstName $lastName, '
      'doc: $documentNumber, dob: $dateOfBirth)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
