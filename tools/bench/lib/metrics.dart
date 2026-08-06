// Output-quality metrics for the DSQ bench. Pure Dart, host-only.
import 'dart:math';
import 'dart:typed_data';

/// Sharpness: variance of the 4-neighbour Laplacian over interior pixels.
double varianceOfLaplacian(Uint8List luma, int w, int h) {
  final n = (w - 2) * (h - 2);
  if (n <= 0) return 0.0;
  var sum = 0.0;
  var sumSq = 0.0;
  for (var y = 1; y < h - 1; y++) {
    final row = y * w;
    for (var x = 1; x < w - 1; x++) {
      final i = row + x;
      final lap = 4 * luma[i] - luma[i - 1] - luma[i + 1] -
          luma[i - w] - luma[i + w];
      sum += lap;
      sumSq += lap * lap;
    }
  }
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

/// Illumination uniformity: ratio of dimmest to brightest cell mean on a
/// [grid]×[grid] partition. 1.0 = perfectly even lighting.
double illuminationUniformity(Uint8List luma, int w, int h, {int grid = 8}) {
  var minMean = double.infinity;
  var maxMean = -double.infinity;
  for (var gy = 0; gy < grid; gy++) {
    final y0 = (gy * h) ~/ grid;
    final y1 = ((gy + 1) * h) ~/ grid;
    for (var gx = 0; gx < grid; gx++) {
      final x0 = (gx * w) ~/ grid;
      final x1 = ((gx + 1) * w) ~/ grid;
      final count = (y1 - y0) * (x1 - x0);
      if (count <= 0) continue;
      var sum = 0;
      for (var y = y0; y < y1; y++) {
        final row = y * w;
        for (var x = x0; x < x1; x++) {
          sum += luma[row + x];
        }
      }
      final mean = sum / count;
      minMean = min(minMean, mean);
      maxMean = max(maxMean, mean);
    }
  }
  if (maxMean <= 0) return 1.0;
  return (minMean / maxMean).clamp(0.0, 1.0);
}

/// Effective DPI of a rectified page given its physical width.
double effectiveDpi(int outWidthPx, double physicalWidthMm) =>
    outWidthPx / (physicalWidthMm / 25.4);

String _normalize(String s) =>
    s.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

int _levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] =
          [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce(min);
    }
    prev.setAll(0, curr);
  }
  return prev[b.length];
}

/// Character error rate: Levenshtein(truth, recognized) / truth length,
/// after whitespace + case normalization.
double cer(String truth, String recognized) {
  final t = _normalize(truth);
  final r = _normalize(recognized);
  if (t.isEmpty) return r.isEmpty ? 0.0 : 1.0;
  return _levenshtein(t, r) / t.length;
}
