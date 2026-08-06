// Generates the deterministic synthetic seed scenes under bench/corpus/.
// These exist so the DSQ0 harness runs end-to-end before the real
// hand-captured corpus lands. Re-running overwrites seed-* in place.
//
// Usage: dart tools/bench/gen_seed_corpus.dart [--corpus bench/corpus]
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

const _w = 1280;
const _h = 960;
// Page occupies the centered 60% of the frame in both axes.
const _pageX0 = 256, _pageY0 = 192, _pageX1 = 1023, _pageY1 = 767;
const _quad = [0.2, 0.2, 0.8, 0.2, 0.8, 0.8, 0.2, 0.8];

// Deterministic LCG so clutter is stable across runs (no Random()).
int _lcg(int s) => (s * 1103515245 + 12345) & 0x7fffffff;

img.Image _baseFrame({required bool cluttered}) {
  final canvas = img.Image(width: _w, height: _h);
  img.fill(canvas, color: img.ColorRgb8(96, 96, 96));
  if (cluttered) {
    var s = 42;
    for (var i = 0; i < 24; i++) {
      s = _lcg(s);
      final x = s % _w;
      s = _lcg(s);
      final y = s % _h;
      s = _lcg(s);
      final wRect = 40 + s % 200;
      s = _lcg(s);
      final hRect = 40 + s % 200;
      s = _lcg(s);
      final g = 30 + s % 150;
      img.fillRect(canvas,
          x1: x, y1: y, x2: x + wRect, y2: y + hRect,
          color: img.ColorRgb8(g, (g * 3) % 200, (g * 7) % 200));
    }
  }
  img.fillRect(canvas,
      x1: _pageX0, y1: _pageY0, x2: _pageX1, y2: _pageY1,
      color: img.ColorRgb8(250, 250, 248));
  return canvas;
}

void _drawLines(img.Image canvas, List<String> lines) {
  var y = _pageY0 + 60;
  for (final line in lines) {
    img.drawString(canvas, line,
        font: img.arial48, x: _pageX0 + 48, y: y,
        color: img.ColorRgb8(20, 20, 20));
    y += 84;
  }
}

void _dim(img.Image canvas, double factor) {
  for (final p in canvas) {
    p.r = (p.r * factor).round();
    p.g = (p.g * factor).round();
    p.b = (p.b * factor).round();
  }
}

void _shadowLeftHalf(img.Image canvas) {
  // Soft horizontal gradient: 0.45x at the left edge back to 1.0x at center.
  for (var x = 0; x < _w ~/ 2; x++) {
    final f = 0.45 + 0.55 * (x / (_w / 2));
    for (var y = 0; y < _h; y++) {
      final p = canvas.getPixel(x, y);
      p.r = (p.r * f).round();
      p.g = (p.g * f).round();
      p.b = (p.b * f).round();
    }
  }
}

void _glareBlob(img.Image canvas) {
  const cx = 900, cy = 350, radius = 160;
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      final dx = x - cx, dy = y - cy;
      final d2 = dx * dx + dy * dy;
      if (d2 > radius * radius) continue;
      final boost = 1.0 - d2 / (radius * radius);
      final p = canvas.getPixel(x, y);
      p.r = (p.r + 180 * boost).clamp(0, 255).round();
      p.g = (p.g + 180 * boost).clamp(0, 255).round();
      p.b = (p.b + 180 * boost).clamp(0, 255).round();
    }
  }
}

void _writeScene({
  required String corpus,
  required String id,
  required String docType,
  required String background,
  required String lighting,
  required img.Image frame,
  required List<String> truthLines,
}) {
  final dir = Directory('$corpus/$id')..createSync(recursive: true);
  File('${dir.path}/frame.png').writeAsBytesSync(img.encodePng(frame));
  File('${dir.path}/truth.txt').writeAsStringSync('${truthLines.join('\n')}\n');
  File('${dir.path}/scene.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
    'id': id,
    'docType': docType,
    'background': background,
    'lighting': lighting,
    'quad': _quad,
    'physicalWidthMm': 152.4,
    'physicalHeightMm': 114.3,
  }));
  stdout.writeln('[gen_seed_corpus] wrote $id');
}

void main(List<String> argv) {
  var corpus = 'bench/corpus';
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] == '--corpus' && i + 1 < argv.length) corpus = argv[++i];
  }

  const receiptLines = ['RECEIPT 0042', 'MILK 3.50', 'BREAD 2.75',
      'TOTAL 6.25'];
  const invoiceLines = ['INVOICE INV-2026-118', 'SUPY TRADING LLC',
      'AMOUNT DUE 137.50', 'DUE 2026-08-01'];
  const menuLines = ['MENU', 'FALAFEL WRAP 18', 'LENTIL SOUP 14',
      'MINT LEMONADE 12'];

  var f = _baseFrame(cluttered: false);
  _drawLines(f, receiptLines);
  _writeScene(corpus: corpus, id: 'seed-001', docType: 'receipt',
      background: 'plain', lighting: 'good', frame: f,
      truthLines: receiptLines);

  f = _baseFrame(cluttered: false);
  _drawLines(f, receiptLines);
  _dim(f, 0.35);
  _writeScene(corpus: corpus, id: 'seed-002', docType: 'receipt',
      background: 'plain', lighting: 'dim', frame: f,
      truthLines: receiptLines);

  f = _baseFrame(cluttered: false);
  _drawLines(f, receiptLines);
  _shadowLeftHalf(f);
  _writeScene(corpus: corpus, id: 'seed-003', docType: 'receipt',
      background: 'plain', lighting: 'shadow', frame: f,
      truthLines: receiptLines);

  f = _baseFrame(cluttered: true);
  _drawLines(f, invoiceLines);
  _writeScene(corpus: corpus, id: 'seed-004', docType: 'invoice',
      background: 'cluttered', lighting: 'good', frame: f,
      truthLines: invoiceLines);

  f = _baseFrame(cluttered: false);
  _drawLines(f, invoiceLines);
  _writeScene(corpus: corpus, id: 'seed-005', docType: 'invoice',
      background: 'plain', lighting: 'good', frame: f,
      truthLines: invoiceLines);

  f = _baseFrame(cluttered: false);
  _drawLines(f, menuLines);
  _glareBlob(f);
  _writeScene(corpus: corpus, id: 'seed-006', docType: 'menu',
      background: 'plain', lighting: 'glare', frame: f,
      truthLines: menuLines);
}
