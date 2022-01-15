import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'release_updater_base.dart';

abstract class ReleaseBundle {
  final Release release;

  ReleaseBundle(this.release);

  FutureOr<Set<ReleaseFile>> get files;
}

class ReleaseBundleZip extends ReleaseBundle {
  static const List<String> defaultExecutableExtensions = ['exe', 'sh'];

  Uint8List? _zipBytes;
  Set<ReleaseFile>? _files;

  final String? rootPath;
  final List<String> executableExtensions;

  ReleaseBundleZip(Release release,
      {Uint8List? zipBytes,
      Iterable<ReleaseFile>? files,
      this.rootPath,
      this.executableExtensions = defaultExecutableExtensions})
      : _zipBytes = zipBytes,
        _files = files?.toSet(),
        super(release) {
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
  FutureOr<Set<ReleaseFile>> get files => _files ??= _loadFiles();

  Set<ReleaseFile> _loadFiles() {
    final archive = ZipDecoder().decodeBytes(_zipBytes!);
    var files = archive.where((f) => f.isFile).map(_toReleaseFile).toSet();
    return files;
  }

  ReleaseFile _toReleaseFile(ArchiveFile f) {
    var filePath = f.name;

    var rootPath = this.rootPath;

    if (rootPath != null && filePath.startsWith(rootPath)) {
      filePath = filePath.substring(rootPath.length);
    }

    var executable = isExecutable(filePath);

    var releaseFile = ReleaseFile(filePath, f.content,
        time: DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000),
        executable: executable);

    return releaseFile;
  }

  FutureOr<Uint8List> get zipBytes async {
    if (_zipBytes != null) return _zipBytes!;
    var bytes = _zipBytes = await _buildZipBytes();
    return bytes;
  }

  Future<Uint8List> _buildZipBytes() async {
    var files = _files;
    if (files == null) {
      throw StateError("Null files");
    }

    var zipEncoder = ZipEncoder();

    var archive = Archive();

    for (var f in files) {
      var data = await f.data;
      var archiveFile = ArchiveFile(f.path, data.length, data);
      archive.addFile(archiveFile);
    }

    var bytes = zipEncoder.encode(archive)!;

    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }
}
