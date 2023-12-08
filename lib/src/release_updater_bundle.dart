import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ascii_art_tree/ascii_art_tree.dart';
import 'package:base_codecs/base_codecs.dart';
import 'package:collection/collection.dart';
import 'package:data_serializer/data_serializer_io.dart';

import 'release_updater_base.dart';

/// A [Release] bundle of files.
abstract class ReleaseBundle {
  final Release release;

  ReleaseBundle(this.release);

  /// The [ReleaseFile]s of this bundle.
  FutureOr<Set<ReleaseFile>> get files;

  /// Converts this bundle to bytes.
  FutureOr<Uint8List> toBytes();

  /// Returns the MIME-Type of [toBytes].
  String get contentType;

  static const String defaultReleasesBundleFileFormat =
      '%NAME%-%VER%%[-]PLATFORM%.zip';

  static String formatReleaseBundleFile(
      String file, String name, Version version,
      [String? platform]) {
    if (!file.contains('%')) {
      return file;
    }
    file = _replaceMark(file, 'NAME', name);
    file = _replaceMark(file, 'VER', version.toString());
    file = _replaceMark(file, 'PLATFORM', platform);
    return file;
  }

  static String _replaceMark(String s, String mark, String? value) {
    var regExp = RegExp(r'%(?:\[(.*?)\])?(' + mark + r')%');

    return s.replaceAllMapped(regExp, (m) {
      var prev = m.group(1) ?? '';
      return value != null ? '$prev$value' : '';
    });
  }

  /// Builds a [ReleaseManifest] of this bundle.
  Future<ReleaseManifest> buildManifest() async {
    var files = await this.files;

    var manifest = ReleaseManifest(release);

    var manifestFiles =
        await ReleaseManifestFile.toReleaseManifestFileList(files);

    manifest.addFiles(manifestFiles);

    return manifest;
  }

  /// Generates a [ASCIIArtTree] from this [ReleaseBundle] [files].
  Future<ASCIIArtTree> toASCIIArtTree() async {
    var files = await this.files;
    var paths = files.map((f) => f.filePath).toList();
    var asciiArtTree = ASCIIArtTree.fromStringPaths(paths);

    var filesPaths = Map.fromEntries(files.map((f) => MapEntry(f.filePath, f)));

    var filesLengths = <ReleaseFile, int>{};
    for (var f in files) {
      filesLengths[f] = await f.length;
    }

    asciiArtTree.pathInfoProvider = (parents, node, path) {
      var fullPath = [...parents, path].join('/');

      var file = filesPaths[fullPath];
      if (file == null) return null;

      var execStr = file.executable ? ' (EXEC)' : '';
      var fileLength = filesLengths[file];

      var info = '- ($fileLength bytes)$execStr';
      return info;
    };

    return asciiArtTree;
  }
}

/// A [ReleaseBundle] in a Zip format.
class ReleaseBundleZip extends ReleaseBundle {
  static const List<String> defaultExecutableExtensions = ['exe', 'sh'];

  Uint8List? _zipBytes;
  Set<ReleaseFile>? _files;

  final String? rootPath;
  final List<String> executableExtensions;

  ReleaseBundleZip(super.release,
      {Uint8List? zipBytes,
      Iterable<ReleaseFile>? files,
      this.rootPath,
      this.executableExtensions = defaultExecutableExtensions})
      : _zipBytes = zipBytes,
        _files = files?.toSet() {
    if (_files == null && _zipBytes == null) {
      throw ArgumentError(
          "Can't define files! Null `zipBytes` and `files` parameters.");
    }
  }

  static bool isExecutableFilePath(String filePath,
      [List<String>? executableExtensions]) {
    executableExtensions ??= defaultExecutableExtensions;

    return executableExtensions
        .where((ext) => filePath.endsWith('.$ext'))
        .isNotEmpty;
  }

  bool isExecutable(String filePath) =>
      isExecutableFilePath(filePath, executableExtensions);

  @override
  FutureOr<Set<ReleaseFile>> get files {
    if (_files != null) return UnmodifiableSetView(_files!);

    var files = _loadFiles();
    if (files is Set<ReleaseFile>) {
      return UnmodifiableSetView(_files = files);
    } else {
      return files.then((value) => UnmodifiableSetView(_files = value));
    }
  }

  FutureOr<Set<ReleaseFile>> _loadFiles() {
    final archive = ZipDecoder().decodeBytes(_zipBytes!);
    var files = archive.where((f) => f.isFile).map(_toReleaseFile).toSet();

    var manifestJsonFile =
        files.firstWhereOrNull((f) => f.filePath == releaseManifestFilePath);

    if (manifestJsonFile != null) {
      files.remove(manifestJsonFile);

      return manifestJsonFile.dataAsString.then((jsonString) async {
        var json = dart_convert.json.decode(jsonString);

        var manifest = ReleaseManifest.fromJson(json);

        var ok = await manifest.checkBundleFiles(files);
        if (!ok) {
          throw StateError("Manifest check error!");
        }

        return files;
      });
    } else {
      return files;
    }
  }

  ReleaseFile _toReleaseFile(ArchiveFile f) {
    var filePath = f.name;

    var rootPath = this.rootPath;

    if (rootPath != null && filePath.startsWith(rootPath)) {
      filePath = filePath.substring(rootPath.length);
    }

    var executable = f.mode == 755 || isExecutable(filePath);

    var releaseFile = ReleaseFile(filePath, f.content,
        time: DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000),
        executable: executable);

    return releaseFile;
  }

  @override
  String get contentType => 'application/zip';

  @override
  FutureOr<Uint8List> toBytes() => zipBytes;

  FutureOr<Uint8List> get zipBytes {
    if (_zipBytes != null) return _zipBytes!;

    return _buildZipBytes().then((bytes) {
      var bytesView = UnmodifiableUint8ListView(bytes);
      _zipBytes = bytesView;
      return bytesView;
    });
  }

  static const String releaseManifestFilePath = 'release-manifest.json';

  Future<Uint8List> _buildZipBytes() async {
    var files = _files;
    if (files == null) {
      throw StateError("Null files");
    }

    var zipEncoder = ZipEncoder();

    var archive = Archive();

    for (var f in files) {
      var data = await f.data;
      var archiveFile = ArchiveFile(f.filePath, data.length, data);
      archiveFile.mode = f.executable ? 755 : 420;
      archive.addFile(archiveFile);
    }

    {
      var manifest = await buildManifest();
      var jsonBytes = manifest.toJsonEncodedBytes();
      var archiveFile =
          ArchiveFile(releaseManifestFilePath, jsonBytes.length, jsonBytes);
      archive.addFile(archiveFile);
    }

    var bytes = zipEncoder.encode(archive)!;

    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }
}

/// A [ReleaseBundle] manifest.
class ReleaseManifest {
  /// The [Release] of this manifest.
  final Release release;

  /// The [DateTime] of creation of the [ReleaseBundle].
  final DateTime date;

  ReleaseManifest(this.release,
      {Iterable<ReleaseManifestFile>? files, DateTime? date})
      : date = date ?? DateTime.now() {
    if (files != null) {
      addFiles(files);
    }
  }

  final Map<String, ReleaseManifestFile> _files =
      <String, ReleaseManifestFile>{};

  /// The files in this manifest.
  List<ReleaseManifestFile> get files => _files.values.toList();

  /// Returns a [ReleaseManifestFile] with the [filePath];
  ReleaseManifestFile? getFileByPath(String filePath) => _files[filePath];

  /// Adds a [file] to this manifest.
  void addFile(ReleaseManifestFile file) {
    _files[file.filePath] = file;
  }

  /// Add [files] to this manifest.
  void addFiles(Iterable<ReleaseManifestFile> files) {
    for (var f in files) {
      addFile(f);
    }
  }

  Uint8List toJsonEncodedBytes() {
    var bs = dart_convert.utf8.encode(toJsonEncoded()).asUint8List;
    return bs;
  }

  String toJsonEncoded() {
    return dart_convert.JsonEncoder.withIndent('  ').convert(toJson());
  }

  /// This manifest as JSON.
  Map<String, Object> toJson() {
    var entries = _files.values
        .map((e) =>
            MapEntry(e.filePath, {'sha256': e.sha256Hex, 'length': e.length}))
        .toList();

    entries.sort((a, b) => a.key.compareTo(b.key));

    var filesMap = Map<String, Map<String, Object>>.fromEntries(entries);

    return {
      'release': '$release',
      'name': release.name,
      'version': '${release.version}',
      'platform': '${release.platform}',
      'date:': '${DateTime.now().toUtc()}',
      'files': filesMap,
    };
  }

  factory ReleaseManifest.fromJson(Map<String, Object?> json) {
    var releaseStr = json['release'] as String?;
    var nameStr = json['name'] as String?;
    var versionStr = json['version'] as String?;
    var platformStr = json['platform'] as String?;
    var dateStr = json['date'] as String?;
    var filesMap = json['files'] as Map<String, dynamic>;

    Release release;

    if (releaseStr != null) {
      release = Release.parse(releaseStr);

      nameStr ??= release.name;
      versionStr ??= release.version.toString();
      platformStr ??= release.platform;
    } else {
      releaseStr = '${nameStr!}/${versionStr!}';
      if (platformStr != null) {
        releaseStr += '/$platformStr';
      }

      release = Release.parse(releaseStr);
    }

    if (nameStr != release.name) {
      throw ArgumentError('Invalid JSON. Wrong name and release.name');
    }

    if (versionStr != release.version.toString()) {
      throw ArgumentError('Invalid JSON. Wrong version and release.version');
    }

    if (platformStr != release.platform) {
      throw ArgumentError('Invalid JSON. Wrong platform and release.platform');
    }

    var date = dateStr != null ? DateTime.tryParse(dateStr) : null;

    var files = filesMap.entries.map((e) => ReleaseManifestFile.fromSha256Hex(
        e.key, e.value['length'], e.value['sha256']));

    return ReleaseManifest(release, date: date, files: files);
  }

  /// Checks a [releaseBundle] with this manifest.
  Future<bool> checkBundle(ReleaseBundle releaseBundle) async {
    var bundleFiles = await releaseBundle.files;
    return checkBundleFiles(bundleFiles);
  }

  /// Checks a [bundleFiles] with this manifest.
  Future<bool> checkBundleFiles(Iterable<ReleaseFile> bundleFiles) async {
    var map = Map.fromEntries(bundleFiles.map((e) => MapEntry(e.filePath, e)));

    for (var f in _files.values) {
      var bundleFile = map[f.filePath];
      if (bundleFile == null) return false;

      var ok = await f.checkReleaseFile(bundleFile);
      if (!ok) return false;
    }

    return true;
  }
}

/// A [ReleaseManifest] file.
class ReleaseManifestFile {
  static Future<List<ReleaseManifestFile>> toReleaseManifestFileList(
          Iterable<ReleaseFile> releaseFiles) =>
      Future.wait(releaseFiles.map(
          (f) => Future.sync(() => ReleaseManifestFile.fromReleaseFile(f))));

  /// The file path.
  final String filePath;

  /// The length of the file in bytes.
  final int length;

  /// The SHA-256 of this file.
  final Uint8List sha256;

  ReleaseManifestFile(this.filePath, this.length, Uint8List sha256)
      : sha256 = UnmodifiableUint8ListView(sha256);

  ReleaseManifestFile.fromSha256Hex(String file, int length, String sha256Hex)
      : this(file, length, base16.decode(sha256Hex));

  static FutureOr<ReleaseManifestFile> fromReleaseFile(
      ReleaseFile releaseFile) {
    var sha256 = releaseFile.dataSHA256;
    var length = releaseFile.length;
    if (sha256 is Uint8List && length is int) {
      return ReleaseManifestFile(releaseFile.filePath, length, sha256);
    } else {
      return Future.sync(() => sha256).then((sha256Value) {
        return Future.sync(() => length).then((lengthValue) =>
            ReleaseManifestFile(
                releaseFile.filePath, lengthValue, sha256Value));
      });
    }
  }

  String? _sha256Hex;

  String get sha256Hex => _sha256Hex ??= base16.encode(sha256);

  /// Checks a [bundleFile] with this manifest file.
  Future<bool> checkReleaseFile(ReleaseFile bundleFile) async {
    var length = await bundleFile.length;
    if (length != this.length) return false;

    var dataSHA256 = await bundleFile.dataSHA256;
    return sha256.equals(dataSHA256);
  }
}
