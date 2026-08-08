import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// GS1 group separator (ASCII 29).
const String gs = '\u001d';

SupyBarcodeDocument? parse(String raw) =>
    SupyBarcode(rawValue: raw, format: SupyBarcodeFormat.qr).parseDocument();

void main() {
  group('URL / URI schemes', () {
    test('parses a bare https URL', () {
      final doc = parse('https://supy.io/scan?ref=1');
      expect(doc, isA<SupyUrlBarcode>());
      expect((doc! as SupyUrlBarcode).url.host, 'supy.io');
    });

    test('does not treat plain text as a URL', () {
      expect(parse('just some text'), isNull);
    });

    test('parses a MEBKM bookmark with title', () {
      final doc = parse('MEBKM:TITLE:Supy;URL:https://supy.io;;');
      expect(doc, isA<SupyUrlBarcode>());
      final url = doc! as SupyUrlBarcode;
      expect(url.title, 'Supy');
      expect(url.url.toString(), 'https://supy.io');
    });

    test('parses mailto with subject and body', () {
      final doc = parse('mailto:a@b.com?subject=Hi&body=There');
      expect(doc, isA<SupyEmailBarcode>());
      final email = doc! as SupyEmailBarcode;
      expect(email.address, 'a@b.com');
      expect(email.subject, 'Hi');
      expect(email.body, 'There');
    });

    test('parses MATMSG email', () {
      final doc = parse('MATMSG:TO:a@b.com;SUB:Order;BODY:Please ship;;');
      final email = doc! as SupyEmailBarcode;
      expect(email.address, 'a@b.com');
      expect(email.subject, 'Order');
      expect(email.body, 'Please ship');
    });

    test('parses tel', () {
      final doc = parse('tel:+14155550123');
      expect((doc! as SupyPhoneBarcode).number, '+14155550123');
    });

    test('parses SMSTO with message', () {
      final doc = parse('SMSTO:+14155550123:Call me');
      final sms = doc! as SupySmsBarcode;
      expect(sms.number, '+14155550123');
      expect(sms.message, 'Call me');
    });

    test('parses geo with query', () {
      final doc = parse('geo:37.7749,-122.4194?q=SF');
      final geo = doc! as SupyGeoBarcode;
      expect(geo.latitude, closeTo(37.7749, 1e-9));
      expect(geo.longitude, closeTo(-122.4194, 1e-9));
      expect(geo.query, 'SF');
    });
  });

  group('WiFi', () {
    test('parses WPA network', () {
      final doc = parse('WIFI:T:WPA;S:SupyGuest;P:s3cret;H:false;;');
      final wifi = doc! as SupyWifiBarcode;
      expect(wifi.ssid, 'SupyGuest');
      expect(wifi.encryption, SupyWifiEncryption.wpa);
      expect(wifi.password, 's3cret');
      expect(wifi.hidden, isFalse);
    });

    test('parses open (nopass) hidden network', () {
      final doc = parse('WIFI:S:OpenNet;T:nopass;H:true;;');
      final wifi = doc! as SupyWifiBarcode;
      expect(wifi.encryption, SupyWifiEncryption.none);
      expect(wifi.hidden, isTrue);
      expect(wifi.password, isNull);
    });
  });

  group('Contacts', () {
    test('parses a vCard', () {
      const raw =
          'BEGIN:VCARD\n'
          'VERSION:3.0\n'
          'N:Doe;Jane;;;\n'
          'FN:Jane Doe\n'
          'ORG:Supy;Engineering\n'
          'TITLE:Engineer\n'
          'TEL;TYPE=CELL:+14155550123\n'
          'EMAIL:jane@supy.io\n'
          'URL:https://supy.io\n'
          'NOTE:VIP\n'
          'END:VCARD';
      final c = parse(raw)! as SupyContactBarcode;
      expect(c.formattedName, 'Jane Doe');
      expect(c.firstName, 'Jane');
      expect(c.lastName, 'Doe');
      expect(c.organization, 'Supy');
      expect(c.title, 'Engineer');
      expect(c.phones, ['+14155550123']);
      expect(c.emails, ['jane@supy.io']);
      expect(c.urls, ['https://supy.io']);
      expect(c.note, 'VIP');
    });

    test('parses a MeCard', () {
      const raw = 'MECARD:N:Doe,Jane;TEL:14155550123;EMAIL:jane@supy.io;;';
      final c = parse(raw)! as SupyContactBarcode;
      expect(c.lastName, 'Doe');
      expect(c.firstName, 'Jane');
      expect(c.formattedName, 'Jane Doe');
      expect(c.phones, ['14155550123']);
      expect(c.emails, ['jane@supy.io']);
    });
  });

  group('Calendar', () {
    test('parses a VEVENT with UTC times', () {
      const raw =
          'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'SUMMARY:Stock count\n'
          'LOCATION:Warehouse 3\n'
          'DTSTART:20260807T090000Z\n'
          'DTEND:20260807T100000Z\n'
          'END:VEVENT\n'
          'END:VCALENDAR';
      final e = parse(raw)! as SupyCalendarEventBarcode;
      expect(e.summary, 'Stock count');
      expect(e.location, 'Warehouse 3');
      expect(e.start, DateTime.utc(2026, 8, 7, 9));
      expect(e.end, DateTime.utc(2026, 8, 7, 10));
    });
  });

  group('Payments', () {
    test('parses a SEPA GiroCode', () {
      const raw =
          'BCD\n'
          '002\n'
          '1\n'
          'SCT\n'
          'BFSWDE33BER\n'
          'Red Cross\n'
          'DE91100000000123456789\n'
          'EUR12.50\n'
          'CHAR\n'
          '\n'
          'Donation\n';
      final g = parse(raw)! as SupyGiroCodeBarcode;
      expect(g.name, 'Red Cross');
      expect(g.iban, 'DE91100000000123456789');
      expect(g.bic, 'BFSWDE33BER');
      expect(g.amount, 12.50);
      expect(g.currency, 'EUR');
      expect(g.remittanceText, 'Donation');
    });

    test('parses a Swiss QR-bill', () {
      const raw =
          'SPC\n'
          '0200\n'
          '1\n'
          'CH4431999123000889012\n'
          'S\n'
          'Robert Schneider AG\n'
          'Rue du Lac\n'
          '1268\n'
          '2501\n'
          'Biel\n'
          'CH\n'
          '\n' // ultimate creditor block (7 empty lines 11-17)
          '\n'
          '\n'
          '\n'
          '\n'
          '\n'
          '\n'
          '3949.75\n' // 18 amount
          'CHF\n' // 19 currency
          'S\n' // 20 debtor addr type
          'Pia-Maria Rutschmann\n' // 21 debtor name
          'Grosse Marktgasse\n'
          '28\n'
          '9400\n'
          'Rorschach\n'
          'CH\n'
          'QRR\n' // 27 ref type
          '210000000003139471430009017\n' // 28 reference
          'Order 24\n'; // 29 unstructured message
      final s = parse(raw)! as SupySwissQrBillBarcode;
      expect(s.iban, 'CH4431999123000889012');
      expect(s.creditorName, 'Robert Schneider AG');
      expect(s.amount, 3949.75);
      expect(s.currency, 'CHF');
      expect(s.debtorName, 'Pia-Maria Rutschmann');
      expect(s.reference, '210000000003139471430009017');
      expect(s.additionalInfo, 'Order 24');
    });
  });

  group('GS1', () {
    test('parses GTIN + expiry + lot with a GS separator', () {
      // (01) GTIN 14, (17) expiry 6, (10) lot variable.
      const raw =
          '010401234567890117260807'
          '10'
          'LOT42$gs';
      final doc = parse(raw)! as SupyGs1Barcode;
      expect(doc.gtin, '04012345678901');
      expect(
        doc.elements[SupyGs1ApplicationIdentifier.expirationDate],
        '260807',
      );
      expect(doc.elements[SupyGs1ApplicationIdentifier.batchLot], 'LOT42');
    });

    test('honors the AIM ]C1 prefix', () {
      final doc = parse(']C10104012345678901') as SupyGs1Barcode?;
      expect(doc, isNotNull);
      expect(doc!.gtin, '04012345678901');
    });
  });

  group('IATA boarding pass (BCBP)', () {
    test('parses the mandatory header and first leg', () {
      // Build the fixed-width M1 payload so field offsets are exact.
      String pad(String v, int width) => v.padRight(width).substring(0, width);
      final raw =
          StringBuffer()
            ..write('M') // format code
            ..write('1') // leg count
            ..write(pad('DESMARAIS/LUC', 20)) // passenger name
            ..write('E') // electronic ticket indicator
            ..write(pad('ABC123', 7)) // PNR
            ..write('YUL') // from
            ..write('FRA') // to
            ..write(pad('AC', 3)) // carrier
            ..write(pad('0834', 5)) // flight number
            ..write('226') // julian date
            ..write('F') // compartment
            ..write(pad('1A', 4)) // seat
            ..write(pad('0025', 5)) // sequence
            ..write('1') // passenger status
            ..write('00'); // conditional-field size
      final p = parse(raw.toString())! as SupyBoardingPassBarcode;
      expect(p.passengerName, 'DESMARAIS/LUC');
      expect(p.legCount, 1);
      expect(p.pnr, 'ABC123');
      expect(p.from, 'YUL');
      expect(p.to, 'FRA');
      expect(p.operatingCarrier, 'AC');
      expect(p.flightNumber, '0834');
      expect(p.julianFlightDate, 226);
      expect(p.seat, '1A');
    });
  });

  group('AAMVA driver license', () {
    test('parses core fields', () {
      const raw =
          '@\n\rANSI 636000090002DL00410288ZV03190008DL'
          'DCADM\n'
          'DCSDOE\n'
          'DACJOHN\n'
          'DAQD12345678\n'
          'DBB01151986\n'
          'DBA01152030\n'
          '\r';
      final dl = parse(raw)! as SupyDriverLicenseBarcode;
      expect(dl.lastName, 'DOE');
      expect(dl.firstName, 'JOHN');
      expect(dl.documentNumber, 'D12345678');
      expect(dl.dateOfBirth, '01151986');
      expect(dl.expiryDate, '01152030');
    });
  });

  group('value semantics', () {
    test('equal documents compare equal', () {
      expect(parse('tel:+1234'), equals(parse('tel:+1234')));
      expect(parse('tel:+1234').hashCode, equals(parse('tel:+1234').hashCode));
    });
  });
}
