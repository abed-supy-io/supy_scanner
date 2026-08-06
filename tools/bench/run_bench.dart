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
import 'lib/harness_io.dart';
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

/// Starts [exe], converting a failure to even launch the process (missing
/// binary, not on PATH, etc.) into a [HarnessException] instead of letting
/// the raw [ProcessException] escape as an uncaught error.
Future<Process> _startProcess(String exe, List<String> args,
    {String? workingDirectory, ProcessStartMode mode = ProcessStartMode.normal}) async {
  try {
    return await Process.start(exe, args,
        workingDirectory: workingDirectory, mode: mode);
  } on ProcessException catch (e) {
    throw HarnessException('[bench] failed to launch $exe: ${e.message}');
  }
}

/// Runs [exe] to completion, converting a launch failure into a
/// [HarnessException] (see [_startProcess]).
Future<ProcessResult> _runProcess(String exe, List<String> args,
    {String? workingDirectory}) async {
  try {
    return await Process.run(exe, args, workingDirectory: workingDirectory);
  } on ProcessException catch (e) {
    throw HarnessException('[bench] failed to launch $exe: ${e.message}');
  }
}

Future<void> _buildTools(String root, {required bool ocr}) async {
  Future<void> run(String exe, List<String> cmd) async {
    stdout.writeln('[bench] $exe ${cmd.join(' ')}');
    final proc = await _startProcess(exe, cmd, workingDirectory: root,
        mode: ProcessStartMode.inheritStdio);
    if (await proc.exitCode != 0) {
      throw HarnessException('[bench] $exe failed');
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
    final result = await _runProcess('$root/$_buildDir/bench_detect', [
      '--gray', grayPath,
      '--width', '${frame.width}',
      '--height', '${frame.height}',
    ]);
    if (result.exitCode != 0) {
      throw HarnessException('[bench] bench_detect failed on $sceneId:\n'
          '${result.stderr}');
    }
    final json = parseJsonLine(result.stdout as String, 'DSQ_DETECT');
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
    final result = await _runProcess('$root/$_buildDir/bench_pipeline', [
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
    final info = parseJsonLine(result.stdout as String, 'DSQ_PIPELINE');
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
    final ProcessResult result;
    try {
      result = await Process.run(bin.path, [imagePath]);
    } on ProcessException catch (e) {
      stderr.writeln('[bench] vision_ocr failed to launch: ${e.message}');
      return null;
    }
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

/// Entry point. Delegates to [_runBench] and enforces the driver's
/// exit-code contract (0 clean, 1 gate regression, 2 harness/infra error)
/// at a single point: any [HarnessException] — or a raw [ProcessException]
/// / [FormatException] that still escapes a call site we didn't wrap —
/// is reported to stderr and mapped to exit 2 instead of a raw stack
/// trace + exit 255.
Future<void> main(List<String> argv) async {
  try {
    await _runBench(argv);
  } on HarnessException catch (e) {
    stderr.writeln(e.message);
    exit(2);
  } on ProcessException catch (e) {
    stderr.writeln('[bench] process error: ${e.message}');
    exit(2);
  } on FileSystemException catch (e) {
    stderr.writeln('[bench] filesystem error: ${e.message}');
    exit(2);
  } on FormatException catch (e) {
    stderr.writeln('[bench] malformed data: $e');
    exit(2);
  }
}

Future<void> _runBench(List<String> argv) async {
  final args = _parseArgs(argv);
  final suite = args['suite'] ?? 'all';
  if (!{'all', 'detect', 'output'}.contains(suite)) {
    stderr.writeln('[bench] --suite must be all|detect|output');
    exit(2);
  }
  final root = _repoRoot().path;
  final corpusDir = Directory('$root/${args['corpus'] ?? 'bench/corpus'}');
  if (!corpusDir.existsSync()) {
    stderr.writeln('[bench] no corpus at ${corpusDir.path}');
    exit(2);
  }
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
        throw HarnessException(
            '[bench] cannot decode ${scene.frameFile.path} — '
            'is Git LFS hydrated? (git lfs pull)');
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
