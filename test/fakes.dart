import 'dart:async';
import 'dart:typed_data';

import 'package:release_updater/release_updater.dart';

/// A [ReleaseStorage] that keeps everything in memory.
class MemoryStorage extends ReleaseStorage {
  @override
  final String name;

  @override
  final String? platform;

  /// The value returned by [onSpawned].
  final FutureOr<bool> Function()? onSpawnedImpl;

  MemoryStorage({this.name = 'foo', this.platform, this.onSpawnedImpl});

  @override
  FutureOr<bool> onSpawned() =>
      onSpawnedImpl != null ? onSpawnedImpl!() : super.onSpawned();

  @override
  MemoryStorage copy() => MemoryStorage(
    name: name,
    platform: platform,
    onSpawnedImpl: onSpawnedImpl,
  )..files.addAll(files);

  @override
  Release? currentRelease;

  @override
  String? get currentReleasePath => currentRelease != null
      ? '${currentRelease!.name}--${currentRelease!.version}'
      : null;

  final Map<String, ReleaseFile> files = <String, ReleaseFile>{};

  @override
  Set<ReleaseFile> get currentFiles => files.values.toSet();

  @override
  bool saveFile(Release release, ReleaseFile file, {bool verbose = false}) {
    files[file.filePath] = file;
    return true;
  }

  @override
  FutureOr<bool> isFileEquals(
    Release release,
    ReleaseFile file,
    ReleaseManifestFile manifestFile,
  ) {
    var storedFile = files[file.filePath];
    if (storedFile == null) return false;
    return manifestFile.checkReleaseFile(storedFile);
  }

  @override
  bool saveRelease(Release release) {
    currentRelease = release;
    return true;
  }

  ReleaseManifest? manifest;

  @override
  bool saveManifest(ReleaseManifest manifest) {
    this.manifest = manifest;
    return true;
  }

  @override
  ReleaseManifest? loadManifest() => manifest;

  @override
  Future<bool> checkManifest(
    ReleaseManifest manifest, {
    bool verbose = false,
  }) async {
    for (var f in manifest.files) {
      var file = files[f.filePath];
      if (file == null) return false;
      if (!await f.checkReleaseFile(file)) return false;
    }
    return true;
  }
}

/// A [ReleaseProvider] backed by in-memory bundles.
class MemoryProvider extends ReleaseProvider {
  final List<Release> releases;

  final Map<String, Set<ReleaseFile>> bundles;

  /// The value returned by [onSpawned].
  final FutureOr<bool> Function()? onSpawnedImpl;

  MemoryProvider({
    List<Release>? releases,
    Map<String, Set<ReleaseFile>>? bundles,
    this.onSpawnedImpl,
  }) : releases = releases ?? <Release>[],
       bundles = bundles ?? <String, Set<ReleaseFile>>{};

  @override
  FutureOr<bool> onSpawned() =>
      onSpawnedImpl != null ? onSpawnedImpl!() : super.onSpawned();

  @override
  MemoryProvider copy() => MemoryProvider(
    releases: releases.toList(),
    bundles: bundles,
    onSpawnedImpl: onSpawnedImpl,
  );

  @override
  List<Release> listReleases() => releases.toList();

  @override
  ReleaseBundle? getReleaseBundle(
    String name,
    Version targetVersion, [
    String? platform,
  ]) {
    var files = bundles['$targetVersion'];
    if (files == null) return null;

    var release = Release(name, targetVersion, platform: platform);
    return MemoryReleaseBundle(release, files);
  }
}

/// A simple in-memory [ReleaseBundle].
class MemoryReleaseBundle extends ReleaseBundle {
  final Set<ReleaseFile> _files;

  MemoryReleaseBundle(super.release, this._files);

  @override
  Set<ReleaseFile> get files => _files.toSet();

  @override
  String get contentType => 'application/octet-stream';

  @override
  Uint8List toBytes() => throw UnimplementedError();
}

/// A [DataProvider] that resolves its data asynchronously.
class AsyncDataProvider implements DataProvider {
  final Uint8List bytes;

  AsyncDataProvider(List<int> bytes) : bytes = Uint8List.fromList(bytes);

  @override
  Future<Uint8List> get() async => bytes;

  @override
  Future<int> get length async => bytes.length;
}
