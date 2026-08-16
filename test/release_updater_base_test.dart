@TestOn('vm')
import 'dart:convert' as dart_convert;
import 'dart:typed_data';

import 'package:release_updater/release_updater.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('Release', () {
    test('parse', () {
      var release = Release.parse('foo/1.0.2/linux-x64');

      expect(release.name, equals('foo'));
      expect(release.version.toString(), equals('1.0.2'));
      expect(release.platform, equals('linux-x64'));
      expect(release.toString(), equals('foo/1.0.2/linux-x64'));
    });

    test('parse (no platform)', () {
      var release = Release.parse(' foo / 1.0.2 ');

      expect(release.name, equals('foo'));
      expect(release.platform, isNull);
      expect(release.toString(), equals('foo/1.0.2'));
    });

    test('parse error', () {
      expect(() => Release.parse('foo'), throwsFormatException);
      expect(() => Release.parse(''), throwsFormatException);
      expect(() => Release.parse('foo/x'), throwsFormatException);
    });

    test('normalizeName', () {
      expect(Release.normalizeName(' foo bar '), equals('foo_bar'));
      expect(Release.normalizeName('foo@1'), equals('foo_1'));
      expect(Release.normalizeName('foo-x.y'), equals('foo-x.y'));
    });

    test('normalizePlatform', () {
      expect(Release.normalizePlatform(null), isNull);
      expect(Release.normalizePlatform(''), isNull);
      expect(Release.normalizePlatform('  '), isNull);
      expect(Release.normalizePlatform('linux x64'), equals('linux_x64'));
    });

    test('asFileName', () {
      expect(
        Release.parse('foo/1.0.2/linux-x64').asFileName,
        equals('foo-1.0.2-linux-x64'),
      );

      expect(Release.parse('foo/1.0.2').asFileName, equals('foo-1.0.2'));
    });

    test('equality and hashCode', () {
      var r1 = Release.parse('foo/1.0.2/linux');
      var r2 = Release.parse('foo/1.0.2/linux');
      var r3 = Release.parse('foo/1.0.2/macos');

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
      expect(r1, isNot(equals(r3)));
      expect(r1, equals(r1));
    });

    test('compareTo', () {
      var r1 = Release.parse('foo/1.0.2');
      var r2 = Release.parse('foo/1.0.10');
      var r3 = Release.parse('bar/2.0.0');

      expect(r1.compareTo(r2), lessThan(0));
      expect(r2.compareTo(r1), greaterThan(0));
      expect(r1.compareTo(r3), greaterThan(0));

      var list = [r2, r3, r1]..sort();
      expect(
        list.map((e) => e.toString()),
        equals(['bar/2.0.0', 'foo/1.0.2', 'foo/1.0.10']),
      );
    });
  });

  group('SemanticVersioning', () {
    test('compareTo', () {
      var v1 = SemanticVersioning.parse('1.0.2');
      var v2 = SemanticVersioning.parse('1.0.3');

      expect(v1.compareTo(v2), lessThan(0));
      expect(v2.compareTo(v1), greaterThan(0));
      expect(v1.compareTo(SemanticVersioning.parse('1.0.2')), equals(0));
    });

    test('compareTo (other Version implementation)', () {
      var v1 = SemanticVersioning.parse('1.0.2');
      var v2 = _StringVersion('1.0.3');

      expect(v1.compareTo(v2), lessThan(0));
      expect(v1.compareTo(_StringVersion('1.0.2')), equals(0));
    });

    test('equality', () {
      expect(
        SemanticVersioning.parse('1.0.2'),
        equals(SemanticVersioning.parse('1.0.2')),
      );

      expect(
        SemanticVersioning.parse('1.0.2').hashCode,
        equals(SemanticVersioning.parse('1.0.2').hashCode),
      );

      expect(
        SemanticVersioning.parse('1.0.2'),
        isNot(equals(SemanticVersioning.parse('1.0.3'))),
      );

      // A different `Version` runtimeType is never equal:
      expect(
        SemanticVersioning.parse('1.0.2'),
        isNot(equals(_StringVersion('1.0.2'))),
      );
    });

    test('parse error', () {
      expect(() => SemanticVersioning.parse('x'), throwsFormatException);
    });
  });

  group('ReleaseFile', () {
    test('normalizePath', () {
      expect(ReleaseFile.normalizePath('/foo/bar.txt'), equals('foo/bar.txt'));
      expect(
        ReleaseFile.normalizePath('\\foo\\bar.txt'),
        equals('foo/bar.txt'),
      );
      expect(ReleaseFile.normalizePath('./foo/bar.txt'), equals('foo/bar.txt'));
      expect(
        ReleaseFile.normalizePath('foo/./x/../bar.txt'),
        equals('foo/bar.txt'),
      );
    });

    test('normalizePath error', () {
      expect(() => ReleaseFile.normalizePath(''), throwsStateError);
      expect(() => ReleaseFile.normalizePath('/'), throwsStateError);
      expect(() => ReleaseFile.normalizePath('.'), throwsStateError);
      expect(() => ReleaseFile.normalizePath('C:\\'), throwsStateError);
    });

    test('normalizePath rejects paths out of the release (`Zip Slip`)', () {
      expect(() => ReleaseFile.normalizePath('..'), throwsStateError);
      expect(() => ReleaseFile.normalizePath('../evil.txt'), throwsStateError);
      expect(
        () => ReleaseFile.normalizePath('../../evil.txt'),
        throwsStateError,
      );
      expect(
        () => ReleaseFile.normalizePath('..\\..\\evil.txt'),
        throwsStateError,
      );
      expect(
        () => ReleaseFile.normalizePath('foo/../../evil.txt'),
        throwsStateError,
      );
      expect(() => ReleaseFile('../../evil.txt', 'data'), throwsStateError);

      // A `..` that does not escape the release directory is fine:
      expect(
        ReleaseFile.normalizePath('foo/bar/../ok.txt'),
        equals('foo/ok.txt'),
      );
    });

    test('data from String', () async {
      var file = ReleaseFile('a.txt', 'Hello!');

      expect(file.filePath, equals('a.txt'));
      expect(file.length, equals(6));
      expect(await file.dataAsString, equals('Hello!'));
      expect(file.executable, isFalse);
      expect(file.compressed, isFalse);
      expect(file.toInfo(), equals('a.txt (6 bytes)'));
      expect(file.toString(), contains('a.txt'));
    });

    test('data from bytes', () async {
      var bytes = Uint8List.fromList([1, 2, 3]);

      var fromUint8List = ReleaseFile('a.bin', bytes);
      expect(await fromUint8List.data, equals([1, 2, 3]));

      var fromList = ReleaseFile('b.bin', <int>[1, 2, 3]);
      expect(await fromList.data, equals([1, 2, 3]));
      expect(fromList.length, equals(3));
    });

    test('data is unmodifiable', () async {
      var file = ReleaseFile('a.bin', <int>[1, 2, 3]);
      var data = await file.data;
      expect(() => data[0] = 10, throwsUnsupportedError);
    });

    test('data from DataProvider', () async {
      var file = ReleaseFile('a.bin', AsyncDataProvider([1, 2, 3, 4]));

      expect(await file.length, equals(4));
      expect(await file.data, equals([1, 2, 3, 4]));
      expect(await file.dataSHA256, hasLength(32));
    });

    test('dataSHA256', () async {
      var file = ReleaseFile('a.txt', 'abc');

      var sha256 = await file.dataSHA256;

      expect(
        sha256,
        equals(
          dart_convert.base64.decode(
            'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qc'
            'tBD/YfIAFa0=',
          ),
        ),
      );

      // Cached (2nd call returns the same instance):
      expect(identical(await file.dataSHA256, sha256), isTrue);
    });

    test('executable and compressed flags', () {
      var file = ReleaseFile(
        'run.sh',
        '#!/bin/sh',
        executable: true,
        compressed: true,
      );

      expect(file.executable, isTrue);
      expect(file.compressed, isTrue);
      expect(file.toInfo(), contains('(EXEC)'));
      expect(file.toInfo(), contains('(COMP)'));
    });

    test('time', () {
      var time = DateTime(2020, 1, 2, 3, 4, 5);
      expect(ReleaseFile('a.txt', 'x', time: time).time, equals(time));

      var now = DateTime.now();
      expect(
        ReleaseFile('a.txt', 'x').time.difference(now).inSeconds.abs(),
        lessThan(10),
      );
    });

    test('compareTo', () {
      var files = [
        ReleaseFile('b.txt', 'b'),
        ReleaseFile('a.txt', 'a'),
        ReleaseFile('c.txt', 'c'),
      ]..sort();

      expect(files.map((e) => e.filePath), equals(['a.txt', 'b.txt', 'c.txt']));
    });
  });

  group('ReleaseUpdater', () {
    test('name, platform and toString', () {
      var updater = ReleaseUpdater(
        MemoryStorage(name: 'foo', platform: 'linux-x64'),
        MemoryProvider(),
      );

      expect(updater.name, equals('foo'));
      expect(updater.platform, equals('linux-x64'));
      expect(updater.toString(), contains('MemoryStorage'));
    });

    test('copy', () {
      var updater = ReleaseUpdater(MemoryStorage(), MemoryProvider());
      var copy = updater.copy();

      expect(copy, isNot(same(updater)));
      expect(copy.storage, isNot(same(updater.storage)));
      expect(copy.releaseProvider, isNot(same(updater.releaseProvider)));
    });

    test('onSpawned (sync)', () {
      var updater = ReleaseUpdater(MemoryStorage(), MemoryProvider());
      expect(updater.onSpawned(), isTrue);
    });

    test('onSpawned (sync `false`)', () {
      var updater = ReleaseUpdater(
        MemoryStorage(onSpawnedImpl: () => false),
        MemoryProvider(),
      );
      expect(updater.onSpawned(), isFalse);
    });

    test('onSpawned (async)', () async {
      var updater = ReleaseUpdater(
        MemoryStorage(onSpawnedImpl: () async => true),
        MemoryProvider(onSpawnedImpl: () async => true),
      );

      expect(await updater.onSpawned(), isTrue);
    });

    test('onSpawned (async `false`)', () async {
      var updater = ReleaseUpdater(
        MemoryStorage(onSpawnedImpl: () async => false),
        MemoryProvider(onSpawnedImpl: () async => true),
      );

      expect(await updater.onSpawned(), isFalse);
    });

    test('onSpawned (error)', () async {
      var updater = ReleaseUpdater(
        MemoryStorage(onSpawnedImpl: () => throw StateError('spawn error')),
        MemoryProvider(onSpawnedImpl: () => true),
      );

      expect(await updater.onSpawned(), isTrue);
    });

    test('checkForUpdate (no releases)', () async {
      var updater = ReleaseUpdater(MemoryStorage(), MemoryProvider());
      expect(await updater.checkForUpdate(), isNull);
    });

    test('checkForUpdate (onNewRelease error is caught)', () async {
      var updater = ReleaseUpdater(
        MemoryStorage(),
        MemoryProvider(releases: [Release.parse('foo/1.0.0')]),
      );

      var release = await updater.checkForUpdate(
        onNewRelease: (r) => throw StateError('callback error'),
      );

      expect(release.toString(), equals('foo/1.0.0'));
    });

    test('update (no release available)', () async {
      var updater = ReleaseUpdater(MemoryStorage(), MemoryProvider());
      expect(await updater.update(), isNull);
    });

    test('update (no bundle for version)', () async {
      var updater = ReleaseUpdater(
        MemoryStorage(),
        MemoryProvider(releases: [Release.parse('foo/1.0.0')]),
      );

      expect(await updater.update(), isNull);
    });

    test('update and re-update', () async {
      var storage = MemoryStorage(name: 'foo');

      var provider = MemoryProvider(
        releases: [Release.parse('foo/1.0.0'), Release.parse('foo/1.0.1')],
        bundles: {
          '1.0.0': {ReleaseFile('a.txt', 'A')},
          '1.0.1': {ReleaseFile('a.txt', 'A'), ReleaseFile('b.txt', 'B')},
        },
      );

      var updater = ReleaseUpdater(storage, provider);

      var result = await updater.update();
      expect(result, isNotNull);
      expect(result!.release.toString(), equals('foo/1.0.1'));
      expect(result.savedFilesLength, equals(2));
      expect(result.hasSavedFiles, isTrue);
      expect(result.manifest.files, hasLength(2));
      expect(result.toString(), contains('savedFiles: 2'));

      // Already updated:
      expect(await updater.update(), isNull);

      // Forced update re-saves nothing (files are unchanged):
      var forced = await updater.update(force: true);
      expect(forced, isNotNull);
      expect(forced!.savedFilesLength, equals(0));
      expect(forced.hasSavedFiles, isFalse);
    });

    test('update (targetRelease)', () async {
      var storage = MemoryStorage(name: 'foo');

      var provider = MemoryProvider(
        releases: [Release.parse('foo/1.0.0'), Release.parse('foo/1.0.1')],
        bundles: {
          '1.0.0': {ReleaseFile('a.txt', 'A')},
        },
      );

      var updater = ReleaseUpdater(storage, provider);

      var result = await updater.update(
        targetRelease: Release.parse('foo/1.0.0'),
      );

      expect(result!.release.toString(), equals('foo/1.0.0'));
      expect(storage.currentRelease.toString(), equals('foo/1.0.0'));
    });

    test('startPeriodicUpdateChecker', () async {
      var provider = MemoryProvider(releases: [Release.parse('foo/1.0.0')]);

      var updater = ReleaseUpdater(MemoryStorage(), provider);

      var notified = <Release>[];

      var timer = updater.startPeriodicUpdateChecker(
        notified.add,
        interval: Duration(milliseconds: 50),
      );

      try {
        await Future.delayed(Duration(milliseconds: 300));
        expect(notified, isNotEmpty);
        expect(notified.first.toString(), equals('foo/1.0.0'));
      } finally {
        timer.cancel();
      }
    });
  });

  group('ReleaseProvider', () {
    test('lastRelease (platform match)', () async {
      var provider = MemoryProvider(
        releases: [
          Release.parse('foo/1.0.0/linux'),
          Release.parse('foo/1.0.2/linux'),
          Release.parse('foo/1.0.3/macos'),
          Release.parse('bar/2.0.0/linux'),
        ],
      );

      expect(
        (await provider.lastRelease('foo', platform: 'linux')).toString(),
        equals('foo/1.0.2/linux'),
      );

      expect(
        (await provider.lastRelease('bar', platform: 'linux')).toString(),
        equals('bar/2.0.0/linux'),
      );
    });

    test('lastRelease (fallback to no platform)', () async {
      var provider = MemoryProvider(
        releases: [Release.parse('foo/1.0.0'), Release.parse('foo/1.0.2')],
      );

      expect(
        (await provider.lastRelease('foo', platform: 'linux')).toString(),
        equals('foo/1.0.2'),
      );

      expect(
        (await provider.lastRelease('foo')).toString(),
        equals('foo/1.0.2'),
      );
    });

    test('lastRelease (no platform match)', () async {
      var provider = MemoryProvider(
        releases: [Release.parse('foo/1.0.0/macos')],
      );

      expect(await provider.lastRelease('foo', platform: 'linux'), isNull);
      expect(await provider.lastRelease('unknown'), isNull);

      // Without a target platform any platform is accepted:
      expect(
        (await provider.lastRelease('foo')).toString(),
        equals('foo/1.0.0/macos'),
      );
    });
  });
}

/// A [Version] implementation that is not a [SemanticVersioning].
class _StringVersion extends Version {
  final String version;

  _StringVersion(this.version);

  @override
  int compareTo(Version other) => version.compareTo(other.toString());

  @override
  String toString() => version;
}
