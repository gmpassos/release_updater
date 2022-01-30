import 'dart:async';

import 'package:collection/collection.dart';

import 'release_updater_base.dart';
import 'release_updater_bundle.dart';
import 'release_updater_utils.dart';

/// A [Release] storage.
abstract class ReleaseStorage implements Copiable<ReleaseStorage> {
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
  FutureOr<Release?> updateTo(ReleaseBundle bundle,
      {bool force = false, bool verbose = false}) async {
    var currentRelease = await this.currentRelease;
    var release = bundle.release;

    if (!force && currentRelease == release) return null;

    var files = await bundle.files;

    if (files.isNotEmpty) {
      if (verbose) {
        print('-- Saving release `$release` files (${files.length}):');
      }

      for (var f in files) {
        var ok = await saveFile(release, f, verbose: verbose);
        if (!ok) {
          throw StateError("Can't save file: $f");
        }
      }
    }

    var ok = await saveRelease(release);
    if (!ok) {
      throw StateError("Can't save release: $release");
    }

    var manifest = await bundle.buildManifest();

    ok = await saveManifest(manifest);
    if (!ok) {
      throw StateError("Can't save manifest!");
    }

    ok = await checkManifest(manifest);
    if (!ok) {
      throw StateError("Error checking Manifest!");
    }

    return release;
  }

  /// Saves a file to this storage implementation.
  FutureOr<bool> saveFile(Release release, ReleaseFile file,
      {bool verbose = false});

  /// Saves the current [release] to this storage implementation.
  FutureOr<bool> saveRelease(Release release);

  /// Checks the [manifest] with the stored files to this storage implementation.
  FutureOr<bool> checkManifest(ReleaseManifest manifest);

  /// Saves the current [manifest] to this storage implementation.
  FutureOr<bool> saveManifest(ReleaseManifest manifest);
}
