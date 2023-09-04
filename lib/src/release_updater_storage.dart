import 'dart:async';

import 'package:collection/collection.dart';

import 'release_updater_base.dart';
import 'release_updater_bundle.dart';
import 'release_updater_utils.dart';

/// A [Release] storage.
abstract class ReleaseStorage implements Copiable<ReleaseStorage>, Spawnable {
  @override
  FutureOr<bool> onSpawned() => true;

  /// The name of the stored [Release].
  String get name;

  /// The storage platform name.
  String? get platform;

  /// Returns the current storage [Release].
  FutureOr<Release?> get currentRelease;

  /// Returns the current storage [Release] storage path.
  FutureOr<String?> get currentReleasePath;

  /// Returns a [ReleaseFile.filePath] from [currentFiles] that matches [filePath].
  Future<String?> currentReleaseFilePath(String filePath) async {
    var releasePath = await currentReleasePath;
    if (releasePath == null) return null;

    var releaseFile = await currentReleaseFile(filePath);
    if (releaseFile == null) return null;

    var fullPath = joinPaths(releasePath, releaseFile.filePath);
    return fullPath;
  }

  FutureOr<Set<ReleaseFile>> get currentFiles;

  /// Returns a [ReleaseFile] from [currentFiles] that matches [filePath].
  FutureOr<ReleaseFile?> currentReleaseFile(String filePath) async {
    var files = await currentFiles;
    return files.firstWhereOrNull((e) => e.filePath == filePath);
  }

  /// Updates the current stored version to the [bundle].
  FutureOr<ReleaseUpdateResult?> updateTo(ReleaseBundle bundle,
      {bool force = false, bool verbose = false}) async {
    var currentRelease = await this.currentRelease;
    var release = bundle.release;

    if (!force && currentRelease == release) return null;

    var files = await bundle.files;

    var manifest = await bundle.buildManifest();

    var savedFiles = <ReleaseFile>[];

    if (files.isNotEmpty) {
      if (verbose) {
        print('»  Saving release `$release` files (${files.length}):');
      }

      for (var f in files) {
        var manifestFile = manifest.getFileByPath(f.filePath);

        if (manifestFile != null) {
          var storedFileEquals = await isFileEquals(release, f, manifestFile);
          if (storedFileEquals) {
            if (verbose) {
              print('   »  Skipping unchanged file: ${f.filePath}');
            }
            continue;
          }
        }

        var ok = await saveFile(release, f, verbose: verbose);
        if (!ok) {
          throw StateError("Can't save file: $f");
        }

        savedFiles.add(f);
      }
    }

    var ok = await saveRelease(release);
    if (!ok) {
      throw StateError("Can't save release: $release");
    }

    ok = await saveManifest(manifest);
    if (!ok) {
      throw StateError("Can't save manifest!");
    }

    ok = await checkManifest(manifest, verbose: true);
    if (!ok) {
      throw StateError("Error checking Manifest!");
    }

    var result = ReleaseUpdateResult(release, manifest, savedFiles);
    return result;
  }

  /// Saves a file to this storage implementation.
  FutureOr<bool> saveFile(Release release, ReleaseFile file,
      {bool verbose = false});

  /// Returns `true` if the stored [file] is equals to [manifestFile].
  FutureOr<bool> isFileEquals(
      Release release, ReleaseFile file, ReleaseManifestFile manifestFile);

  /// Saves the current [release] to this storage implementation.
  FutureOr<bool> saveRelease(Release release);

  /// Checks the [manifest] with the stored files to this storage implementation.
  FutureOr<bool> checkManifest(ReleaseManifest manifest,
      {bool verbose = false});

  /// Saves the current [manifest] to this storage implementation.
  FutureOr<bool> saveManifest(ReleaseManifest manifest);

  /// Loads the stored [ReleaseManifest].
  FutureOr<ReleaseManifest?> loadManifest();
}
