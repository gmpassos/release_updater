import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:release_updater/src/release_updater_utils.dart';

import 'release_updater_base.dart';
import 'release_updater_io.dart';
import 'release_updater_platform.dart';
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

  File get currentReleaseConfigFile =>
      File(joinPaths(directory.path, 'current.release'));

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
    String dirName = releasePathName(release);
    return Directory(joinPaths(directory.path, dirName));
  }

  String releasePathName(Release release) =>
      release.name + '--' + normalizeFileName(release.version.toString());

  @override
  Release? get currentRelease {
    var file = currentReleaseConfigFile;
    if (!file.existsSync()) return null;

    try {
      var data = file.readAsStringSync();
      if (data.isEmpty) return null;

      var release = Release.parse(data);

      var releaseDir = releaseDirectory(release);
      return releaseDir.existsSync() ? release : null;
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
    var pathName = releasePathName(currentRelease);
    var fullPath = joinPaths(directory.path, pathName);
    return fullPath;
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

    if (file.executable) {
      _setFileExecutablePermissionImpl(localFile, true);
    }

    return true;
  }

  void setFileExecutablePermission(
      Release release, ReleaseFile file, bool executable) {
    var dir = releaseDirectory(release);
    var localFile = file.toFile(parentDirectory: dir);

    _setFileExecutablePermissionImpl(localFile, executable);
  }

  void _setFileExecutablePermissionImpl(File file, bool executable) {
    if (Platform.isLinux || Platform.isMacOS) {
      var mode = executable ? '+rx' : '-rx';
      var chmodPath = whichExecutablePath('chmod');
      Process.runSync(chmodPath, [mode, file.path]);
    }
  }

  @override
  bool saveRelease(Release release) {
    var file = currentReleaseConfigFile;
    file.writeAsStringSync('$release\n');
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
    var path = joinPaths(parentDirectory?.path, this.path);
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
