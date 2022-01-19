@TestOn('vm')
import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:io';
import 'dart:typed_data';

import 'package:release_updater/release_updater_io.dart';
import 'package:release_updater/src/release_updater_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseUpdater', () {
    test('memory', () async {
      var storage = _MyStorageMemory();
      var provider = _MyProvider('generic');
      await _testUpdater(storage, provider, 'generic');
    });

    test('local', () async {
      var tmp = Directory.systemTemp.createTempSync('release-updater-test--');

      try {
        var storage = ReleaseStorageDirectory('foo', tmp);
        print(storage);

        var provider = _MyProvider(storage.platform!);

        await _testUpdater(storage, provider, storage.platform!);

        expect(storage.currentReleaseDirectory!.path, endsWith('--1.0.3'));
      } finally {
        tmp.deleteSync(recursive: true);
        print('-- Deleted: $tmp');
        if (tmp.existsSync()) {
          print('** Files at: $tmp');
          print(tmp
              .listSync(recursive: true)
              .map((e) => e.path)
              .toList()
              .join('\n'));
        }
      }
    });
  });
}

Future<ReleaseUpdater> _testUpdater(ReleaseStorage storage,
    _MyProvider provider, String currentPlatform) async {
  final pathSeparator = getPathContext().separator;

  var releaseUpdater = ReleaseUpdater(storage, provider);

  {
    var currentRelease = storage.currentRelease;
    expect(currentRelease, isNull);

    var currentReleasePath = storage.currentReleasePath;
    expect(currentReleasePath, isNull);

    var files = await storage.currentFiles;
    expect(files, isEmpty);
  }

  var listReleases = await releaseUpdater.listReleases();
  expect(
      listReleases.map((e) => e.toString()),
      equals([
        'foo/1.0.0/$currentPlatform',
        'foo/1.0.1/$currentPlatform',
        'foo/1.0.2/$currentPlatform',
      ]));

  var lastRelease = await releaseUpdater.checkForUpdate();
  expect(lastRelease.toString(), equals('foo/1.0.2/$currentPlatform'));

  var updatedRelease =
      await releaseUpdater.update(targetVersion: lastRelease!.version);
  print('-- Updated to: $updatedRelease');
  expect(updatedRelease,
      equals(Release('foo', lastRelease.version, platform: currentPlatform)));

  {
    var currentRelease = releaseUpdater.currentRelease;
    expect(currentRelease, equals(Release.parse('foo/1.0.2/$currentPlatform')));

    var currentReleasePath = await releaseUpdater.currentReleasePath;
    expect(currentReleasePath, endsWith('foo--1.0.2'));

    expect(await releaseUpdater.currentReleaseFilePath('README.md'),
        endsWith('foo--1.0.2${pathSeparator}README.md'));

    expect((await storage.currentReleaseFile('README.md'))?.path,
        endsWith('README.md'));

    var files = (await storage.currentFiles).toList();
    files.sort();
    expect(files.length, equals(2));

    var filesPaths = files.map((e) => e.path).toList();

    expect(filesPaths, equals(['README.md', 'hello.txt']));

    expect(
        List.generate(
            filesPaths.length,
            (i) => dart_convert.utf8
                .decode(files[i].data as Uint8List)
                .normalizeToPosixLines()).toList(),
        equals(['#Foo/1.0.2\n\nA Foo project.\n', 'Hello World!']));

    expect(List.generate(files.length, (i) => files[i].length).toList(),
        equals([27, 12]));
  }

  var lastRelease2 = await releaseUpdater.checkForUpdate();
  expect(lastRelease2, isNull);
  {
    var lastVersion2 = await provider.lastRelease('foo');
    expect(lastVersion2.toString(), equals('foo/1.0.2/$currentPlatform'));

    provider._releases.add(Release.parse('foo/1.0.3/$currentPlatform'));

    lastVersion2 = await provider.lastRelease('foo');
    expect(lastVersion2.toString(), equals('foo/1.0.3/$currentPlatform'));
  }

  var lastRelease3 = await releaseUpdater.checkForUpdate();
  expect(lastRelease3.toString(), equals('foo/1.0.3/$currentPlatform'));

  {
    var updatedReleaseError =
        await releaseUpdater.update(platform: 'x', exactPlatform: true);
    expect(updatedReleaseError, isNull);
  }

  var updatedRelease2 = await releaseUpdater.update(
      platform: currentPlatform, exactPlatform: true);
  print('-- Updated to: $updatedRelease2');
  expect(updatedRelease2.toString(), equals('foo/1.0.3/$currentPlatform'));

  {
    var currentRelease = storage.currentRelease;
    expect(currentRelease, equals(Release.parse('foo/1.0.3/$currentPlatform')));

    var currentReleasePath = storage.currentReleasePath;
    expect(currentReleasePath, endsWith('foo--1.0.3'));

    var files = (await storage.currentFiles).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, equals(3));

    var filesPaths = files.map((e) => e.path).toList();

    expect(filesPaths, equals(['README.md', 'hello.txt', 'note.txt']));

    expect(
        List.generate(
            filesPaths.length,
            (i) => dart_convert.utf8
                .decode(files[i].data as Uint8List)
                .normalizeToPosixLines()).toList(),
        equals(
            ['#Foo/1.0.3\n\nA Foo project.\n', 'Hello New World!', 'A note.']));
  }

  return releaseUpdater;
}

class _MyStorageMemory extends ReleaseStorage {
  @override
  final String name = 'foo';

  @override
  Release? currentRelease;

  @override
  _MyStorageMemory copy() => _MyStorageMemory();

  @override
  FutureOr<String?> get currentReleasePath => currentRelease != null
      ? '${currentRelease!.name}--${currentRelease!.version}'
      : null;

  final Map<String, ReleaseFile> _files = <String, ReleaseFile>{};

  @override
  FutureOr<Set<ReleaseFile>> get currentFiles => _files.values.toSet();

  @override
  FutureOr<bool> saveFile(Release release, ReleaseFile file) {
    _files[file.path] = file;
    return true;
  }

  @override
  FutureOr<bool> saveRelease(Release release) {
    currentRelease = release;
    return true;
  }

  @override
  String? get platform => 'generic';
}

class _MyProvider extends ReleaseProvider {
  final String platform;

  late final List<Release> _releases;

  @override
  _MyProvider copy() => _MyProvider(platform);

  _MyProvider(this.platform) {
    _releases = [
      Release.parse('foo/1.0.0/$platform'),
      Release.parse('foo/1.0.1/$platform'),
      Release.parse('foo/1.0.2/$platform'),
    ];
  }

  @override
  FutureOr<List<Release>> listReleases() => _releases.toList();

  @override
  FutureOr<ReleaseBundle?> getReleaseBundle(String name, Version targetVersion,
      [String? platform]) {
    if (name != 'foo' || platform == 'x') return null;

    var ver = targetVersion.toString();

    var release = Release.parse(
        'foo/$ver${platform != null && platform.isNotEmpty ? '/$platform' : ''}');

    switch (ver) {
      case '1.0.2':
        return _MyReleaseBundle(release, {
          ReleaseFile('README.md', '#Foo/$ver\n\nA Foo project.\n'),
          ReleaseFile('hello.txt', 'Hello World!'),
        });
      case '1.0.3':
        return _MyReleaseBundle(release, {
          ReleaseFile('README.md', '#Foo/$ver\n\nA Foo project.\n'),
          ReleaseFile('hello.txt', 'Hello New World!'),
          ReleaseFile('note.txt', 'A note.'),
        });
      default:
        return null;
    }
  }
}

class _MyReleaseBundle extends ReleaseBundle {
  final Set<ReleaseFile> _files;

  _MyReleaseBundle(Release release, this._files) : super(release);

  @override
  FutureOr<Set<ReleaseFile>> get files => _files.toSet();

  @override
  FutureOr<Uint8List> toBytes() {
    throw UnimplementedError();
  }
}
