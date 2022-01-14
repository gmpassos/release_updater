import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as pack_path;
import 'package:release_updater/src/release_updater_platform.dart';

import 'release_updater_base.dart';
import 'release_updater_storage.dart';

class ReleaseStorageDirectory extends ReleaseStorage {
  static String normalizeFileName(String name) {
    name = name.trim().replaceAll(RegExp(r'[^\w-.]+'), '_');
    return name;
  }

  @override
  String name;

  final Directory directory;

  ReleaseStorageDirectory(this.name, this.directory);

  @override
  String? get platform {
    var p = ReleasePlatform.platform;
    return p.isNotEmpty ? p : null;
  }

  File get currentReleaseFile =>
      File(pack_path.join(directory.path, 'current.release'));

  Directory? get currentReleaseDirectory {
    var currentRelease = this.currentRelease;
    if (currentRelease == null) return null;
    return releaseDirectory(currentRelease);
  }

  static final Expando<Directory> _expandoReleaseDirectory =
      Expando<Directory>('releaseDirectory');

  Directory releaseDirectory(Release release) {
    var prev = _expandoReleaseDirectory[release];
    if (prev != null) return prev;

    var dir = _releaseDirectoryImpl(release);
    _expandoReleaseDirectory[release] = dir;
    return dir;
  }

  Directory _releaseDirectoryImpl(Release release) {
    String dirName = releasePath(release);
    return Directory(pack_path.join(directory.path, dirName));
  }

  String releasePath(Release release) =>
      release.name + '--' + normalizeFileName(release.version.toString());

  @override
  Release? get currentRelease {
    var file = currentReleaseFile;
    if (!file.existsSync()) return null;

    try {
      var data = file.readAsStringSync();
      if (data.isEmpty) return null;

      return Release.parse(data);
    } catch (e, s) {
      print(e);
      print(s);
      return null;
    }
  }

  @override
  FutureOr<String?> get currentReleasePath {
    var currentRelease = this.currentRelease;
    if (currentRelease == null) return null;
    return releasePath(currentRelease);
  }

  @override
  Set<ReleaseFile> get currentFiles {
    var currentRelease = this.currentRelease;
    if (currentRelease == null) return <ReleaseFile>{};

    var dir = releaseDirectory(currentRelease);
    return directoryFiles(dir).toSet();
  }

  List<ReleaseFile> directoryFiles(Directory directory) {
    var dirPath = directory.path;

    return directory
        .listSync(recursive: true)
        .map((f) => File(f.path).toReleaseFile(parentPath: dirPath))
        .toList();
  }

  @override
  Future<bool> saveFile(Release release, ReleaseFile file) async {
    var dir = releaseDirectory(release);

    var localFile = file.toFile(parentDirectory: dir);
    localFile.createSync(recursive: true);

    var data = await file.data;

    localFile.writeAsBytesSync(data);
    localFile.setLastModifiedSync(file.time);

    return true;
  }

  @override
  bool saveRelease(Release release) {
    var file = currentReleaseFile;
    file.writeAsStringSync(release.toString());
    return true;
  }

  @override
  String toString() {
    return 'ReleaseStorageDirectory{$directory}';
  }
}

extension FileExtension on File {
  ReleaseFile toReleaseFile({String? parentPath}) {
    var path = this.path;
    if (parentPath != null && path.startsWith(parentPath)) {
      path = path.substring(parentPath.length);
    }
    var data = FileDataProvider(this);
    return ReleaseFile(path, data, time: lastModifiedSync());
  }
}

extension ReleaseFileExtension on ReleaseFile {
  File toFile({Directory? parentDirectory}) {
    var path = this.path;
    if (parentDirectory != null) {
      path = pack_path.join(parentDirectory.path, path);
    }
    return File(path);
  }
}

class FileDataProvider implements DataProvider {
  final File file;

  FileDataProvider(this.file);

  @override
  Uint8List get() => file.readAsBytesSync();

  @override
  int get length => file.lengthSync();
}
