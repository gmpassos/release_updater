import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'release_updater_base.dart';
import 'release_updater_bundle.dart';
import 'release_updater_io.dart';
import 'release_updater_platform.dart';
import 'release_updater_storage.dart';
import 'release_updater_utils.dart';
import 'release_updater_utils_io.dart';

/// A [ReleaseStorage] implementation for a local [Directory].
class ReleaseStorageDirectory extends ReleaseStorage {
  static String normalizeFileName(String name) {
    name = name.trim().replaceAll(RegExp(r'[^\w-.]+'), '_');
    return name;
  }

  @override
  String name;

  /// The storage directory.
  final Directory directory;

  /// If `true` will overwrite files that already exists.
  final bool overwriteFiles;

  final bool selfReleaseDirectory;

  ReleaseStorageDirectory(this.name, this.directory,
      {bool overwriteFiles = true, this.selfReleaseDirectory = false})
      : overwriteFiles = overwriteFiles && !selfReleaseDirectory;

  @override
  ReleaseStorageDirectory copy() => ReleaseStorageDirectory(name, directory);

  @override
  String? get platform {
    var p = ReleasePlatform.platform;
    return p.isNotEmpty ? p : null;
  }

  File get currentReleaseConfigFile => File(
      joinPaths(directory.path, normalizeFileName(name) + '--current.release'));

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
    if (selfReleaseDirectory) {
      return directory;
    }

    String dirName = releasePathName(release);
    return Directory(joinPaths(directory.path, dirName));
  }

  String releasePathName(Release release) {
    return release.name + '--' + normalizeFileName(release.version.toString());
  }

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
  String? get currentReleasePath {
    var currentRelease = this.currentRelease;
    if (currentRelease == null) return null;

    var dir = _releaseDirectoryImpl(currentRelease);
    return dir.path;
  }

  @override
  Set<ReleaseFile> get currentFiles {
    var currentRelease = this.currentRelease;
    if (currentRelease == null) return <ReleaseFile>{};

    var dir = releaseDirectory(currentRelease);
    return directoryReleaseFiles(dir).toSet();
  }

  List<ReleaseFile> directoryReleaseFiles(Directory directory) {
    var dirPath = directory.path;

    return directory
        .listSync(recursive: true)
        .map((f) => File(f.path).toReleaseFile(parentPath: dirPath))
        .toList();
  }

  List<File> directoryFiles(Directory directory) {
    return directory
        .listSync(recursive: true)
        .map((f) => File(f.path))
        .toList();
  }

  static const String _newReleaseSuffix = '.new_release';

  /// Install files with suffix `.new_release`.
  /// Files with `.new_release` are generated when [selfReleaseDirectory]
  /// is enabled.
  List<File> installNewReleaseFiles() {
    var newReleaseFiles = directoryFiles(directory)
        .where((f) => f.path.endsWith(_newReleaseSuffix))
        .toList();

    var movedFiles = <File>[];

    for (var file in newReleaseFiles) {
      var filePath = file.path;
      assert(filePath.endsWith(_newReleaseSuffix));

      var file2 = File(
          filePath.substring(0, filePath.length - _newReleaseSuffix.length));

      var fileMoved = file.renameSync(file2.path);
      movedFiles.add(fileMoved);
    }

    return movedFiles;
  }

  @override
  Future<bool> saveFile(Release release, ReleaseFile file,
      {bool verbose = false}) async {
    var dir = releaseDirectory(release);

    var localFile = file.toFile(parentDirectory: dir);
    localFile.parent.createSync(recursive: true);

    if (!overwriteFiles && localFile.existsSync()) {
      localFile = File(localFile.path + _newReleaseSuffix);
    }

    var data = await file.data;

    localFile.writeAsBytesSync(data);
    localFile.setLastModifiedSync(file.time);

    if (file.executable) {
      setFileExecutablePermission(localFile, true);
    }

    if (verbose) {
      print('  -- ${file.toInfo()} > ${localFile.path}');
    }

    return true;
  }

  void setReleaseFileExecutablePermission(
      Release release, ReleaseFile file, bool executable) {
    var dir = releaseDirectory(release);
    var localFile = file.toFile(parentDirectory: dir);

    setFileExecutablePermission(localFile, executable);
  }

  static void setFileExecutablePermission(File file, bool executable) {
    if (file.path.endsWith('.dart')) return;

    if (Platform.isLinux || Platform.isMacOS) {
      var mode = executable ? '+rx' : '-rx';
      var chmodPath = whichExecutablePath('chmod');
      Process.runSync(chmodPath, [mode, file.path]);
    }
  }

  @override
  FutureOr<bool> isFileEquals(
      Release release, ReleaseFile file, ReleaseManifestFile manifestFile) {
    var dir = releaseDirectory(release);
    if (!dir.existsSync()) return false;

    var localFile = file.toFile(parentDirectory: dir);
    if (!localFile.existsSync()) return false;

    return manifestFile.checkFile(localFile);
  }

  @override
  bool saveRelease(Release release) {
    var file = currentReleaseConfigFile;
    file.writeAsStringSync('$release\n');
    return true;
  }

  @override
  Future<bool> checkManifest(ReleaseManifest manifest,
      {bool verbose = false, bool checkNewReleaseFiles = true}) async {
    var release = manifest.release;
    var dir = releaseDirectory(release);

    if (verbose) {
      print(
          '-- Checking manifest (${manifest.release}) with release at: ${dir.path}');
    }

    if (!dir.existsSync()) {
      print("  ** Can't find release directory: ${dir.path}");
      return false;
    }

    var checkOK = true;

    for (var f in manifest.files) {
      var localFile = File(joinPaths(dir.path, f.filePath));

      bool? ok;

      if (!overwriteFiles && checkNewReleaseFiles) {
        var localFile2 = File(localFile.path + _newReleaseSuffix);
        if (localFile2.existsSync()) {
          ok = await f.checkFile(localFile2);
        }
      }

      ok ??= await f.checkFile(localFile);

      if (!ok) {
        print("  ** Error checking file: ${localFile.path}");
        checkOK = false;
        continue;
      }
    }

    return checkOK;
  }

  File get currentManifestFile =>
      File(joinPaths(directory.path, 'release-manifest.json'));

  @override
  bool saveManifest(ReleaseManifest manifest) {
    var file = currentManifestFile;

    file.writeAsStringSync(manifest.toJsonEncoded());

    return true;
  }

  @override
  FutureOr<ReleaseManifest?> loadManifest() {
    var file = currentManifestFile;
    if (!file.existsSync()) return null;

    try {
      var jsonEncoded = file.readAsStringSync();
      var json = dart_convert.json.decode(jsonEncoded);
      return ReleaseManifest.fromJson(json);
    } catch (e, s) {
      print('** Error loading manifest file: ${file.path}');
      print(e);
      print(s);
      return null;
    }
  }

  @override
  String toString() {
    return 'ReleaseStorageDirectory{$directory}';
  }
}

extension FileStorageExtension on File {
  ReleaseFile toReleaseFile({String? parentPath}) {
    var path = this.path;
    if (parentPath != null && path.startsWith(parentPath)) {
      path = path.substring(parentPath.length);
    }
    var data = FileDataProvider(this);
    var executable =
        hasExecutablePermission || ReleaseBundleZip.isExecutableFilePath(path);

    return ReleaseFile(path, data,
        time: lastModifiedSync(), executable: executable);
  }
}

extension ReleaseFileExtension on ReleaseFile {
  File toFile({Directory? parentDirectory}) {
    var path = joinPaths(parentDirectory?.path, filePath);
    return File(path);
  }
}

class FileDataProvider implements DataProvider {
  final File file;

  FileDataProvider(this.file);

  UnmodifiableUint8ListView? _data;

  @override
  UnmodifiableUint8ListView get() =>
      _data ??= UnmodifiableUint8ListView(file.readAsBytesSync());

  @override
  int get length => file.lengthSync();
}

extension ReleaseManifestFileExtension on ReleaseManifestFile {
  /// Checks a [file] with a manifest file.
  Future<bool> checkFile(File file) async {
    if (!file.existsSync()) return false;

    var length = file.lengthSync();
    if (length != this.length) return false;

    var data = file.readAsBytesSync();
    var dataSHA256 = data.computeSHA256();

    return sha256.equals(dataSHA256);
  }
}
