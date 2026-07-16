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
