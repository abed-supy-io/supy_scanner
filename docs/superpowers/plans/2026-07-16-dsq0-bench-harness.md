# DSQ0 — Bench Harness + Labeled Corpus + Scanbot Baseline: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the DSQ scoreboard — a labeled corpus format, a host bench harness (detection + output quality), a macOS Vision OCR lane, and a CI job — so every later DSQ phase (1–4) can prove "beats Scanbot" with numbers instead of eyeballs.

**Architecture:** A pure-Dart CLI (`tools/bench/`, mirroring the existing `tools/perfgate/` pattern) drives two thin C++ host harnesses built from `native/` with `-DSUPY_BUILD_TOOLS=ON`: `bench_detect` (runs the classical detector `supy::scanner::document::detectDocument` on raw luma files) and `bench_pipeline` (replays decode → `supy_core_warp` → `supy_core_enhance` on raw RGBA files). Dart decodes corpus PNGs (`package:image`), writes raw pixel temp files, parses one-line `DSQ_*` JSON output from the harnesses, computes IoU / sharpness / uniformity / DPI / CER in Dart, and emits `bench_report.md` + `bench_report.json` with deltas vs. pinned baselines (Scanbot's numbers, our previous phase).

**Tech Stack:** Dart ≥3.4 (`package:image`, `package:test`), C++17 (existing `native/` CMake tree, no new third-party deps), Swift/`Vision.framework` (one 30-line macOS OCR CLI), Git LFS for corpus binaries, GitHub Actions (macos-14).

## Global Constraints

- **Pixel buffers MUST NOT cross dart:ffi** (`native/include/supy_scanner_core.h` header contract). The bench keeps pixels in files + native processes: Dart writes raw files, C++ binaries read them. No dart:ffi bindings anywhere in this plan.
- **No paid SDK dependency. No cloud OCR or any network call in the scanning path** (CLAUDE.md). OCR here is on-device macOS Vision, host-tool only.
- **No OpenCV; no new vendored C/C++ libraries.** Harnesses read raw pixel files precisely so the C++ side needs no image decoder.
- **No public Dart API change, no MethodChannel change** in DSQ0 — it is pure infrastructure. Channel stays `io.supy.scanner/v1`, untouched.
- **"Beats Scanbot" gate definition (from the spec, applied by later phases):** win the phase's gate metric on the relevant subset, no regression >±2% on any other metric, size budgets ≤22 MB/ABI Android, ≤25 MB iOS. DSQ0 implements the ±2% comparator; it does not enforce it until baselines are pinned.
- **Host tools default OFF:** all new CMake targets live under the existing `if(SUPY_BUILD_TOOLS)` block (`native/CMakeLists.txt:181`) with `-O3 -Wall -Wextra -Wpedantic -Werror`.
- **Conventional commits** (`feat(bench): ...`, `chore(ci): ...`, `docs: ...`).
- **Corpus capture is user-owned manual work** (~120 real scenes + Scanbot outputs via the retailer app, ~half a day). This plan ships the schema, validator, seed synthetic scenes, and a capture guide — not the real corpus.
- **Quad convention everywhere:** normalized [0,1] coordinates, TL,TR,BR,BL order, interleaved `[x0,y0,x1,y1,x2,y2,x3,y3]`, y-down. Matches `supy::scanner::document::DetectedQuad` and `supy_warp_input_t.src_corners` (which takes the same order in pixel space).

## File Structure

```
bench/corpus/                      # Git LFS; one dir per scene
  README.md                        # schema (Task 1)
  CAPTURE_GUIDE.md                 # user-facing capture instructions (Task 11)
  seed-001/ … seed-006/            # synthetic seed scenes (Task 4)
    frame.png  scene.json  truth.txt
tools/bench/
  pubspec.yaml                     # package supy_bench (Task 1)
  lib/corpus.dart                  # Scene model + loader + validator (Task 1)
  lib/quad_iou.dart                # convex polygon IoU (Task 2)
  lib/metrics.dart                 # sharpness / uniformity / DPI / CER (Task 3)
  lib/report.dart                  # aggregate + markdown + gate (Task 8)
  validate_corpus.dart             # CLI (Task 1)
  gen_seed_corpus.dart             # deterministic seed generator (Task 4)
  run_bench.dart                   # main driver (Task 9)
  ocr/vision_ocr.swift             # macOS Vision OCR CLI (Task 7)
  baselines/                       # pinned BenchSummary JSONs (Task 8)
  test/*.dart                      # unit tests
native/bench/
  bench_detect.cpp                 # detection harness (Task 5)
  bench_pipeline.cpp               # warp+enhance replay harness (Task 6)
.github/workflows/ci.yml           # + dsq-bench job (Task 10)
```

---

### Task 1: Corpus schema, LFS rules, and Dart corpus loader/validator

**Files:**
- Create: `bench/corpus/README.md`
- Create: `tools/bench/pubspec.yaml`
- Create: `tools/bench/lib/corpus.dart`
- Create: `tools/bench/validate_corpus.dart`
- Modify: `.gitattributes` (create if absent)
- Modify: `.gitignore`
- Test: `tools/bench/test/corpus_test.dart`

**Interfaces:**
- Produces: `class Scene { String id; Directory dir; String docType; String background; String lighting; List<double>? quad; double? physicalWidthMm; double? physicalHeightMm; File get frameFile; File get truthFile; File get scanbotFile; String get category; }`
- Produces: `List<Scene> loadCorpus(Directory root)` (sorted by id, only dirs containing `scene.json`)
- Produces: `List<String> validateScene(Scene s)` and `List<String> validateCorpus(List<Scene> scenes)` — empty list = valid
- Produces: constant sets `kDocTypes = {receipt, invoice, menu, synthetic}`, `kBackgrounds = {plain, cluttered}`, `kLightings = {good, dim, shadow, glare}`

- [ ] **Step 1: Scaffold the package**

Create `tools/bench/pubspec.yaml`:

```yaml
name: supy_bench
description: >-
  DSQ document-quality bench harness (host CLI). Design:
  docs/superpowers/specs/2026-07-16-doc-scan-quality-design.md.
publish_to: none

environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  image: ^4.2.0

dev_dependencies:
  test: ^1.25.0
```

Append to `.gitattributes` (create the file at repo root if it does not exist):

```
# DSQ bench corpus — binary scene assets go through Git LFS.
bench/corpus/**/*.png filter=lfs diff=lfs merge=lfs -text
bench/corpus/**/*.jpg filter=lfs diff=lfs merge=lfs -text
```

Append to `.gitignore`:

```
# DSQ bench outputs (regenerated by tools/bench/run_bench.dart)
tools/bench/report/
build/dsq-bench/
```

Run: `git lfs version || brew install git-lfs && git lfs install` (once per machine; CI uses `checkout` with `lfs: true`).

Run: `cd tools/bench && dart pub get`
Expected: resolves `image` and `test`.

- [ ] **Step 2: Write the failing test**

Create `tools/bench/test/corpus_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../lib/corpus.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('corpus_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory writeScene(String id, Map<String, Object?> json,
      {bool withFrame = true}) {
    final dir = Directory('${tmp.path}/$id')..createSync(recursive: true);
    File('${dir.path}/scene.json').writeAsStringSync(jsonEncode(json));
    if (withFrame) {
      // Content irrelevant for the loader; existence is what's validated.
      File('${dir.path}/frame.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    }
    return dir;
  }

  Map<String, Object?> goodJson(String id) => {
        'id': id,
        'docType': 'receipt',
        'background': 'plain',
        'lighting': 'good',
        'quad': [0.2, 0.2, 0.8, 0.2, 0.8, 0.8, 0.2, 0.8],
        'physicalWidthMm': 80.0,
        'physicalHeightMm': 60.0,
      };

  test('loadCorpus loads scenes sorted by id', () {
    writeScene('b-002', goodJson('b-002'));
    writeScene('a-001', goodJson('a-001'));
    final scenes = loadCorpus(tmp);
    expect(scenes.map((s) => s.id).toList(), ['a-001', 'b-002']);
    expect(scenes.first.quad, hasLength(8));
    expect(scenes.first.category, 'receipt/plain/good');
    expect(scenes.first.physicalWidthMm, 80.0);
  });

  test('a valid scene has no validation errors', () {
    writeScene('a-001', goodJson('a-001'));
    final errors = validateCorpus(loadCorpus(tmp));
    expect(errors, isEmpty);
  });

  test('quad may be null (negative scene: no document in frame)', () {
    final j = goodJson('a-001')..['quad'] = null;
    writeScene('a-001', j);
    expect(validateCorpus(loadCorpus(tmp)), isEmpty);
  });

  test('rejects id/dir mismatch, bad category, bad quad, missing frame', () {
    writeScene('a-001', goodJson('WRONG'));
    writeScene('a-002', goodJson('a-002')..['docType'] = 'poster');
    writeScene('a-003', goodJson('a-003')..['quad'] = [0.2, 0.2, 1.5, 0.2]);
    writeScene('a-004', goodJson('a-004'), withFrame: false);
    final j5 = goodJson('a-005')..remove('physicalHeightMm');
    writeScene('a-005', j5);

    final errors = validateCorpus(loadCorpus(tmp));
    expect(errors, hasLength(5));
    expect(errors.join('\n'), contains('a-001'));
    expect(errors.join('\n'), contains('docType'));
    expect(errors.join('\n'), contains('quad'));
    expect(errors.join('\n'), contains('frame.png'));
    expect(errors.join('\n'), contains('physical'));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd tools/bench && dart test test/corpus_test.dart`
Expected: FAIL — `../lib/corpus.dart` does not exist.

- [ ] **Step 4: Implement the loader/validator**

Create `tools/bench/lib/corpus.dart`:

```dart
// Corpus model for the DSQ bench. Schema doc: bench/corpus/README.md.
import 'dart:convert';
import 'dart:io';

const kDocTypes = {'receipt', 'invoice', 'menu', 'synthetic'};
const kBackgrounds = {'plain', 'cluttered'};
const kLightings = {'good', 'dim', 'shadow', 'glare'};

class Scene {
  Scene({
    required this.id,
    required this.dir,
    required this.docType,
    required this.background,
    required this.lighting,
    required this.quad,
    this.physicalWidthMm,
    this.physicalHeightMm,
  });

  final String id;
  final Directory dir;
  final String docType;
  final String background;
  final String lighting;

  /// Normalized [x0,y0,..,x3,y3], TL,TR,BR,BL, y-down. Null means the frame
  /// intentionally contains no document (negative scene).
  final List<double>? quad;

  final double? physicalWidthMm;
  final double? physicalHeightMm;

  File get frameFile => File('${dir.path}/frame.png');
  File get truthFile => File('${dir.path}/truth.txt');
  File get scanbotFile => File('${dir.path}/scanbot.png');

  String get category => '$docType/$background/$lighting';

  static Scene fromJson(Directory dir, Map<String, Object?> json) {
    final quadRaw = json['quad'];
    return Scene(
      id: (json['id'] ?? '') as String,
      dir: dir,
      docType: (json['docType'] ?? '') as String,
      background: (json['background'] ?? '') as String,
      lighting: (json['lighting'] ?? '') as String,
      quad: quadRaw == null
          ? null
          : (quadRaw as List).map((v) => (v as num).toDouble()).toList(),
      physicalWidthMm: (json['physicalWidthMm'] as num?)?.toDouble(),
      physicalHeightMm: (json['physicalHeightMm'] as num?)?.toDouble(),
    );
  }
}

List<Scene> loadCorpus(Directory root) {
  final scenes = <Scene>[];
  final dirs = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final dir in dirs) {
    final jsonFile = File('${dir.path}/scene.json');
    if (!jsonFile.existsSync()) continue;
    final json = jsonDecode(jsonFile.readAsStringSync()) as Map<String, Object?>;
    scenes.add(Scene.fromJson(dir, json));
  }
  return scenes;
}

List<String> validateScene(Scene s) {
  final errors = <String>[];
  final dirName = s.dir.uri.pathSegments.where((p) => p.isNotEmpty).last;
  void err(String msg) => errors.add('[$dirName] $msg');

  if (s.id != dirName) err('id "${s.id}" does not match directory name');
  if (!kDocTypes.contains(s.docType)) err('docType "${s.docType}" invalid');
  if (!kBackgrounds.contains(s.background)) {
    err('background "${s.background}" invalid');
  }
  if (!kLightings.contains(s.lighting)) err('lighting "${s.lighting}" invalid');

  final quad = s.quad;
  if (quad != null) {
    if (quad.length != 8) {
      err('quad must have 8 values, has ${quad.length}');
    } else if (quad.any((v) => v < 0.0 || v > 1.0)) {
      err('quad values must be normalized to [0,1]');
    }
  }

  if (!s.frameFile.existsSync()) err('frame.png missing');

  final hasW = s.physicalWidthMm != null;
  final hasH = s.physicalHeightMm != null;
  if (hasW != hasH ||
      (hasW && (s.physicalWidthMm! <= 0 || s.physicalHeightMm! <= 0))) {
    err('physicalWidthMm/physicalHeightMm must both be present and > 0, '
        'or both absent');
  }
  return errors;
}

List<String> validateCorpus(List<Scene> scenes) =>
    [for (final s in scenes) ...validateScene(s)];
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd tools/bench && dart test test/corpus_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Write the validator CLI and schema doc**

Create `tools/bench/validate_corpus.dart`:

```dart
// Validates bench/corpus against the schema in bench/corpus/README.md.
//
// Usage: dart tools/bench/validate_corpus.dart [--corpus <dir>]
// Exit codes: 0 valid, 1 validation errors, 2 corpus dir missing/empty.
import 'dart:io';

import 'lib/corpus.dart';

void main(List<String> argv) {
  var corpusPath = 'bench/corpus';
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] == '--corpus' && i + 1 < argv.length) corpusPath = argv[++i];
  }
  final root = Directory(corpusPath);
  if (!root.existsSync()) {
    stderr.writeln('[validate_corpus] no corpus at $corpusPath');
    exit(2);
  }
  final scenes = loadCorpus(root);
  if (scenes.isEmpty) {
    stderr.writeln('[validate_corpus] no scenes found in $corpusPath');
    exit(2);
  }
  final errors = validateCorpus(scenes);
  for (final e in errors) {
    stderr.writeln('[validate_corpus] $e');
  }
  final byLighting = <String, int>{};
  for (final s in scenes) {
    byLighting[s.lighting] = (byLighting[s.lighting] ?? 0) + 1;
  }
  stdout.writeln('[validate_corpus] ${scenes.length} scenes, '
      'by lighting: $byLighting, errors: ${errors.length}');
  exit(errors.isEmpty ? 0 : 1);
}
```

Create `bench/corpus/README.md`:

```markdown
# DSQ bench corpus

One directory per scene. Binary assets (`*.png`, `*.jpg`) are stored in
**Git LFS** (see `.gitattributes`). Validate with
`dart tools/bench/validate_corpus.dart`.

## Scene layout

```
bench/corpus/<scene-id>/
  frame.png     # REQUIRED. Raw camera still, full sensor frame, no crop.
  scene.json    # REQUIRED. Labels + category (schema below).
  truth.txt     # OPTIONAL. Ground-truth text for the OCR CER lane.
  scanbot.png   # OPTIONAL. Scanbot SDK output for the same physical scene,
                # captured once via the retailer app (see CAPTURE_GUIDE.md).
```

## scene.json schema

```jsonc
{
  "id": "receipt-thermal-014",        // must equal the directory name
  "docType": "receipt",               // receipt | invoice | menu | synthetic
  "background": "cluttered",          // plain | cluttered
  "lighting": "shadow",               // good | dim | shadow | glare
  // Hand-labeled document quad in frame.png. Normalized [0,1], y-down,
  // TL,TR,BR,BL order, interleaved x,y. null = no document in frame
  // (negative scene: detector must NOT fire).
  "quad": [0.21, 0.18, 0.79, 0.20, 0.81, 0.83, 0.19, 0.80],
  // Physical document size, used for the effective-DPI metric. Both present
  // or both absent.
  "physicalWidthMm": 80.0,
  "physicalHeightMm": 210.0
}
```

Target composition (~120 scenes): thermal/crumpled receipts, A4 invoices,
glossy menus × {plain, cluttered} × {good, dim, shadow, glare}, plus a
handful of negative scenes (`"quad": null`).

`seed-*` scenes are synthetic (generated by
`dart tools/bench/gen_seed_corpus.dart`) and exist so the harness runs
end-to-end before the real corpus lands. Do not hand-edit them.
```

Run: `dart tools/bench/validate_corpus.dart`
Expected: exit 2 with `no corpus at bench/corpus` (or `no scenes`) — correct until Task 4 generates the seed scenes.

- [ ] **Step 7: Commit**

```bash
git add tools/bench/pubspec.yaml tools/bench/lib/corpus.dart \
  tools/bench/validate_corpus.dart tools/bench/test/corpus_test.dart \
  bench/corpus/README.md .gitattributes .gitignore tools/bench/pubspec.lock
git commit -m "feat(bench): DSQ0 corpus schema, loader and validator CLI"
```

---

### Task 2: Quad IoU geometry

**Files:**
- Create: `tools/bench/lib/quad_iou.dart`
- Test: `tools/bench/test/quad_iou_test.dart`

**Interfaces:**
- Consumes: nothing (pure geometry).
- Produces: `double quadIou(List<double> a, List<double> b)` — both quads as normalized 8-value interleaved lists; returns intersection-over-union in [0,1].
- Produces: `double polygonArea(List<Point<double>> poly)` (absolute area) and `List<Point<double>> clipPolygon(List<Point<double>> subject, List<Point<double>> clip)` (Sutherland–Hodgman, convex clip), both used by tests and reusable later.

- [ ] **Step 1: Write the failing test**

Create `tools/bench/test/quad_iou_test.dart`:

```dart
import 'dart:math';

import 'package:test/test.dart';

import '../lib/quad_iou.dart';

// Unit square as a TL,TR,BR,BL interleaved quad (y-down convention).
const unit = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];

void main() {
  test('polygonArea of unit square is 1', () {
    final poly = [
      const Point(0.0, 0.0),
      const Point(1.0, 0.0),
      const Point(1.0, 1.0),
      const Point(0.0, 1.0),
    ];
    expect(polygonArea(poly), closeTo(1.0, 1e-9));
    // Winding must not matter.
    expect(polygonArea(poly.reversed.toList()), closeTo(1.0, 1e-9));
  });

  test('identical quads → IoU 1', () {
    expect(quadIou(unit, unit), closeTo(1.0, 1e-9));
  });

  test('disjoint quads → IoU 0', () {
    const other = [2.0, 2.0, 3.0, 2.0, 3.0, 3.0, 2.0, 3.0];
    expect(quadIou(unit, other), closeTo(0.0, 1e-9));
  });

  test('half-overlap → IoU 1/3', () {
    // Unit square shifted right by 0.5: intersection 0.5, union 1.5.
    const shifted = [0.5, 0.0, 1.5, 0.0, 1.5, 1.0, 0.5, 1.0];
    expect(quadIou(unit, shifted), closeTo(1.0 / 3.0, 1e-9));
  });

  test('contained quad → IoU = area ratio', () {
    // Centered half-size square: intersection 0.25, union 1.0.
    const inner = [0.25, 0.25, 0.75, 0.25, 0.75, 0.75, 0.25, 0.75];
    expect(quadIou(unit, inner), closeTo(0.25, 1e-9));
    expect(quadIou(inner, unit), closeTo(0.25, 1e-9));
  });

  test('degenerate quad → IoU 0, no crash', () {
    const degenerate = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];
    expect(quadIou(unit, degenerate), 0.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/bench && dart test test/quad_iou_test.dart`
Expected: FAIL — `../lib/quad_iou.dart` does not exist.

- [ ] **Step 3: Implement**

Create `tools/bench/lib/quad_iou.dart`:

```dart
// Convex-quad IoU for the detection bench. Sutherland–Hodgman clipping +
// shoelace area — winding-agnostic, no deps.
import 'dart:math';

double _signedArea(List<Point<double>> poly) {
  var sum = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final p = poly[i];
    final q = poly[(i + 1) % poly.length];
    sum += p.x * q.y - q.x * p.y;
  }
  return sum / 2.0;
}

/// Absolute polygon area (shoelace).
double polygonArea(List<Point<double>> poly) {
  if (poly.length < 3) return 0.0;
  return _signedArea(poly).abs();
}

/// Clips [subject] against convex [clip] (Sutherland–Hodgman). Works for
/// either winding of either polygon.
List<Point<double>> clipPolygon(
    List<Point<double>> subject, List<Point<double>> clip) {
  if (clip.length < 3 || subject.length < 3) return const [];
  final sign = _signedArea(clip) >= 0 ? 1.0 : -1.0;
  var output = List.of(subject);
  for (var i = 0; i < clip.length && output.isNotEmpty; i++) {
    final a = clip[i];
    final b = clip[(i + 1) % clip.length];
    bool inside(Point<double> p) =>
        sign * ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) >= 0;
    Point<double> intersect(Point<double> p, Point<double> q) {
      final a1 = b.y - a.y, b1 = a.x - b.x;
      final c1 = a1 * a.x + b1 * a.y;
      final a2 = q.y - p.y, b2 = p.x - q.x;
      final c2 = a2 * p.x + b2 * p.y;
      final det = a1 * b2 - a2 * b1;
      return Point((b2 * c1 - b1 * c2) / det, (a1 * c2 - a2 * c1) / det);
    }

    final input = output;
    output = <Point<double>>[];
    for (var j = 0; j < input.length; j++) {
      final p = input[j];
      final q = input[(j + 1) % input.length];
      final pIn = inside(p);
      final qIn = inside(q);
      if (pIn) {
        output.add(p);
        if (!qIn) output.add(intersect(p, q));
      } else if (qIn) {
        output.add(intersect(p, q));
      }
    }
  }
  return output;
}

List<Point<double>> _toPoints(List<double> quad) => [
      for (var i = 0; i < quad.length; i += 2) Point(quad[i], quad[i + 1]),
    ];

/// IoU of two convex quads given as interleaved [x0,y0,..,x3,y3] lists.
double quadIou(List<double> a, List<double> b) {
  final pa = _toPoints(a);
  final pb = _toPoints(b);
  final areaA = polygonArea(pa);
  final areaB = polygonArea(pb);
  if (areaA <= 0 || areaB <= 0) return 0.0;
  final inter = polygonArea(clipPolygon(pa, pb));
  final union = areaA + areaB - inter;
  if (union <= 0) return 0.0;
  return (inter / union).clamp(0.0, 1.0);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/bench && dart test test/quad_iou_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/bench/lib/quad_iou.dart tools/bench/test/quad_iou_test.dart
git commit -m "feat(bench): convex quad IoU for the detection bench"
```

---

### Task 3: Output-quality metrics (sharpness, uniformity, DPI, CER)

**Files:**
- Create: `tools/bench/lib/metrics.dart`
- Test: `tools/bench/test/metrics_test.dart`

**Interfaces:**
- Consumes: nothing (pure functions over `Uint8List` luma planes / strings).
- Produces:
  - `double varianceOfLaplacian(Uint8List luma, int w, int h)` — sharpness, higher = sharper. Same 4-neighbour Laplacian family the native scorer uses (`supy_core_enhance_quality_score`), so numbers are comparable in spirit, not bit-identical.
  - `double illuminationUniformity(Uint8List luma, int w, int h, {int grid = 8})` — min/max of per-cell mean luma; 1.0 = perfectly even.
  - `double effectiveDpi(int outWidthPx, double physicalWidthMm)`.
  - `double cer(String truth, String recognized)` — character error rate on whitespace-normalized uppercase text; 0 = perfect, can exceed 1 on garbage insertions.

- [ ] **Step 1: Write the failing test**

Create `tools/bench/test/metrics_test.dart`:

```dart
import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/metrics.dart';

void main() {
  test('flat image has zero variance-of-Laplacian', () {
    final flat = Uint8List.fromList(List.filled(64 * 64, 128));
    expect(varianceOfLaplacian(flat, 64, 64), 0.0);
  });

  test('checkerboard is sharper than a smooth gradient', () {
    final checker = Uint8List(64 * 64);
    final gradient = Uint8List(64 * 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        checker[y * 64 + x] = ((x + y) % 2 == 0) ? 255 : 0;
        gradient[y * 64 + x] = (x * 4).clamp(0, 255);
      }
    }
    expect(varianceOfLaplacian(checker, 64, 64),
        greaterThan(varianceOfLaplacian(gradient, 64, 64)));
  });

  test('uniform image scores uniformity 1.0; half-dark image scores low', () {
    final flat = Uint8List.fromList(List.filled(64 * 64, 200));
    expect(illuminationUniformity(flat, 64, 64), closeTo(1.0, 1e-9));

    final halfDark = Uint8List(64 * 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        halfDark[y * 64 + x] = x < 32 ? 200 : 50;
      }
    }
    expect(illuminationUniformity(halfDark, 64, 64), closeTo(0.25, 0.02));
  });

  test('effectiveDpi: A4 width at 2480 px is ~300 DPI', () {
    expect(effectiveDpi(2480, 210.0), closeTo(300.0, 1.0));
  });

  test('cer: exact match 0, one sub in 4 chars = 0.25, case/space ignored',
      () {
    expect(cer('ABCD', 'ABCD'), 0.0);
    expect(cer('ABCD', 'ABXD'), 0.25);
    expect(cer('Total  42.00', 'total 42.00'), 0.0);
    expect(cer('', ''), 0.0);
    expect(cer('', 'X'), 1.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/bench && dart test test/metrics_test.dart`
Expected: FAIL — `../lib/metrics.dart` does not exist.

- [ ] **Step 3: Implement**

Create `tools/bench/lib/metrics.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/bench && dart test test/metrics_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/bench/lib/metrics.dart tools/bench/test/metrics_test.dart
git commit -m "feat(bench): sharpness, uniformity, DPI and CER metrics"
```

---

### Task 4: Deterministic seed corpus generator

**Files:**
- Create: `tools/bench/gen_seed_corpus.dart`
- Create (generated, committed): `bench/corpus/seed-001/` … `bench/corpus/seed-006/` (each: `frame.png`, `scene.json`, `truth.txt`)

**Interfaces:**
- Consumes: `validateCorpus`/`loadCorpus` from Task 1 (for the verification step).
- Produces: six synthetic scenes that exercise every harness lane — page quad labels, truth text, dim/shadow/glare lighting variants, one cluttered background. `seed-*` frames are 1280×960 PNGs with the page occupying the normalized quad [0.2,0.2, 0.8,0.2, 0.8,0.8, 0.2,0.8].

- [ ] **Step 1: Write the generator**

Create `tools/bench/gen_seed_corpus.dart`:

```dart
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
```

- [ ] **Step 2: Generate and validate**

Run:
```bash
dart tools/bench/gen_seed_corpus.dart
dart tools/bench/validate_corpus.dart
```
Expected: six `wrote seed-00N` lines, then `[validate_corpus] 6 scenes, by lighting: {dim: 1, glare: 1, good: 3, shadow: 1}, errors: 0`, exit 0.

- [ ] **Step 3: Verify determinism**

Run:
```bash
shasum bench/corpus/seed-001/frame.png > /tmp/seed1.sha
dart tools/bench/gen_seed_corpus.dart
shasum -c /tmp/seed1.sha
```
Expected: `OK` — regeneration is byte-identical.

- [ ] **Step 4: Verify LFS picked the PNGs up, then commit**

Run: `git add bench/corpus tools/bench/gen_seed_corpus.dart && git lfs status`
Expected: the six `frame.png` files listed as LFS objects to be committed (if not, `git lfs install` was skipped — fix before committing).

```bash
git commit -m "feat(bench): deterministic synthetic seed corpus (6 scenes)"
```

---

### Task 5: `bench_detect` C++ host harness

**Files:**
- Create: `native/bench/bench_detect.cpp`
- Modify: `native/CMakeLists.txt` (the `if(SUPY_BUILD_TOOLS)` block, currently lines 181–186)

**Interfaces:**
- Consumes: `supy::scanner::document::detectDocument(const DetectionInput&)` from `native/document/document_edge_detector.h` (input: luma ptr, width, height, rowStride; output: `optional<DetectedQuad>` with normalized TL,TR,BR,BL corners, coverageRatio, tiltDegrees).
- Produces (consumed by Task 9's driver): CLI `bench_detect --gray <path> --width W --height H`, reading a headerless 8-bit luma file of exactly `W*H` bytes (stride == width), printing exactly one line to stdout:
  - hit: `DSQ_DETECT {"detected":true,"quad":[x0,y0,x1,y1,x2,y2,x3,y3],"coverage":C,"tilt":T}` (quad normalized, 6 decimals)
  - miss: `DSQ_DETECT {"detected":false}`
  - exit 0 in both cases; exit 2 on bad args / unreadable file / size mismatch.

- [ ] **Step 1: Write the harness**

Create `native/bench/bench_detect.cpp`:

```cpp
// Host-side DSQ0 detection bench harness. Reads a headerless 8-bit luma
// file, runs the classical document detector, prints one DSQ_DETECT JSON
// line for tools/bench/run_bench.dart to parse.
//
// Usage: bench_detect --gray <path> --width W --height H
//
// The file must contain exactly width*height bytes (row stride == width);
// tools/bench/run_bench.dart writes these from decoded corpus PNGs. Raw
// files keep pixel decoding out of C++ (no new vendored deps) and pixels
// out of dart:ffi (per the supy_scanner_core.h boundary contract).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "document/document_edge_detector.h"

namespace {

struct Args {
  std::string gray;
  int width = 0;
  int height = 0;
};

Args parseArgs(int argc, char** argv) {
  Args a;
  for (int i = 1; i < argc; ++i) {
    const std::string k = argv[i];
    auto next = [&]() -> const char* {
      if (i + 1 >= argc) {
        std::fprintf(stderr, "bench_detect: missing value for %s\n", k.c_str());
        std::exit(2);
      }
      return argv[++i];
    };
    if (k == "--gray") a.gray = next();
    else if (k == "--width") a.width = std::atoi(next());
    else if (k == "--height") a.height = std::atoi(next());
    else {
      std::fprintf(stderr, "bench_detect: unknown arg %s\n", k.c_str());
      std::exit(2);
    }
  }
  return a;
}

std::vector<uint8_t> readAll(const std::string& path) {
  std::FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    std::fprintf(stderr, "bench_detect: cannot open %s\n", path.c_str());
    std::exit(2);
  }
  std::fseek(f, 0, SEEK_END);
  const long size = std::ftell(f);
  std::fseek(f, 0, SEEK_SET);
  std::vector<uint8_t> buf(size > 0 ? static_cast<size_t>(size) : 0);
  if (!buf.empty() && std::fread(buf.data(), 1, buf.size(), f) != buf.size()) {
    std::fclose(f);
    std::fprintf(stderr, "bench_detect: short read on %s\n", path.c_str());
    std::exit(2);
  }
  std::fclose(f);
  return buf;
}

}  // namespace

int main(int argc, char** argv) {
  const Args a = parseArgs(argc, argv);
  if (a.gray.empty() || a.width <= 0 || a.height <= 0) {
    std::fprintf(stderr,
                 "usage: bench_detect --gray <path> --width W --height H\n");
    return 2;
  }
  const std::vector<uint8_t> luma = readAll(a.gray);
  const size_t expected =
      static_cast<size_t>(a.width) * static_cast<size_t>(a.height);
  if (luma.size() != expected) {
    std::fprintf(stderr, "bench_detect: %s is %zu bytes, expected %zu\n",
                 a.gray.c_str(), luma.size(), expected);
    return 2;
  }

  const supy::scanner::document::DetectionInput input{
      luma.data(), a.width, a.height, a.width};
  const auto quad = supy::scanner::document::detectDocument(input);
  if (!quad.has_value()) {
    std::printf("DSQ_DETECT {\"detected\":false}\n");
    return 0;
  }
  const auto& c = quad->corners;
  std::printf(
      "DSQ_DETECT {\"detected\":true,\"quad\":[%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,"
      "%.6f,%.6f],\"coverage\":%.4f,\"tilt\":%.2f}\n",
      c[0].x, c[0].y, c[1].x, c[1].y, c[2].x, c[2].y, c[3].x, c[3].y,
      quad->coverageRatio, quad->tiltDegrees);
  return 0;
}
```

- [ ] **Step 2: Add the CMake target**

In `native/CMakeLists.txt`, inside the existing `if(SUPY_BUILD_TOOLS)` block (after the `bench_enhance` target), add:

```cmake
  add_executable(bench_detect bench/bench_detect.cpp)
  target_link_libraries(bench_detect PRIVATE supy_scanner_core)
  target_include_directories(bench_detect PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  target_compile_options(bench_detect PRIVATE -O3 -Wall -Wextra -Wpedantic -Werror)
```

- [ ] **Step 3: Build**

Run:
```bash
cmake -S native -B build/dsq-bench -DSUPY_BUILD_TOOLS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build/dsq-bench --target bench_detect --config Release
```
Expected: builds clean under `-Werror`.

- [ ] **Step 4: Run against a seed frame**

Create a throwaway luma dump from seed-001 (this logic moves into the driver in Task 9):

```bash
cat > /tmp/dsq_dump_luma.dart <<'EOF'
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final frame = img.decodePng(File(args[0]).readAsBytesSync())!;
  final luma = Uint8List(frame.width * frame.height);
  var i = 0;
  for (final p in frame) {
    luma[i++] = img.getLuminance(p).round().clamp(0, 255);
  }
  File(args[1]).writeAsBytesSync(luma);
  print('${frame.width} ${frame.height}');
}
EOF
(cd tools/bench && dart /tmp/dsq_dump_luma.dart \
  ../../bench/corpus/seed-001/frame.png /tmp/seed-001.gray)
./build/dsq-bench/bench_detect --gray /tmp/seed-001.gray --width 1280 --height 960
```
Expected: one `DSQ_DETECT {"detected":true,"quad":[...]}` line with quad values near [0.2,0.2, 0.8,0.2, 0.8,0.8, 0.2,0.8] (high-contrast synthetic page; the classical detector must find it). If it prints `"detected":false`, stop and investigate — the harness wiring, not the detector, is the suspect (byte order, dimensions).

- [ ] **Step 5: Commit**

```bash
git add native/bench/bench_detect.cpp native/CMakeLists.txt
git commit -m "feat(bench): bench_detect host harness for the detection bench"
```

---

### Task 6: `bench_pipeline` C++ host harness (warp → enhance replay)

**Files:**
- Create: `native/bench/bench_pipeline.cpp`
- Modify: `native/CMakeLists.txt` (same `if(SUPY_BUILD_TOOLS)` block)

**Interfaces:**
- Consumes: `supy_core_warp` / `supy_core_warp_rgba/_width/_height/_row_stride/_free` (`native/include/supy_scanner_core.h:259-272`); `supy_core_enhance` family + `supy_enhance_mode_t` (`native/include/supy_scanner_enhance.h`).
- Produces (consumed by Task 9): CLI
  `bench_pipeline --rgba <path> --width W --height H --quad x0,y0,...,x3,y3 --mode <off|fast|balanced|max> --out <path>`
  reading headerless RGBA8888 of `W*H*4` bytes, quad normalized TL,TR,BR,BL. Writes packed RGBA (`outWidth*outHeight*4` bytes) to `--out` and prints one line:
  `DSQ_PIPELINE {"outWidth":..,"outHeight":..,"enhanced":true|false,"appliedStages":..,"qualityScore":..,"verdict":..,"processingMs":..}`
  Enhance failure (NULL handle) falls back to writing the un-enhanced warp output with `"enhanced":false` — mirroring the DSQ1 production error policy. Exit 0 on success, 2 on bad args/IO, 3 on warp failure.

- [ ] **Step 1: Write the harness**

Create `native/bench/bench_pipeline.cpp`:

```cpp
// Host-side DSQ0 "pipeline replay" harness: raw RGBA still + labeled quad →
// supy_core_warp → supy_core_enhance → raw RGBA out. Replays the device
// capture pipeline on corpus stills so the output bench runs in CI without
// a device. One DSQ_PIPELINE JSON line on stdout for run_bench.dart.
//
// Usage:
//   bench_pipeline --rgba <path> --width W --height H \
//     --quad x0,y0,x1,y1,x2,y2,x3,y3 --mode balanced --out <path>
//
// Quad is normalized [0,1] TL,TR,BR,BL; scaled to pixels here (the same
// contract supy_warp_input_t documents for production callers).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "supy_scanner_core.h"
#include "supy_scanner_enhance.h"

namespace {

struct Args {
  std::string rgba;
  std::string out;
  std::string mode = "balanced";
  int width = 0;
  int height = 0;
  float quad[8] = {0};
  bool haveQuad = false;
};

bool parseQuad(const char* s, float out[8]) {
  int n = 0;
  const char* p = s;
  char* end = nullptr;
  while (n < 8) {
    out[n] = std::strtof(p, &end);
    if (end == p) return false;
    ++n;
    p = end;
    if (*p == ',') ++p;
  }
  return n == 8;
}

Args parseArgs(int argc, char** argv) {
  Args a;
  for (int i = 1; i < argc; ++i) {
    const std::string k = argv[i];
    auto next = [&]() -> const char* {
      if (i + 1 >= argc) {
        std::fprintf(stderr, "bench_pipeline: missing value for %s\n",
                     k.c_str());
        std::exit(2);
      }
      return argv[++i];
    };
    if (k == "--rgba") a.rgba = next();
    else if (k == "--out") a.out = next();
    else if (k == "--mode") a.mode = next();
    else if (k == "--width") a.width = std::atoi(next());
    else if (k == "--height") a.height = std::atoi(next());
    else if (k == "--quad") a.haveQuad = parseQuad(next(), a.quad);
    else {
      std::fprintf(stderr, "bench_pipeline: unknown arg %s\n", k.c_str());
      std::exit(2);
    }
  }
  return a;
}

supy_enhance_mode_t parseMode(const std::string& m) {
  if (m == "off") return SUPY_ENHANCE_OFF;
  if (m == "fast") return SUPY_ENHANCE_FAST;
  if (m == "balanced") return SUPY_ENHANCE_BALANCED;
  if (m == "max") return SUPY_ENHANCE_MAX;
  std::fprintf(stderr, "bench_pipeline: unknown mode %s\n", m.c_str());
  std::exit(2);
}

std::vector<uint8_t> readAll(const std::string& path) {
  std::FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    std::fprintf(stderr, "bench_pipeline: cannot open %s\n", path.c_str());
    std::exit(2);
  }
  std::fseek(f, 0, SEEK_END);
  const long size = std::ftell(f);
  std::fseek(f, 0, SEEK_SET);
  std::vector<uint8_t> buf(size > 0 ? static_cast<size_t>(size) : 0);
  if (!buf.empty() && std::fread(buf.data(), 1, buf.size(), f) != buf.size()) {
    std::fclose(f);
    std::fprintf(stderr, "bench_pipeline: short read on %s\n", path.c_str());
    std::exit(2);
  }
  std::fclose(f);
  return buf;
}

void writeAll(const std::string& path, const uint8_t* data, size_t size) {
  std::FILE* f = std::fopen(path.c_str(), "wb");
  if (!f || std::fwrite(data, 1, size, f) != size) {
    if (f) std::fclose(f);
    std::fprintf(stderr, "bench_pipeline: cannot write %s\n", path.c_str());
    std::exit(2);
  }
  std::fclose(f);
}

// Copies a possibly-strided RGBA buffer into a packed vector.
std::vector<uint8_t> packRows(const uint8_t* src, int w, int h, int stride) {
  std::vector<uint8_t> out(static_cast<size_t>(w) * h * 4);
  for (int y = 0; y < h; ++y) {
    std::memcpy(out.data() + static_cast<size_t>(y) * w * 4,
                src + static_cast<size_t>(y) * stride,
                static_cast<size_t>(w) * 4);
  }
  return out;
}

}  // namespace

int main(int argc, char** argv) {
  const Args a = parseArgs(argc, argv);
  if (a.rgba.empty() || a.out.empty() || a.width <= 0 || a.height <= 0 ||
      !a.haveQuad) {
    std::fprintf(stderr,
                 "usage: bench_pipeline --rgba <path> --width W --height H "
                 "--quad x0,y0,...,x3,y3 --mode <off|fast|balanced|max> "
                 "--out <path>\n");
    return 2;
  }
  const std::vector<uint8_t> rgba = readAll(a.rgba);
  const size_t expected =
      static_cast<size_t>(a.width) * static_cast<size_t>(a.height) * 4;
  if (rgba.size() != expected) {
    std::fprintf(stderr, "bench_pipeline: %s is %zu bytes, expected %zu\n",
                 a.rgba.c_str(), rgba.size(), expected);
    return 2;
  }

  supy_warp_input_t warpIn;
  std::memset(&warpIn, 0, sizeof(warpIn));
  warpIn.rgba = rgba.data();
  warpIn.width = a.width;
  warpIn.height = a.height;
  warpIn.row_stride = a.width * 4;
  for (int i = 0; i < 8; ++i) {
    warpIn.src_corners[i] =
        a.quad[i] * static_cast<float>(i % 2 == 0 ? a.width : a.height);
  }
  warpIn.max_long_side = 0;  // unbounded; bench measures full-res output

  supy_warp_result_t* warp = supy_core_warp(&warpIn);
  if (!warp) {
    std::fprintf(stderr, "bench_pipeline: supy_core_warp failed\n");
    return 3;
  }
  const int outW = supy_core_warp_width(warp);
  const int outH = supy_core_warp_height(warp);
  const int outStride = supy_core_warp_row_stride(warp);
  const uint8_t* warped = supy_core_warp_rgba(warp);

  supy_enhance_input_t enhIn;
  std::memset(&enhIn, 0, sizeof(enhIn));
  enhIn.rgba = warped;
  enhIn.width = outW;
  enhIn.height = outH;
  enhIn.row_stride = outStride;
  enhIn.mode = parseMode(a.mode);
  enhIn.min_blur_score = 0.0f;

  supy_enhance_result_t* enh = supy_core_enhance(&enhIn);
  if (!enh) {
    // Mirror production policy: enhance failure → un-enhanced warp output.
    const std::vector<uint8_t> packed = packRows(warped, outW, outH, outStride);
    writeAll(a.out, packed.data(), packed.size());
    std::printf(
        "DSQ_PIPELINE {\"outWidth\":%d,\"outHeight\":%d,\"enhanced\":false,"
        "\"appliedStages\":0,\"qualityScore\":0.0,\"verdict\":-1,"
        "\"processingMs\":0}\n",
        outW, outH);
    supy_core_warp_free(warp);
    return 0;
  }

  const std::vector<uint8_t> packed =
      packRows(supy_core_enhance_rgba(enh), supy_core_enhance_width(enh),
               supy_core_enhance_height(enh), supy_core_enhance_row_stride(enh));
  writeAll(a.out, packed.data(), packed.size());
  std::printf(
      "DSQ_PIPELINE {\"outWidth\":%d,\"outHeight\":%d,\"enhanced\":true,"
      "\"appliedStages\":%u,\"qualityScore\":%.2f,\"verdict\":%d,"
      "\"processingMs\":%d}\n",
      supy_core_enhance_width(enh), supy_core_enhance_height(enh),
      supy_core_enhance_applied_stages(enh),
      static_cast<double>(supy_core_enhance_quality_score(enh)),
      supy_core_enhance_verdict(enh), supy_core_enhance_processing_ms(enh));

  supy_core_enhance_free(enh);
  supy_core_warp_free(warp);
  return 0;
}
```

- [ ] **Step 2: Add the CMake target**

In the same `if(SUPY_BUILD_TOOLS)` block of `native/CMakeLists.txt`, after `bench_detect`, add:

```cmake
  add_executable(bench_pipeline bench/bench_pipeline.cpp)
  target_link_libraries(bench_pipeline PRIVATE supy_scanner_core)
  target_compile_options(bench_pipeline PRIVATE -O3 -Wall -Wextra -Wpedantic -Werror)
```

(`bench_pipeline` only includes public headers from `native/include/`, which `supy_scanner_core` already exposes; no extra include dir needed.)

- [ ] **Step 3: Build**

Run: `cmake --build build/dsq-bench --target bench_pipeline --config Release`
Expected: clean build.

- [ ] **Step 4: Run against a seed frame**

```bash
cat > /tmp/dsq_dump_rgba.dart <<'EOF'
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final frame =
      img.decodePng(File(args[0]).readAsBytesSync())!.convert(numChannels: 4);
  File(args[1]).writeAsBytesSync(
      frame.getBytes(order: img.ChannelOrder.rgba));
  print('${frame.width} ${frame.height}');
}
EOF
(cd tools/bench && dart /tmp/dsq_dump_rgba.dart \
  ../../bench/corpus/seed-001/frame.png /tmp/seed-001.rgba)
./build/dsq-bench/bench_pipeline --rgba /tmp/seed-001.rgba \
  --width 1280 --height 960 \
  --quad 0.2,0.2,0.8,0.2,0.8,0.8,0.2,0.8 \
  --mode balanced --out /tmp/seed-001-out.rgba
```
Expected: one `DSQ_PIPELINE {...,"enhanced":true,...}` line with `outWidth`≈768, `outHeight`≈576 (the page region), and `/tmp/seed-001-out.rgba` of exactly `outWidth*outHeight*4` bytes (`stat -f%z /tmp/seed-001-out.rgba`).

- [ ] **Step 5: Commit**

```bash
git add native/bench/bench_pipeline.cpp native/CMakeLists.txt
git commit -m "feat(bench): bench_pipeline host harness (warp+enhance replay)"
```

---

### Task 7: macOS Vision OCR CLI

**Files:**
- Create: `tools/bench/ocr/vision_ocr.swift`

**Interfaces:**
- Consumes: nothing from this repo (Vision.framework + AppKit only).
- Produces (consumed by Task 9): binary built via
  `swiftc -O -o build/dsq-bench/vision_ocr tools/bench/ocr/vision_ocr.swift`
  invoked as `vision_ocr <image-path>`; prints recognized text lines (one per Vision observation, reading order) to stdout; exit 0 on success (including "no text found" → empty stdout), 2 on unreadable image / bad args.

- [ ] **Step 1: Write the CLI**

Create `tools/bench/ocr/vision_ocr.swift`:

```swift
// macOS Vision OCR CLI for the DSQ bench CER lane. Host tool only — the
// scanning path never does OCR through this (and never does cloud OCR at
// all, per CLAUDE.md). Prints one line per recognized text observation.
//
// Build: swiftc -O -o build/dsq-bench/vision_ocr tools/bench/ocr/vision_ocr.swift
// Usage: vision_ocr <image-path>

import AppKit
import Foundation
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: vision_ocr <image-path>")
}

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fail("vision_ocr: cannot load image at \(path)")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false

let handler = VNImageRequestHandler(cgImage: cgImage)
do {
    try handler.perform([request])
} catch {
    fail("vision_ocr: recognition failed: \(error)")
}

for observation in request.results ?? [] {
    if let candidate = observation.topCandidates(1).first {
        print(candidate.string)
    }
}
```

- [ ] **Step 2: Build and smoke-test on a seed frame**

Run:
```bash
mkdir -p build/dsq-bench
swiftc -O -o build/dsq-bench/vision_ocr tools/bench/ocr/vision_ocr.swift
./build/dsq-bench/vision_ocr bench/corpus/seed-001/frame.png
```
Expected: prints text containing `RECEIPT` and `TOTAL` (arial48 on a clean synthetic page — Vision reads this reliably). Exact digits may vary slightly; the CER metric absorbs that.

- [ ] **Step 3: Verify failure path**

Run: `./build/dsq-bench/vision_ocr /nonexistent.png; echo "exit=$?"`
Expected: stderr `cannot load image`, `exit=2`.

- [ ] **Step 4: Commit**

```bash
git add tools/bench/ocr/vision_ocr.swift
git commit -m "feat(bench): macOS Vision OCR CLI for the CER lane"
```

---

### Task 8: Aggregation, report rendering, and the ±2% gate

**Files:**
- Create: `tools/bench/lib/report.dart`
- Create: `tools/bench/baselines/README.md`
- Test: `tools/bench/test/report_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure data transforms; the driver in Task 9 feeds it).
- Produces:
  - `class OutputMetrics { double sharpness; double uniformity; double? dpi; double? cer; }`
  - `class SceneResult { String id; String docType; String lighting; bool labelHasDoc; bool? detected; double? iou; OutputMetrics? ours; OutputMetrics? scanbot; }`
  - `class BenchSummary { int scenes; Map<String, double> metrics; Map<String, Map<String, double>> perLighting; Map<String, Object?> toJson(); static BenchSummary fromJson(Map); }`
  - `BenchSummary aggregate(List<SceneResult> results)` — metric keys: `detect_rate`, `mean_iou`, `false_positive_rate`, `ours_sharpness`, `ours_uniformity`, `ours_dpi`, `ours_cer`, `scanbot_sharpness`, `scanbot_uniformity`, `scanbot_cer` (a key is absent when no scene produced it). `mean_iou` counts undetected labeled scenes as IoU 0. `detect_rate` = detected/labeled. `false_positive_rate` = detections on `quad:null` scenes / negative-scene count.
  - `String renderMarkdown(BenchSummary summary, Map<String, BenchSummary> baselines)` — scoreboard table + per-lighting table + delta columns per baseline.
  - `class GateResult { String metric; double observed; double baseline; double deltaPct; bool regressed; }` and `List<GateResult> gate(BenchSummary observed, BenchSummary baseline, {double tolerancePct = 2.0})` — direction-aware: `ours_cer` and `false_positive_rate` are lower-is-better, everything else higher-is-better; only `detect_rate`, `mean_iou`, `false_positive_rate`, `ours_*` are gated (`scanbot_*` are reference numbers).

- [ ] **Step 1: Write the failing test**

Create `tools/bench/test/report_test.dart`:

```dart
import 'package:test/test.dart';

import '../lib/report.dart';

SceneResult scene(String id, String lighting,
        {bool labelHasDoc = true,
        bool? detected,
        double? iou,
        OutputMetrics? ours,
        OutputMetrics? scanbot}) =>
    SceneResult(
        id: id,
        docType: 'receipt',
        lighting: lighting,
        labelHasDoc: labelHasDoc,
        detected: detected,
        iou: iou,
        ours: ours,
        scanbot: scanbot);

void main() {
  test('aggregate computes rates, means, and per-lighting breakdown', () {
    final results = [
      scene('a', 'good',
          detected: true,
          iou: 0.9,
          ours: OutputMetrics(
              sharpness: 100, uniformity: 0.9, dpi: 300, cer: 0.1),
          scanbot: OutputMetrics(
              sharpness: 80, uniformity: 0.8, dpi: null, cer: 0.2)),
      scene('b', 'dim', detected: false, iou: null),
      scene('c', 'good', labelHasDoc: false, detected: true),
    ];
    final s = aggregate(results);
    expect(s.scenes, 3);
    expect(s.metrics['detect_rate'], closeTo(0.5, 1e-9)); // 1 of 2 labeled
    expect(s.metrics['mean_iou'], closeTo(0.45, 1e-9)); // (0.9 + 0) / 2
    expect(s.metrics['false_positive_rate'], closeTo(1.0, 1e-9)); // 1 of 1
    expect(s.metrics['ours_sharpness'], closeTo(100, 1e-9));
    expect(s.metrics['ours_cer'], closeTo(0.1, 1e-9));
    expect(s.metrics['scanbot_sharpness'], closeTo(80, 1e-9));
    expect(s.metrics.containsKey('scanbot_dpi'), isFalse);
    expect(s.perLighting['good']!['detect_rate'], closeTo(1.0, 1e-9));
    expect(s.perLighting['dim']!['detect_rate'], closeTo(0.0, 1e-9));
  });

  test('summary JSON round-trips', () {
    final s = aggregate([scene('a', 'good', detected: true, iou: 0.8)]);
    final back = BenchSummary.fromJson(s.toJson());
    expect(back.scenes, s.scenes);
    expect(back.metrics, s.metrics);
    expect(back.perLighting, s.perLighting);
  });

  test('gate flags direction-aware regressions beyond 2%', () {
    final base = BenchSummary(scenes: 1, metrics: {
      'mean_iou': 0.80,
      'ours_cer': 0.10,
      'scanbot_sharpness': 500.0,
    }, perLighting: {});
    final observed = BenchSummary(scenes: 1, metrics: {
      'mean_iou': 0.76, // -5% on higher-is-better → regressed
      'ours_cer': 0.11, // +10% on lower-is-better → regressed
      'scanbot_sharpness': 100.0, // reference metric → never gated
    }, perLighting: {});
    final results = gate(observed, base);
    expect(results.where((r) => r.regressed).map((r) => r.metric).toSet(),
        {'mean_iou', 'ours_cer'});
    expect(results.any((r) => r.metric == 'scanbot_sharpness'), isFalse);
  });

  test('gate passes small movements within tolerance', () {
    final base = BenchSummary(
        scenes: 1, metrics: {'mean_iou': 0.80}, perLighting: {});
    final observed = BenchSummary(
        scenes: 1, metrics: {'mean_iou': 0.79}, perLighting: {}); // -1.25%
    expect(gate(observed, base).single.regressed, isFalse);
  });

  test('renderMarkdown includes scoreboard and deltas', () {
    final s = aggregate([
      scene('a', 'good',
          detected: true,
          iou: 0.9,
          ours: OutputMetrics(
              sharpness: 100, uniformity: 0.9, dpi: 300, cer: 0.1))
    ]);
    final md = renderMarkdown(s, {'scanbot': s});
    expect(md, contains('# DSQ bench report'));
    expect(md, contains('mean_iou'));
    expect(md, contains('Δ vs scanbot'));
    expect(md, contains('## Per-lighting'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/bench && dart test test/report_test.dart`
Expected: FAIL — `../lib/report.dart` does not exist.

- [ ] **Step 3: Implement**

Create `tools/bench/lib/report.dart`:

```dart
// Aggregation + report rendering + regression gate for the DSQ bench.
// The gate implements the program-wide rule from the DSQ spec: no metric
// regresses by more than ±2% (direction-aware) vs the pinned baseline.

class OutputMetrics {
  OutputMetrics(
      {required this.sharpness, required this.uniformity, this.dpi, this.cer});

  final double sharpness;
  final double uniformity;
  final double? dpi;
  final double? cer;
}

class SceneResult {
  SceneResult({
    required this.id,
    required this.docType,
    required this.lighting,
    required this.labelHasDoc,
    this.detected,
    this.iou,
    this.ours,
    this.scanbot,
  });

  final String id;
  final String docType;
  final String lighting;
  final bool labelHasDoc;
  final bool? detected;
  final double? iou;
  final OutputMetrics? ours;
  final OutputMetrics? scanbot;
}

class BenchSummary {
  BenchSummary(
      {required this.scenes, required this.metrics, required this.perLighting});

  final int scenes;
  final Map<String, double> metrics;
  final Map<String, Map<String, double>> perLighting;

  Map<String, Object?> toJson() => {
        'scenes': scenes,
        'metrics': metrics,
        'perLighting': perLighting,
      };

  static BenchSummary fromJson(Map<String, Object?> json) => BenchSummary(
        scenes: json['scenes'] as int,
        metrics: (json['metrics'] as Map).map(
            (k, v) => MapEntry(k as String, (v as num).toDouble())),
        perLighting: (json['perLighting'] as Map).map((k, v) => MapEntry(
            k as String,
            (v as Map)
                .map((k2, v2) => MapEntry(k2 as String, (v2 as num).toDouble())))),
      );
}

double? _mean(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return null;
  return list.reduce((a, b) => a + b) / list.length;
}

Map<String, double> _detectionMetrics(List<SceneResult> results) {
  final labeled = results.where((r) => r.labelHasDoc).toList();
  final negatives = results.where((r) => !r.labelHasDoc).toList();
  final m = <String, double>{};
  if (labeled.isNotEmpty) {
    m['detect_rate'] =
        labeled.where((r) => r.detected == true).length / labeled.length;
    m['mean_iou'] = labeled
            .map((r) => (r.detected == true ? (r.iou ?? 0.0) : 0.0))
            .reduce((a, b) => a + b) /
        labeled.length;
  }
  if (negatives.isNotEmpty) {
    m['false_positive_rate'] =
        negatives.where((r) => r.detected == true).length / negatives.length;
  }
  return m;
}

Map<String, double> _outputMetrics(
    List<SceneResult> results, String prefix, OutputMetrics? Function(SceneResult) pick) {
  final m = <String, double>{};
  void put(String key, double? Function(OutputMetrics) f) {
    final mean = _mean(results
        .map(pick)
        .whereType<OutputMetrics>()
        .map(f)
        .whereType<double>());
    if (mean != null) m['${prefix}_$key'] = mean;
  }

  put('sharpness', (o) => o.sharpness);
  put('uniformity', (o) => o.uniformity);
  put('dpi', (o) => o.dpi);
  put('cer', (o) => o.cer);
  return m;
}

BenchSummary aggregate(List<SceneResult> results) {
  final metrics = <String, double>{
    ..._detectionMetrics(results),
    ..._outputMetrics(results, 'ours', (r) => r.ours),
    ..._outputMetrics(results, 'scanbot', (r) => r.scanbot),
  };
  final perLighting = <String, Map<String, double>>{};
  final lightings = results.map((r) => r.lighting).toSet().toList()..sort();
  for (final lighting in lightings) {
    final subset = results.where((r) => r.lighting == lighting).toList();
    perLighting[lighting] = {
      ..._detectionMetrics(subset),
      ..._outputMetrics(subset, 'ours', (r) => r.ours),
    };
  }
  return BenchSummary(
      scenes: results.length, metrics: metrics, perLighting: perLighting);
}

/// Metrics where a smaller number is better.
const kLowerIsBetter = {'ours_cer', 'false_positive_rate'};

/// Metrics eligible for gating (scanbot_* are reference-only).
bool _gated(String metric) => !metric.startsWith('scanbot_');

class GateResult {
  GateResult(
      {required this.metric,
      required this.observed,
      required this.baseline,
      required this.deltaPct,
      required this.regressed});

  final String metric;
  final double observed;
  final double baseline;
  final double deltaPct;
  final bool regressed;
}

List<GateResult> gate(BenchSummary observed, BenchSummary baseline,
    {double tolerancePct = 2.0}) {
  final results = <GateResult>[];
  for (final entry in observed.metrics.entries) {
    if (!_gated(entry.key)) continue;
    final base = baseline.metrics[entry.key];
    if (base == null || base == 0) continue;
    final deltaPct = (entry.value - base) / base * 100.0;
    final worsePct =
        kLowerIsBetter.contains(entry.key) ? deltaPct : -deltaPct;
    results.add(GateResult(
      metric: entry.key,
      observed: entry.value,
      baseline: base,
      deltaPct: deltaPct,
      regressed: worsePct > tolerancePct,
    ));
  }
  return results;
}

String _fmt(double v) => v.toStringAsFixed(4);

String renderMarkdown(
    BenchSummary summary, Map<String, BenchSummary> baselines) {
  final buf = StringBuffer()
    ..writeln('# DSQ bench report')
    ..writeln()
    ..writeln('Scenes: ${summary.scenes}')
    ..writeln()
    ..writeln('## Scoreboard')
    ..writeln();
  final baselineNames = baselines.keys.toList()..sort();
  buf.write('| metric | value |');
  for (final name in baselineNames) {
    buf.write(' Δ vs $name |');
  }
  buf
    ..writeln()
    ..write('|---|---|');
  for (final _ in baselineNames) {
    buf.write('---|');
  }
  buf.writeln();
  final keys = summary.metrics.keys.toList()..sort();
  for (final key in keys) {
    final value = summary.metrics[key]!;
    buf.write('| $key | ${_fmt(value)} |');
    for (final name in baselineNames) {
      final base = baselines[name]!.metrics[key];
      if (base == null || base == 0) {
        buf.write(' n/a |');
      } else {
        final delta = (value - base) / base * 100.0;
        buf.write(' ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}% |');
      }
    }
    buf.writeln();
  }
  buf
    ..writeln()
    ..writeln('## Per-lighting')
    ..writeln();
  final allKeys = <String>{
    for (final m in summary.perLighting.values) ...m.keys
  }.toList()
    ..sort();
  buf.write('| lighting |');
  for (final k in allKeys) {
    buf.write(' $k |');
  }
  buf
    ..writeln()
    ..write('|---|');
  for (final _ in allKeys) {
    buf.write('---|');
  }
  buf.writeln();
  final lightings = summary.perLighting.keys.toList()..sort();
  for (final lighting in lightings) {
    buf.write('| $lighting |');
    for (final k in allKeys) {
      final v = summary.perLighting[lighting]![k];
      buf.write(v == null ? ' — |' : ' ${_fmt(v)} |');
    }
    buf.writeln();
  }
  return buf.toString();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/bench && dart test test/report_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Write the baselines doc and commit**

Create `tools/bench/baselines/README.md`:

```markdown
# DSQ bench baselines

Pinned `BenchSummary` JSONs the gate compares against
(`dart tools/bench/run_bench.dart --gate <name>`).

- `scanbot.json` — Scanbot's numbers on the corpus (pin once the real corpus
  with `scanbot.png` lanes lands: `run_bench.dart --pin scanbot` after a full
  run; this snapshots the `scanbot_*` metrics as the reference).
- `prev.json` — our own numbers from the last accepted phase. Re-pin at each
  DSQ phase merge (`--pin prev`), with the phase named in the commit message.

Pinning refuses to overwrite an existing file without `--force`. A PR that
moves a baseline must say why in its description — same policy as
`tools/perfgate/PROMOTION_CHECKLIST.md`.
```

```bash
git add tools/bench/lib/report.dart tools/bench/test/report_test.dart \
  tools/bench/baselines/README.md
git commit -m "feat(bench): aggregation, markdown report and ±2% gate"
```

---

### Task 9: `run_bench.dart` driver

**Files:**
- Create: `tools/bench/run_bench.dart`

**Interfaces:**
- Consumes: everything above — `loadCorpus`/`validateCorpus` (Task 1), `quadIou` (Task 2), `varianceOfLaplacian`/`illuminationUniformity`/`effectiveDpi`/`cer` (Task 3), seed corpus (Task 4), `bench_detect` (Task 5), `bench_pipeline` (Task 6), `vision_ocr` (Task 7), `aggregate`/`renderMarkdown`/`gate`/`BenchSummary` (Task 8).
- Produces: CLI
  `dart tools/bench/run_bench.dart [--suite all|detect|output] [--corpus bench/corpus] [--skip-build] [--skip-ocr] [--gate <name>] [--pin <name>] [--force]`
  writing `tools/bench/report/bench_report.json` (`{"summary": BenchSummary, "scenes": [...] }`) and `tools/bench/report/bench_report.md`, plus per-scene rectified PNGs under `tools/bench/report/pages/`. Exit codes: 0 clean, 1 gate regression, 2 setup error (corpus invalid, build failed, harness crashed).

- [ ] **Step 1: Write the driver**

Create `tools/bench/run_bench.dart`:

```dart
// DSQ bench driver. Decodes corpus PNGs, feeds raw pixels to the host C++
// harnesses (bench_detect, bench_pipeline), computes metrics in Dart, and
// writes bench_report.{md,json} with deltas vs pinned baselines.
//
// Pixels reach native code via temp files + argv — never dart:ffi, per the
// supy_scanner_core.h boundary contract.
//
// Usage:
//   dart tools/bench/run_bench.dart [--suite all|detect|output]
//     [--corpus bench/corpus] [--skip-build] [--skip-ocr]
//     [--gate <baseline-name>] [--pin <baseline-name>] [--force]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'lib/corpus.dart';
import 'lib/metrics.dart';
import 'lib/quad_iou.dart';
import 'lib/report.dart';

const _buildDir = 'build/dsq-bench';
const _reportDir = 'tools/bench/report';
const _baselinesDir = 'tools/bench/baselines';

Directory _repoRoot() {
  // tools/bench/run_bench.dart → repo root is two levels up.
  final script = File.fromUri(Platform.script);
  return script.parent.parent.parent;
}

Map<String, String> _parseArgs(List<String> argv) {
  final args = <String, String>{};
  const withValue = {'--suite', '--corpus', '--gate', '--pin'};
  for (var i = 0; i < argv.length; i++) {
    final k = argv[i];
    if (withValue.contains(k)) {
      if (i + 1 >= argv.length) {
        stderr.writeln('[bench] missing value for $k');
        exit(2);
      }
      args[k.substring(2)] = argv[++i];
    } else if (k.startsWith('--')) {
      args[k.substring(2)] = '';
    } else {
      stderr.writeln('[bench] unknown arg $k');
      exit(2);
    }
  }
  return args;
}

Future<void> _buildTools(String root, {required bool ocr}) async {
  Future<void> run(String exe, List<String> cmd) async {
    stdout.writeln('[bench] $exe ${cmd.join(' ')}');
    final proc = await Process.start(exe, cmd, workingDirectory: root,
        mode: ProcessStartMode.inheritStdio);
    if (await proc.exitCode != 0) {
      stderr.writeln('[bench] $exe failed');
      exit(2);
    }
  }

  await run('cmake', [
    '-S', 'native', '-B', _buildDir,
    '-DSUPY_BUILD_TOOLS=ON', '-DCMAKE_BUILD_TYPE=Release',
  ]);
  await run('cmake', [
    '--build', _buildDir, '--target', 'bench_detect', '--target',
    'bench_pipeline', '--config', 'Release',
  ]);
  if (ocr) {
    await run('swiftc', [
      '-O', '-o', '$_buildDir/vision_ocr', 'tools/bench/ocr/vision_ocr.swift',
    ]);
  }
}

Map<String, Object?> _parseJsonLine(String output, String tag) {
  for (final line in const LineSplitter().convert(output)) {
    final idx = line.indexOf('$tag ');
    if (idx < 0) continue;
    final start = line.indexOf('{', idx);
    if (start < 0) continue;
    return jsonDecode(line.substring(start)) as Map<String, Object?>;
  }
  stderr.writeln('[bench] no $tag line in harness output:\n$output');
  exit(2);
}

Uint8List _lumaOf(img.Image frame) {
  final luma = Uint8List(frame.width * frame.height);
  var i = 0;
  for (final p in frame) {
    luma[i++] = img.getLuminance(p).round().clamp(0, 255);
  }
  return luma;
}

class _Harness {
  _Harness(this.root, this.scratch);

  final String root;
  final Directory scratch;

  Future<({bool detected, List<double>? quad})> detect(
      img.Image frame, String sceneId) async {
    final grayPath = '${scratch.path}/$sceneId.gray';
    File(grayPath).writeAsBytesSync(_lumaOf(frame));
    final result = await Process.run('$root/$_buildDir/bench_detect', [
      '--gray', grayPath,
      '--width', '${frame.width}',
      '--height', '${frame.height}',
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('[bench] bench_detect failed on $sceneId:\n'
          '${result.stderr}');
      exit(2);
    }
    final json = _parseJsonLine(result.stdout as String, 'DSQ_DETECT');
    if (json['detected'] != true) return (detected: false, quad: null);
    final quad =
        (json['quad'] as List).map((v) => (v as num).toDouble()).toList();
    return (detected: true, quad: quad);
  }

  Future<({img.Image page, Map<String, Object?> info})?> pipeline(
      img.Image frame, List<double> quad, String sceneId) async {
    final rgbaPath = '${scratch.path}/$sceneId.rgba';
    final outPath = '${scratch.path}/$sceneId.out.rgba';
    final rgba = frame.convert(numChannels: 4);
    File(rgbaPath)
        .writeAsBytesSync(rgba.getBytes(order: img.ChannelOrder.rgba));
    final result = await Process.run('$root/$_buildDir/bench_pipeline', [
      '--rgba', rgbaPath,
      '--width', '${frame.width}',
      '--height', '${frame.height}',
      '--quad', quad.map((v) => v.toStringAsFixed(6)).join(','),
      '--mode', 'balanced',
      '--out', outPath,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('[bench] bench_pipeline failed on $sceneId:\n'
          '${result.stderr}');
      return null;
    }
    final info = _parseJsonLine(result.stdout as String, 'DSQ_PIPELINE');
    final w = info['outWidth'] as int;
    final h = info['outHeight'] as int;
    final bytes = File(outPath).readAsBytesSync();
    final page = img.Image.fromBytes(
        width: w, height: h, bytes: bytes.buffer,
        order: img.ChannelOrder.rgba);
    return (page: page, info: info);
  }

  Future<String?> ocr(String imagePath) async {
    final bin = File('$root/$_buildDir/vision_ocr');
    if (!bin.existsSync()) return null;
    final result = await Process.run(bin.path, [imagePath]);
    if (result.exitCode != 0) {
      stderr.writeln('[bench] vision_ocr failed on $imagePath:\n'
          '${result.stderr}');
      return null;
    }
    return result.stdout as String;
  }
}

Future<OutputMetrics> _measurePage(
    img.Image page, Scene scene, _Harness harness, String pngPath,
    {required bool withOcr}) async {
  File(pngPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(page));
  final luma = _lumaOf(page);
  double? cerValue;
  if (withOcr && scene.truthFile.existsSync()) {
    final recognized = await harness.ocr(pngPath);
    if (recognized != null) {
      cerValue = cer(scene.truthFile.readAsStringSync(), recognized);
    }
  }
  return OutputMetrics(
    sharpness: varianceOfLaplacian(luma, page.width, page.height),
    uniformity: illuminationUniformity(luma, page.width, page.height),
    dpi: scene.physicalWidthMm == null
        ? null
        : effectiveDpi(page.width, scene.physicalWidthMm!),
    cer: cerValue,
  );
}

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  final suite = args['suite'] ?? 'all';
  if (!{'all', 'detect', 'output'}.contains(suite)) {
    stderr.writeln('[bench] --suite must be all|detect|output');
    exit(2);
  }
  final root = _repoRoot().path;
  final corpusDir = Directory('$root/${args['corpus'] ?? 'bench/corpus'}');
  final skipOcr = args.containsKey('skip-ocr') || !Platform.isMacOS;

  final scenes = loadCorpus(corpusDir);
  final errors = validateCorpus(scenes);
  if (scenes.isEmpty || errors.isNotEmpty) {
    errors.forEach(stderr.writeln);
    stderr.writeln('[bench] corpus invalid (${errors.length} errors, '
        '${scenes.length} scenes)');
    exit(2);
  }
  stdout.writeln('[bench] ${scenes.length} scenes, suite=$suite'
      '${skipOcr ? ', OCR off' : ''}');

  if (!args.containsKey('skip-build')) {
    await _buildTools(root, ocr: !skipOcr);
  }

  final scratch = Directory.systemTemp.createTempSync('dsq_bench');
  final harness = _Harness(root, scratch);
  final results = <SceneResult>[];
  try {
    for (final scene in scenes) {
      final frame = img.decodePng(scene.frameFile.readAsBytesSync());
      if (frame == null) {
        stderr.writeln('[bench] cannot decode ${scene.frameFile.path} — '
            'is Git LFS hydrated? (git lfs pull)');
        exit(2);
      }

      bool? detected;
      double? iou;
      if (suite != 'output') {
        final d = await harness.detect(frame, scene.id);
        detected = d.detected;
        if (d.detected && scene.quad != null) {
          iou = quadIou(scene.quad!, d.quad!);
        }
      }

      OutputMetrics? ours;
      OutputMetrics? scanbot;
      if (suite != 'detect' && scene.quad != null) {
        final piped = await harness.pipeline(frame, scene.quad!, scene.id);
        if (piped != null) {
          ours = await _measurePage(piped.page, scene, harness,
              '$root/$_reportDir/pages/${scene.id}.png',
              withOcr: !skipOcr);
        }
        if (scene.scanbotFile.existsSync()) {
          final sb = img.decodePng(scene.scanbotFile.readAsBytesSync());
          if (sb != null) {
            scanbot = await _measurePage(sb, scene, harness,
                '$root/$_reportDir/pages/${scene.id}.scanbot.png',
                withOcr: !skipOcr);
          }
        }
      }

      results.add(SceneResult(
        id: scene.id,
        docType: scene.docType,
        lighting: scene.lighting,
        labelHasDoc: scene.quad != null,
        detected: detected,
        iou: iou,
        ours: ours,
        scanbot: scanbot,
      ));
      stdout.writeln('[bench] ${scene.id}: detected=$detected '
          'iou=${iou?.toStringAsFixed(3)} '
          'cer=${ours?.cer?.toStringAsFixed(3)}');
    }
  } finally {
    scratch.deleteSync(recursive: true);
  }

  final summary = aggregate(results);

  final baselines = <String, BenchSummary>{};
  final baseDir = Directory('$root/$_baselinesDir');
  if (baseDir.existsSync()) {
    for (final f in baseDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final name = f.uri.pathSegments.last.replaceAll('.json', '');
      baselines[name] = BenchSummary.fromJson(
          jsonDecode(f.readAsStringSync()) as Map<String, Object?>);
    }
  }

  final reportDir = Directory('$root/$_reportDir')..createSync(recursive: true);
  File('${reportDir.path}/bench_report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
    'summary': summary.toJson(),
    'scenes': [
      for (final r in results)
        {
          'id': r.id,
          'lighting': r.lighting,
          'detected': r.detected,
          'iou': r.iou,
          'ours_cer': r.ours?.cer,
          'scanbot_cer': r.scanbot?.cer,
        }
    ],
  }));
  File('${reportDir.path}/bench_report.md')
      .writeAsStringSync(renderMarkdown(summary, baselines));
  stdout.writeln('[bench] report → $_reportDir/bench_report.md');
  for (final e in (summary.metrics.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key)))) {
    stdout.writeln('[bench]   ${e.key} = ${e.value.toStringAsFixed(4)}');
  }

  final pinName = args['pin'];
  if (pinName != null) {
    baseDir.createSync(recursive: true);
    final f = File('${baseDir.path}/$pinName.json');
    if (f.existsSync() && !args.containsKey('force')) {
      stderr.writeln('[bench] $pinName.json exists; use --force to re-pin');
      exit(2);
    }
    f.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(summary.toJson()));
    stdout.writeln('[bench] pinned baseline $pinName');
  }

  final gateName = args['gate'];
  if (gateName != null) {
    final base = baselines[gateName];
    if (base == null) {
      stderr.writeln('[bench] no baseline named $gateName in $_baselinesDir');
      exit(2);
    }
    final gateResults = gate(summary, base);
    var regressed = false;
    for (final g in gateResults) {
      final flag = g.regressed ? 'REGRESSED' : 'ok';
      stdout.writeln('[gate] ${g.metric}: ${g.observed.toStringAsFixed(4)} '
          'vs ${g.baseline.toStringAsFixed(4)} '
          '(${g.deltaPct >= 0 ? '+' : ''}${g.deltaPct.toStringAsFixed(1)}%) '
          '$flag');
      regressed |= g.regressed;
    }
    if (regressed) exit(1);
  }
}
```

- [ ] **Step 2: End-to-end run, detect suite**

Run: `dart tools/bench/run_bench.dart --suite detect --skip-build`
(Harnesses were built in Tasks 5–6; drop `--skip-build` if `build/dsq-bench/` is gone.)
Expected: six `[bench] seed-00N: detected=...` lines; summary shows `detect_rate` and `mean_iou`; `tools/bench/report/bench_report.md` exists. On the clean seed scenes expect `detect_rate` ≥ 0.5 and `mean_iou` ≥ 0.4 — dim/glare seeds may legitimately miss; record whatever the classical detector actually scores (that IS the DSQ2 baseline motivation), do not tune the harness to flatter it.

- [ ] **Step 3: End-to-end run, full suite with OCR**

Run: `dart tools/bench/run_bench.dart --suite all --skip-build`
Expected: per-scene `cer=` values on macOS; `ours_sharpness`, `ours_uniformity`, `ours_dpi`, `ours_cer` in the summary; rectified pages under `tools/bench/report/pages/seed-00N.png` (open one — it should be the warped, enhanced page crop). `ours_dpi` ≈ 768/6 = **128** on seed frames (small synthetic frames — the low number is exactly the gap DSQ1's max-res work will close).

- [ ] **Step 4: Verify pin + gate loop**

Run:
```bash
dart tools/bench/run_bench.dart --suite all --skip-build --pin prev
dart tools/bench/run_bench.dart --suite all --skip-build --gate prev
echo "exit=$?"
```
Expected: first run writes `tools/bench/baselines/prev.json`; second prints `[gate] ... ok` lines and `exit=0` (identical corpus → CER/sharpness identical; Vision OCR is deterministic on identical input). Then delete the scratch baseline — seed-only baselines must not be committed: `rm tools/bench/baselines/prev.json`.

- [ ] **Step 5: Commit**

```bash
git add tools/bench/run_bench.dart
git commit -m "feat(bench): run_bench driver with report, pin and gate modes"
```

---

### Task 10: CI job

**Files:**
- Modify: `.github/workflows/ci.yml` (append a job after `enhance-bench-low`)

**Interfaces:**
- Consumes: `dart tools/bench/run_bench.dart --suite all` (Task 9), tools/bench tests (Tasks 1–3, 8), corpus in LFS (Task 4).
- Produces: `dsq-bench` job on `macos-14` — unit tests + full host bench on every PR, `bench_report.md` uploaded as artifact. `continue-on-error: true` until the real corpus and baselines land (same policy as `enhance-bench-low` and `perfgate-emulator`).

- [ ] **Step 1: Add the job**

Append to `.github/workflows/ci.yml` (match the existing pinned action SHAs used by other jobs in this file):

```yaml
  # dsq-bench runs the DSQ0 host bench over bench/corpus: unit tests for the
  # bench libs, then the full detect + pipeline-replay + Vision-OCR run, and
  # uploads bench_report.md. macOS runner because the CER lane needs
  # Vision.framework. Tracks DSQ0
  # (docs/superpowers/specs/2026-07-16-doc-scan-quality-design.md).
  #
  # Non-blocking (continue-on-error) until the real corpus + pinned baselines
  # land — mirrors the enhance-bench-low / perfgate-emulator policy. Flip to
  # blocking with `--gate prev` when DSQ1 pins its first baseline.
  dsq-bench:
    name: dsq bench (host replay)
    runs-on: macos-14
    needs: [analyze-and-test]
    timeout-minutes: 30
    continue-on-error: true
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
        with:
          lfs: true

      - uses: dart-lang/setup-dart@0a8a0fc875eb934c15d08629302413c671d3f672  # v1.6.5
        with:
          sdk: '3.4.0'

      - name: dart pub get (tools/bench)
        working-directory: tools/bench
        run: dart pub get

      - name: dart test (tools/bench)
        working-directory: tools/bench
        run: dart test

      - name: validate corpus
        run: dart tools/bench/validate_corpus.dart

      - name: run dsq bench (detect + output + OCR)
        run: dart tools/bench/run_bench.dart --suite all

      - name: upload bench report
        if: always()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02  # v4.6.2
        with:
          name: dsq-bench-report
          path: tools/bench/report/
```

- [ ] **Step 2: Validate the workflow file locally**

Run: `dart tools/bench/validate_corpus.dart && ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml"); puts "yaml ok"'`
Expected: `yaml ok` (ruby ships on macOS; if unavailable, `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml ok')"`).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "chore(ci): dsq-bench job — host bench + Vision OCR on macOS"
```

- [ ] **Step 4: Verify on CI**

Push the branch (or open the PR) and confirm the `dsq bench (host replay)` job goes green and the `dsq-bench-report` artifact contains `bench_report.md` with the seed-corpus scoreboard.

---

### Task 11: Capture guide, bench README, TODO tickets

**Files:**
- Create: `bench/corpus/CAPTURE_GUIDE.md`
- Create: `tools/bench/README.md`
- Modify: `TODO.md` (add DSQ program section)

**Interfaces:**
- Consumes: the schema (Task 1), driver flags (Task 9).
- Produces: the user-facing instructions for the one manual dependency in the program (real-corpus + Scanbot capture), and the sprint tracking entries CLAUDE.md requires.

- [ ] **Step 1: Write the capture guide**

Create `bench/corpus/CAPTURE_GUIDE.md`:

```markdown
# Corpus capture guide (manual, ~half a day)

The DSQ program needs ~120 real scenes with Scanbot reference output. This
is the only manual dependency in the program. Per scene:

1. **Stage the scene.** Composition targets (see README.md): thermal /
   crumpled receipts, A4 invoices, glossy menus × {plain, cluttered}
   backgrounds × {good, dim, shadow, glare} lighting. Add ~6 negative
   scenes (no document in frame).
2. **Capture `frame.png`.** Phone on a stand (scene must not move between
   the two captures). Use the plain camera app at max still resolution,
   export PNG (or lossless HEIC→PNG). This is the raw input both pipelines
   will be replayed against.
3. **Capture `scanbot.png`.** Without moving anything, scan the same scene
   with the current retailer app (Scanbot SDK path) and export its final
   processed page image.
4. **Label `scene.json`.** Copy the template from README.md. Mark the four
   document corners in frame.png (any image viewer with pixel readout),
   divide x by width and y by height, order TL,TR,BR,BL. Measure the
   physical document with a ruler for `physicalWidthMm`/`physicalHeightMm`.
5. **Transcribe `truth.txt`.** The document's machine-readable text, top to
   bottom. Skip logos/handwriting. This is the CER ground truth — accuracy
   here matters more than coverage; omit lines you cannot read.
6. **Validate:** `dart tools/bench/validate_corpus.dart` must exit 0.
7. Commit through Git LFS (`git lfs install` once; `.gitattributes` already
   routes `bench/corpus/**/*.png`).

After the corpus lands, pin Scanbot's reference numbers once:

    dart tools/bench/run_bench.dart --suite all
    dart tools/bench/run_bench.dart --suite all --pin scanbot

and commit `tools/bench/baselines/scanbot.json`.
```

- [ ] **Step 2: Write the bench README**

Create `tools/bench/README.md`:

```markdown
# tools/bench — DSQ quality bench

The DSQ scoreboard: detection quality (quad IoU, detect rate, false
positives) and output quality (sharpness, illumination uniformity,
effective DPI, OCR CER) over the labeled corpus in `bench/corpus/`,
side-by-side with Scanbot reference outputs.

Design: `docs/superpowers/specs/2026-07-16-doc-scan-quality-design.md` (DSQ0).
Sibling harness for perf (latency) gating: `tools/perfgate/`.

## Run

```sh
cd tools/bench && dart pub get && cd ../..
dart tools/bench/run_bench.dart                  # full suite
dart tools/bench/run_bench.dart --suite detect   # detection only
dart tools/bench/run_bench.dart --skip-ocr       # no Vision CER lane
dart tools/bench/run_bench.dart --gate prev      # exit 1 on >2% regression
dart tools/bench/run_bench.dart --pin prev       # snapshot current numbers
```

Report: `tools/bench/report/bench_report.md` (+ `.json`, + rectified pages
under `report/pages/`). OCR needs macOS (Vision.framework); elsewhere the
CER lane is skipped automatically.

## Pieces

| Path | What |
|---|---|
| `lib/corpus.dart` | Scene schema + validator (`validate_corpus.dart` CLI) |
| `lib/quad_iou.dart` | Convex quad IoU |
| `lib/metrics.dart` | Sharpness / uniformity / DPI / CER |
| `lib/report.dart` | Aggregation, markdown scoreboard, ±2% gate |
| `run_bench.dart` | Driver: build tools, replay corpus, write report |
| `gen_seed_corpus.dart` | Regenerates the synthetic `seed-*` scenes |
| `ocr/vision_ocr.swift` | macOS Vision OCR CLI |
| `native/bench/bench_detect.cpp` | Host harness → classical detector |
| `native/bench/bench_pipeline.cpp` | Host harness → warp + enhance replay |

Pixel data reaches native code via raw temp files + argv — never dart:ffi
(`native/include/supy_scanner_core.h` boundary contract).

## CI

`dsq-bench` job in `.github/workflows/ci.yml` (macos-14): unit tests +
full host replay on the corpus, report uploaded as artifact. Non-blocking
until the real corpus and baselines land.
```

- [ ] **Step 3: Add the DSQ section to TODO.md**

Append to `TODO.md` (adjacent to the existing sprint sections; keep the file's existing checkbox style):

```markdown
## DSQ — Document Scan Quality program (spec: docs/superpowers/specs/2026-07-16-doc-scan-quality-design.md)

### DSQ0 — bench harness + corpus (plan: docs/superpowers/plans/2026-07-16-dsq0-bench-harness.md)
- [x] DSQ0-01 corpus schema, LFS rules, loader/validator (`tools/bench/lib/corpus.dart`)
- [x] DSQ0-02 quad IoU (`tools/bench/lib/quad_iou.dart`)
- [x] DSQ0-03 output metrics: sharpness/uniformity/DPI/CER (`tools/bench/lib/metrics.dart`)
- [x] DSQ0-04 synthetic seed corpus ×6 (`tools/bench/gen_seed_corpus.dart`)
- [x] DSQ0-05 bench_detect host harness (`native/bench/bench_detect.cpp`)
- [x] DSQ0-06 bench_pipeline host harness (`native/bench/bench_pipeline.cpp`)
- [x] DSQ0-07 Vision OCR CLI (`tools/bench/ocr/vision_ocr.swift`)
- [x] DSQ0-08 aggregation + report + ±2% gate (`tools/bench/lib/report.dart`)
- [x] DSQ0-09 run_bench driver (`tools/bench/run_bench.dart`)
- [x] DSQ0-10 dsq-bench CI job (macos-14, non-blocking until baselines pin)
- [ ] DSQ0-11 real corpus ~120 scenes + Scanbot outputs (USER-OWNED, see bench/corpus/CAPTURE_GUIDE.md)
- [ ] DSQ0-12 pin scanbot.json baseline after DSQ0-11

### DSQ1–DSQ4
Planned per-phase; each phase gets its own implementation plan once the
previous phase's bench results are in. DSQ1 requires a TODO decisions-log
entry for the embedded-iOS `enhanceMode` default flip (spec §DSQ1).
```

Check the boxes DSQ0-01…10 only if the corresponding tasks actually landed; when executing this plan task-by-task, add this section in Task 11 with the then-true states.

- [ ] **Step 4: Final full-suite verification**

Run:
```bash
cd tools/bench && dart test && cd ../..
dart tools/bench/run_bench.dart --suite all
```
Expected: all unit tests pass; full bench runs clean on the seed corpus and refreshes `tools/bench/report/bench_report.md`.

- [ ] **Step 5: Commit**

```bash
git add bench/corpus/CAPTURE_GUIDE.md tools/bench/README.md TODO.md
git commit -m "docs: DSQ0 capture guide, bench README, TODO program tickets"
```

---

## Spec coverage map (self-review)

| Spec DSQ0 requirement | Task |
|---|---|
| `bench/corpus/` Git LFS, scene = frame + labeled quad JSON + truth text + Scanbot output | 1 (schema/LFS), 4 (seeds), 11 (capture guide for the real ~120) |
| `tools/bench/` host Dart CLI, perfgate pattern | 9 (driver), 5–6 (C++ harnesses under `SUPY_BUILD_TOOLS`, JSON line protocol) |
| Detection bench: native detector on corpus → IoU, detection rate, per-category, CI | 2 (IoU), 5 (harness), 8 (aggregation incl. per-lighting), 10 (CI) |
| Output bench: OCR CER (macOS Vision Swift CLI), sharpness, illumination uniformity, effective DPI | 3 (metrics), 7 (OCR CLI), 6+9 (host pipeline replay: decode → warp → enhance → encode) |
| `bench_report.md` with deltas vs pinned baselines (Scanbot + previous phase) | 8 (render + gate), 9 (baselines load/pin/gate flags) |
| ±2% regression rule implemented for later phases | 8 (`gate`, direction-aware) |
| Scanbot baseline capture = user-owned manual work | 11 (CAPTURE_GUIDE.md, TODO DSQ0-11/12) |

Known intentional scope choices: device integration runs of the output bench (spec: "full runs on device via integration tests") are deferred to DSQ1, where the first device-visible behavior change lands — DSQ0's CI lane is the host replay mode, which the spec designates as the CI mechanism. Negative seed scenes aren't generated (the `false_positive_rate` path is unit-tested in Task 8; real negatives arrive with the user corpus).
