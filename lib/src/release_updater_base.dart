import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:typed_data';

import 'package:pub_semver/pub_semver.dart' as semver;

import 'release_updater_provider.dart';
import 'release_updater_storage.dart';
import 'release_updater_utils.dart';

abstract class Copiable<T> {
  /// Returns a copy of this instance.
  /// - Fresh instances should be prepared to be sent through `Isolate`s.
  T copy();
}

typedef OnRelease = void Function(Release release);

/// A [Release] updater from [releaseProvider] to [storage].
class ReleaseUpdater implements Copiable<ReleaseUpdater> {
  // ignore: constant_identifier_names
  static const String VERSION = '1.0.19';

  /// The [Release] storage.
  final ReleaseStorage storage;

  /// The [Release] provider.
  final ReleaseProvider releaseProvider;

  ReleaseUpdater(this.storage, this.releaseProvider);

  @override
  ReleaseUpdater copy() =>
      ReleaseUpdater(storage.copy(), releaseProvider.copy());

  String get name => storage.name;

  String? get platform => storage.platform;

  /// Checks if there's a new version to update and returns it, otherwise returns `null`.
  ///
  /// - [onNewRelease] is called when a new release is available.
  FutureOr<Release?> checkForUpdate(
      {OnRelease? onNewRelease, Release? currentRelease}) async {
    final realCurrentRelease = await this.currentRelease;

    if (currentRelease == null) {
      currentRelease = realCurrentRelease;
    } else if (realCurrentRelease == null ||
        currentRelease.compareTo(realCurrentRelease) > 0) {
      currentRelease = realCurrentRelease;
    }

    var lastRelease = await this.lastRelease;
    if (lastRelease == null) return null;

    var newRelease =
        currentRelease == null || lastRelease.compareTo(currentRelease) > 0;

    if (newRelease) {
      if (onNewRelease != null) {
        try {
          onNewRelease(lastRelease);
        } catch (e, s) {
          print(e);
          print(s);
        }
      }

      return lastRelease;
    } else {
      return null;
    }
  }

  /// Starts a [Timer] with a periodic call to [checkForUpdate].
  ///
  /// - [onNewRelease] is called when a new release is available.
  /// - [interval] is the [Timer] interval. Default: 1min.
  Timer startPeriodicUpdateChecker(OnRelease onNewRelease,
      {Duration? interval, Release? currentRelease}) {
    interval ??= Duration(minutes: 1);

    return Timer.periodic(interval, (_) async {
      var newRelease = await checkForUpdate(
          onNewRelease: onNewRelease, currentRelease: currentRelease);
      if (newRelease != null) {
        currentRelease = newRelease;
      }
    });
  }

  /// Returns the current [Release].
  FutureOr<Release?> get currentRelease => storage.currentRelease;

  /// Returns the current [Release] [storage] path.
  FutureOr<String?> get currentReleasePath => storage.currentReleasePath;

  /// Returns the current [ReleaseFile] [storage] path.
  Future<String?> currentReleaseFilePath(String filePath) =>
      storage.currentReleaseFilePath(filePath);

  /// Returns the last [Release] available for [name] and [platform].
  FutureOr<Release?> get lastRelease =>
      releaseProvider.lastRelease(name, platform: platform);

  /// List the releases from [releaseProvider].
  FutureOr<List<Release>> listReleases() => releaseProvider.listReleases();

  /// Updates the release at [storage].
  ///
  /// - [targetRelease] is the desired [Release] to update to.
  /// - [targetVersion] is the desired [Version] for the release.
  /// - [platform] is the desired platform of the available [Release].
  /// - [exactPlatform] when `true` ensures that the update is for the exact [platform] parameter.
  /// - [force] when `true` performs the update even when already updated to the [targetRelease] and [targetVersion].
  FutureOr<Release?> update(
      {Release? targetRelease,
      Version? targetVersion,
      String? platform,
      bool exactPlatform = false,
      bool force = false}) async {
    Release? lastRelease;

    if (targetVersion == null) {
      var release = targetRelease;
      release ??= lastRelease ??= await this.lastRelease;
      if (release == null) return null;
      targetVersion = release.version;
    }

    platform ??= targetRelease?.platform ?? storage.platform;

    if (!force) {
      var currentRelease = await storage.currentRelease;
      if (currentRelease != null &&
          currentRelease.name == name &&
          currentRelease.version == targetVersion) {
        if (platform == null ||
            currentRelease.platform == null ||
            currentRelease.platform == platform) {
          return null;
        }
      }
    }

    var releaseBundle =
        await releaseProvider.getReleaseBundle(name, targetVersion, platform);

    if (releaseBundle == null && !exactPlatform) {
      releaseBundle =
          await releaseProvider.getReleaseBundle(name, targetVersion);
    }

    if (releaseBundle == null) return null;

    return storage.updateTo(releaseBundle, force: force);
  }

  @override
  String toString() {
    return 'ReleaseUpdater{storage: $storage, releaseProvider: $releaseProvider}';
  }
}

/// A release an its information.
class Release implements Comparable<Release> {
  static String normalizeName(String name) {
    name = name.trim().replaceAll(RegExp(r'[^\w-.]+'), '_').trim();
    return name;
  }

  static String? normalizePlatform(String? platform) {
    if (platform == null) return null;
    platform = normalizeName(platform);
    return platform.isEmpty ? null : platform;
  }

  /// The name of the release.
  final String name;

  /// The [Version] of this release.
  final Version version;

  final String? platform;

  Release(String name, this.version, {String? platform})
      : name = normalizeName(name),
        platform = normalizePlatform(platform);

  factory Release.parse(String s) {
    var parts = s.trim().split('/');
    var name = parts[0].trim();
    var ver = parts[1].trim();
    var platform = parts.length > 2 ? parts[2] : null;
    return Release(name, SemanticVersioning.parse(ver),
        platform: platform?.trim());
  }

  @override
  int compareTo(Release other) {
    var cmp = name.compareTo(other.name);
    if (cmp == 0) {
      cmp = version.compareTo(other.version);
    }
    return cmp;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Release &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          version == other.version &&
          platform == other.platform;

  @override
  int get hashCode =>
      name.hashCode ^ version.hashCode ^ (platform?.hashCode ?? 0);

  /// Returns this release as a compatible file name.
  String get asFileName {
    var platformStr = platform ?? '';
    if (platformStr.isNotEmpty) {
      platformStr = '-$platformStr';
    }
    var path = '$name-$version$platformStr';
    path = path.replaceAll(RegExp(r'[^\w\.-]+'), '');
    return path;
  }

  @override
  String toString() {
    var platformStr = platform ?? '';
    if (platformStr.isNotEmpty) {
      platformStr = '/$platformStr';
    }
    return '$name/$version$platformStr';
  }
}

/// A version of a [Release].
abstract class Version implements Comparable<Version> {
  @override
  String toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Version &&
          runtimeType == other.runtimeType &&
          compareTo(other) == 0;

  @override
  int get hashCode => toString().hashCode;
}

class SemanticVersioning extends Version {
  final semver.Version _semver;

  SemanticVersioning._(this._semver);

  SemanticVersioning.parse(String version)
      : this._(semver.Version.parse(version));

  @override
  int compareTo(Version other) {
    if (other is SemanticVersioning) {
      return _semver.compareTo(other._semver);
    } else {
      var otherSemver = semver.Version.parse(other.toString());
      return _semver.compareTo(otherSemver);
    }
  }

  @override
  String toString() => _semver.toString();
}

abstract class DataProvider {
  FutureOr<Uint8List> get();

  FutureOr<int> get length;
}

class ReleaseFile implements Comparable<ReleaseFile> {
  static String normalizePath(String path) {
    path = path.trim();

    var path2 = normalizePlatformPath(path, asPosix: true);
    var parts = splitPathRootPrefix(path2, asPosix: true);

    var path3 = parts[1];

    if (startsWithDriver(path3)) {
      throw StateError("Can't normalize path: $path -> $path3");
    }

    while (startsWithGenericPathSeparator(path3)) {
      path3 = path3.substring(1);
    }

    if (path3.isEmpty) {
      throw StateError("Can't normalize path: $path");
    }

    return path3;
  }

  final String path;

  final Object? _data;

  final DateTime time;

  final bool executable;

  final bool compressed;

  ReleaseFile(String path, Object data,
      {DateTime? time, this.executable = false, this.compressed = false})
      : path = normalizePath(path),
        _data = toBytes(data),
        time = time ?? DateTime.now();

  static Object toBytes(Object data) {
    if (data is DataProvider) return data;
    if (data is Uint8List) return data;

    if (data is Iterable<int>) return Uint8List.fromList(data.toList());

    var s = data.toString();
    var encoded = dart_convert.utf8.encode(s);
    return encoded is Uint8List ? encoded : Uint8List.fromList(encoded);
  }

  FutureOr<int> get length {
    var data = _data;
    if (data is Uint8List) {
      return data.length;
    } else if (data is DataProvider) {
      return data.length;
    }

    throw StateError('Unknown data type: $data');
  }

  FutureOr<Uint8List> get data {
    var data = _data;
    if (data is Uint8List) {
      return data;
    } else if (data is DataProvider) {
      return data.get();
    }

    throw StateError('Unknown data type: $data');
  }

  Future<String> get dataAsString async {
    var bytes = await data;
    return dart_convert.utf8.decode(bytes);
  }

  @override
  String toString() {
    return 'ReleaseFile{path: $path, length: $length, time: $time, executable: $executable, compressed: $compressed}';
  }

  @override
  int compareTo(ReleaseFile other) => path.compareTo(other.path);
}
