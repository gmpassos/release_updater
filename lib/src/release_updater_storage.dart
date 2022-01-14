import 'dart:async';

import 'release_updater_base.dart';
import 'release_updater_release_bundle.dart';

/// A [Release] storage.
abstract class ReleaseStorage {
  /// The name of the stored [Release].
  String get name;

  /// The storage platform name.
  String? get platform;

  /// Returns the current storage [Release].
  FutureOr<Release?> get currentRelease;

  /// Returns the current storage [Release] storage path.
  FutureOr<String?> get currentReleasePath;

  FutureOr<Set<ReleaseFile>> get currentFiles;

  /// Updates the current stored version to the [bundle].
  FutureOr<Release?> updateTo(ReleaseBundle bundle,
      {bool force = false}) async {
    var currentRelease = await this.currentRelease;
    var release = bundle.release;

    if (currentRelease == release) return null;

    var files = await bundle.files;

    for (var f in files) {
      var ok = await saveFile(release, f);
      if (!ok) {
        throw StateError("Can't save file: $f");
      }
    }

    var ok = await saveRelease(release);
    if (!ok) {
      throw StateError("Can't save release: $release");
    }

    return release;
  }

  FutureOr<bool> saveFile(Release release, ReleaseFile file);

  FutureOr<bool> saveRelease(Release release);
}
