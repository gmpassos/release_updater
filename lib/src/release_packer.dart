import 'dart:convert' as dart_convert;
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as pack_path;
import 'release_updater_io.dart';
import 'package:yaml/yaml.dart';

import 'release_updater_base.dart';
import 'release_updater_bundle.dart';
import 'release_updater_config.dart';

class ReleasePacker {
  final String name;
  final Version version;
  final List<ReleasePackerFile> files;
  final Directory? configDirectory;

  ReleasePacker(this.name, this.version, this.files, {this.configDirectory});

  factory ReleasePacker.fromJson(Map<String, Object?> json,
      {Directory? rootDirectory}) {
    var name = json.get<String>('name') ?? 'app';
    var versionStr = json.get<String>('version');

    if (versionStr == null) {
      var versionFrom = json.get<String>('version_from');
      if (versionFrom != null) {
        var json = _readFilePath(versionFrom, rootDirectory);
        versionStr = json is Map ? json['version'] : null;
      }
    }

    var version = SemanticVersioning.parse(versionStr ?? '0.0.1');

    var files = json.get<List>('files', [])!;

    var releaseFiles = files.map((e) => ReleasePackerFile.fromJson(e)).toList();

    return ReleasePacker(name, version, releaseFiles,
        configDirectory: rootDirectory);
  }

  factory ReleasePacker.fromFilePath(String filePath,
      {Directory? rootDirectory}) {
    var file = _toFile(filePath, rootDirectory);
    return ReleasePacker.fromFile(file, rootDirectory: rootDirectory);
  }

  factory ReleasePacker.fromFile(File file, {Directory? rootDirectory}) {
    var json = _readFile(file);
    return ReleasePacker.fromJson(json,
        rootDirectory: rootDirectory ?? file.parent);
  }

  static File _toFile(String filePath, Directory? rootDirectory) {
    var path = pack_path.isRootRelative(filePath)
        ? filePath
        : pack_path.join((rootDirectory ?? Directory.current).path, filePath);
    return File(path);
  }

  static dynamic _readFilePath(String filePath, Directory? rootDirectory) {
    var file = _toFile(filePath, rootDirectory);
    return _readFile(file);
  }

  static _readFile(File file) {
    if (!file.existsSync()) return null;

    var content = file.readAsStringSync();

    var path = file.path;

    if (path.endsWith('.json')) {
      return dart_convert.json.decode(content);
    } else if (path.endsWith('.yaml') || path.endsWith('.yml')) {
      return loadYaml(content);
    }

    return content;
  }

  List<ReleasePackerFile> getFiles({String? platform}) {
    Iterable<ReleasePackerFile> where = files;
    if (platform != null) {
      where = where.where((e) => e.matchesPlatform(platform));
    }
    return where.toList();
  }

  ReleasePackerFile? getFile(String filePath, {String? platform}) {
    var where = files.where((e) => e.sourcePath == filePath);
    if (platform != null) {
      where = where.where((e) => e.matchesPlatform(platform));
    }
    return where.firstOrNull;
  }

  ReleasePackerFile? getFileMatching(RegExp filePathRegexp) =>
      files.firstWhereOrNull((e) => filePathRegexp.hasMatch(e.sourcePath));

  ReleaseBundleZip buildFromDirectory(
      {Directory? rootDirectory, String? sourcePath, String? platform}) {
    var configDirectory = this.configDirectory;

    if (rootDirectory == null) {
      if (sourcePath != null) {
        if (pack_path.isRootRelative(sourcePath)) {
          rootDirectory = Directory(sourcePath);
        } else if (configDirectory != null) {
          rootDirectory =
              Directory(pack_path.join(configDirectory.path, sourcePath));
        } else {
          rootDirectory = Directory(sourcePath);
        }
      } else if (configDirectory != null) {
        rootDirectory = configDirectory;
      }
    }

    if (rootDirectory == null) {
      throw ArgumentError("Can't define `rootDirectory`!");
    }

    for (var f in getFiles(platform: platform)
        .where((e) => e.dartCompileExe != null)) {
      _dartCompileExe(rootDirectory, f.dartCompileExe!);
    }

    var files = rootDirectory.listSync(recursive: true);

    var rootPath = rootDirectory.path;

    var list = files
        .map((e) {
          var sourcePath = e.path;
          if (sourcePath.startsWith(rootPath)) {
            sourcePath = sourcePath.substring(rootPath.length);
          }

          sourcePath = ReleaseFile.normalizePath(sourcePath);

          var packFile = getFile(sourcePath, platform: platform);
          if (packFile == null) {
            return null;
          }

          var file = File(e.path);

          var destinyPath = packFile.destinyPath;
          var data = file.readAsBytesSync();
          var time = file.lastModifiedSync();
          var exec = ReleaseBundleZip.isExecutableFilePath(destinyPath);

          return ReleaseFile(destinyPath, data, time: time, executable: exec);
        })
        .whereType<ReleaseFile>()
        .toList();

    var release = Release(name, version, platform: platform);
    return ReleaseBundleZip(release, files: list);
  }

  @override
  String toString() {
    return 'ReleasePacker{name: $name, version: $version, files: ${files.length}';
  }

  Future<bool> _dartCompileExe(
      Directory rootDirectory, String dartScript) async {
    print('-- Dart compile exe: ${rootDirectory.path} -> $dartScript');

    var dartPath = whichExecutablePath('dart');

    var result = Process.runSync(dartPath, ['compile', 'exe', dartScript],
        workingDirectory: rootDirectory.path);

    var ok = result.exitCode == 0;

    if (!ok) {
      print('** Error compiling: $dartScript');
    }

    return ok;
  }
}

class ReleasePackerFile {
  String sourcePath;

  String destinyPath;

  List<RegExp> platforms;

  String? dartCompileExe;

  ReleasePackerFile(this.sourcePath, String destinyPath,
      {Object? platform, this.dartCompileExe})
      : destinyPath = destinyPath == '.' ? sourcePath : destinyPath,
        platforms = platform == null
            ? <RegExp>[]
            : (platform is List
                ? platform.where((e) => e != null).map(_toRegExp).toList()
                : <RegExp>[_toRegExp(platform)]);

  static RegExp _toRegExp(e) => e is RegExp ? e : RegExp('$e');

  factory ReleasePackerFile.fromJson(Object json) {
    if (json is String) {
      return ReleasePackerFile(json, json);
    } else if (json is Map) {
      var platform = json['platform'];
      var dartCompileExe = json['dart_compile_exe'];
      var entry = json.entries
          .where((e) => e.key != 'platform' && e.key != 'dart_compile_exe')
          .first;
      return ReleasePackerFile(entry.key, entry.value,
          platform: platform, dartCompileExe: dartCompileExe);
    } else {
      throw ArgumentError("Unknown type: $json");
    }
  }

  bool matchesPlatform(String? platform) {
    if (platforms.isEmpty || platform == null || platform.isEmpty) return true;
    platform = platform.trim();

    for (var re in platforms) {
      if (re.hasMatch(platform)) return true;
    }

    return false;
  }

  @override
  String toString() {
    return 'ReleasePackerFile{path: $sourcePath -> $destinyPath, platform: $platforms}';
  }
}
