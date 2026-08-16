@TestOn('vm')
import 'dart:io';

import 'package:release_updater/release_updater_io.dart';
import 'package:release_updater/src/release_updater_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseStorageDirectory', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-storage--');
    });

    tearDown(() {
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
    });

    ReleaseBundleZip bundle(
      String version, {
      Map<String, String>? files,
      String? platform,
    }) => ReleaseBundleZip(
      Release('foo', SemanticVersioning.parse(version), platform: platform),
      files: (files ?? {'README.md': '#Foo/$version', 'hello.txt': 'Hello!'})
          .entries
          .map((e) => ReleaseFile(e.key, e.value))
          .toList(),
    );

    test('normalizeFileName', () {
      expect(
        ReleaseStorageDirectory.normalizeFileName(' foo bar '),
        equals('foo_bar'),
      );
      expect(
        ReleaseStorageDirectory.normalizeFileName('foo-1.0.0'),
        equals('foo-1.0.0'),
      );
    });

    test('copy', () {
      var storage = ReleaseStorageDirectory(
        'foo',
        tmpDir,
        overwriteFiles: false,
        selfReleaseDirectory: true,
      );

      var copy = storage.copy();

      expect(copy.name, equals('foo'));
      expect(copy.directory.path, equals(tmpDir.path));
      expect(copy.selfReleaseDirectory, isTrue);
      expect(copy.overwriteFiles, equals(storage.overwriteFiles));

      var storage2 = ReleaseStorageDirectory('foo', tmpDir);
      expect(storage2.copy().overwriteFiles, isTrue);
      expect(storage2.copy().selfReleaseDirectory, isFalse);
    });

    test('`selfReleaseDirectory` disables `overwriteFiles`', () {
      var storage = ReleaseStorageDirectory(
        'foo',
        tmpDir,
        selfReleaseDirectory: true,
      );

      expect(storage.overwriteFiles, isFalse);
    });

    test('empty storage', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      expect(storage.currentRelease, isNull);
      expect(storage.currentReleasePath, isNull);
      expect(storage.currentReleaseDirectory, isNull);
      expect(storage.currentFiles, isEmpty);
      expect(await storage.currentReleaseFilePath('README.md'), isNull);
      expect(await storage.loadManifest(), isNull);
      expect(storage.onSpawned(), isTrue);
      expect(storage.toString(), contains(tmpDir.path));
    });

    test('releaseDirectory and releasePathName', () {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      var release = Release.parse('foo/1.0.0/linux-x64');

      expect(storage.releasePathName(release), equals('foo--1.0.0'));
      expect(storage.releaseDirectory(release).path, endsWith('foo--1.0.0'));

      // The directory instance is cached:
      expect(
        identical(
          storage.releaseDirectory(release),
          storage.releaseDirectory(release),
        ),
        isTrue,
      );

      expect(
        storage.currentReleaseConfigFile.path,
        endsWith('foo--current.release'),
      );
    });

    test('updateTo', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      var result = await storage.updateTo(bundle('1.0.0'), verbose: true);

      expect(result, isNotNull);
      expect(result!.savedFilesLength, equals(2));

      expect(storage.currentRelease, equals(Release.parse('foo/1.0.0')));
      expect(storage.currentReleasePath, endsWith('foo--1.0.0'));

      var files = storage.currentFiles.toList()..sort();
      expect(files.map((e) => e.filePath), equals(['README.md', 'hello.txt']));
      expect(await files[0].dataAsString, equals('#Foo/1.0.0'));

      expect(
        await storage.currentReleaseFilePath('hello.txt'),
        endsWith('hello.txt'),
      );
      expect(await storage.currentReleaseFilePath('unknown.txt'), isNull);

      var manifest = await storage.loadManifest();
      expect(manifest!.release, equals(Release.parse('foo/1.0.0')));
      expect(await storage.checkManifest(manifest), isTrue);

      // Same release: no update.
      expect(await storage.updateTo(bundle('1.0.0')), isNull);

      // Forced: updates but skips the unchanged files.
      var forced = await storage.updateTo(bundle('1.0.0'), force: true);
      expect(forced!.savedFilesLength, equals(0));
    });

    test('updateTo (only the changed files are saved)', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      await storage.updateTo(bundle('1.0.0'));

      var result = await storage.updateTo(
        bundle(
          '1.0.1',
          files: {'README.md': '#Foo/1.0.0', 'hello.txt': 'Hello World!'},
        ),
      );

      expect(
        result!.savedFiles.map((e) => e.filePath),
        equals(['README.md', 'hello.txt']),
      );

      // The 1.0.1 directory is a new one, so both files are saved:
      expect(storage.currentReleasePath, endsWith('foo--1.0.1'));
    });

    test('checkManifest of a missing release directory', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      var manifest = await bundle('9.9.9').buildManifest();

      expect(await storage.checkManifest(manifest, verbose: true), isFalse);
    });

    test('checkManifest of a modified file', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      await storage.updateTo(bundle('1.0.0'));

      var manifest = (await storage.loadManifest())!;

      var readme = File(
        await storage.currentReleaseFilePath('README.md') ?? '',
      );
      readme.writeAsStringSync('CHANGED!!');

      expect(await storage.checkManifest(manifest), isFalse);
    });

    test('currentRelease of a removed release directory', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      await storage.updateTo(bundle('1.0.0'));
      expect(storage.currentRelease, isNotNull);

      storage.currentReleaseDirectory!.deleteSync(recursive: true);

      // The release file points to a directory that does not exist:
      expect(storage.currentRelease, isNull);
    });

    test('currentRelease of a corrupted release file', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      storage.currentReleaseConfigFile.writeAsStringSync('');
      expect(storage.currentRelease, isNull);

      storage.currentReleaseConfigFile.writeAsStringSync('not-a-release');
      expect(storage.currentRelease, isNull);
    });

    test('loadManifest of a corrupted manifest file', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      storage.currentManifestFile.writeAsStringSync('{ not a json');

      expect(await storage.loadManifest(), isNull);
    });

    test('executable file permission', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      var release = Release.parse('foo/1.0.0');

      var releaseFile = ReleaseFile('run.sh', '#!/bin/sh\n', executable: true);

      await storage.updateTo(ReleaseBundleZip(release, files: [releaseFile]));

      var file = File(await storage.currentReleaseFilePath('run.sh') ?? '');
      expect(file.existsSync(), isTrue);

      if (Platform.isLinux || Platform.isMacOS) {
        expect(file.hasExecutablePermission, isTrue);

        storage.setReleaseFileExecutablePermission(release, releaseFile, false);
        expect(file.hasExecutablePermission, isFalse);

        storage.setReleaseFileExecutablePermission(release, releaseFile, true);
        expect(file.hasExecutablePermission, isTrue);
      }
    });

    test('selfReleaseDirectory and installNewReleaseFiles', () async {
      var storage = ReleaseStorageDirectory(
        'foo',
        tmpDir,
        selfReleaseDirectory: true,
      );

      await storage.updateTo(bundle('1.0.0'));

      var readme = File('${tmpDir.path}/README.md');
      expect(readme.existsSync(), isTrue);
      expect(readme.readAsStringSync(), equals('#Foo/1.0.0'));

      // A new release does not overwrite the current files,
      // saving them with a `.new_release` suffix:
      await storage.updateTo(
        bundle(
          '1.0.1',
          files: {'README.md': '#Foo/1.0.1', 'hello.txt': 'Hello!'},
        ),
      );

      var readmeNew = File('${tmpDir.path}/README.md.new_release');

      expect(readmeNew.existsSync(), isTrue);
      expect(readmeNew.readAsStringSync(), equals('#Foo/1.0.1'));
      expect(readme.readAsStringSync(), equals('#Foo/1.0.0'));

      var movedFiles = storage.installNewReleaseFiles();

      expect(movedFiles.map((e) => e.path), contains(readme.path));
      expect(readmeNew.existsSync(), isFalse);
      expect(readme.readAsStringSync(), equals('#Foo/1.0.1'));
    });

    test('directoryFiles and directoryReleaseFiles', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      await storage.updateTo(bundle('1.0.0'));

      var dir = storage.currentReleaseDirectory!;

      expect(storage.directoryFiles(dir), hasLength(2));

      var releaseFiles = storage.directoryReleaseFiles(dir)..sort();
      expect(
        releaseFiles.map((e) => e.filePath),
        equals(['README.md', 'hello.txt']),
      );
    });
  });

  group('File extensions', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-storage-ext--');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('toReleaseFile', () async {
      var file = File('${tmpDir.path}/a.txt');
      file.writeAsStringSync('Hello!');

      var releaseFile = file.toReleaseFile(parentPath: tmpDir.path);

      expect(releaseFile.filePath, equals('a.txt'));
      expect(await releaseFile.length, equals(6));
      expect(await releaseFile.dataAsString, equals('Hello!'));
      expect(releaseFile.executable, isFalse);

      // Without a `parentPath` the full path is normalized:
      expect(file.toReleaseFile().filePath, endsWith('a.txt'));
    });

    test('toReleaseFile (executable extension)', () {
      var file = File('${tmpDir.path}/run.sh');
      file.writeAsStringSync('#!/bin/sh\n');

      expect(file.toReleaseFile(parentPath: tmpDir.path).executable, isTrue);
    });

    test('toFile', () {
      var releaseFile = ReleaseFile('dir/a.txt', 'x');

      expect(
        releaseFile.toFile(parentDirectory: tmpDir).path,
        equals(joinPaths(tmpDir.path, 'dir/a.txt')),
      );

      expect(releaseFile.toFile().path, endsWith('a.txt'));
    });

    test('FileDataProvider', () {
      var file = File('${tmpDir.path}/a.txt');
      file.writeAsStringSync('Hello!');

      var provider = FileDataProvider(file);

      expect(provider.length, equals(6));
      expect(provider.get(), equals('Hello!'.codeUnits));

      // Cached:
      expect(identical(provider.get(), provider.get()), isTrue);
    });

    test('ReleaseManifestFile.checkFile', () async {
      var file = File('${tmpDir.path}/a.txt');
      file.writeAsStringSync('Hello!');

      var manifestFile = await ReleaseManifestFile.fromReleaseFile(
        ReleaseFile('a.txt', 'Hello!'),
      );

      expect(await manifestFile.checkFile(file), isTrue);

      file.writeAsStringSync('Hello?');
      expect(await manifestFile.checkFile(file), isFalse);

      file.writeAsStringSync('Hello!!');
      expect(await manifestFile.checkFile(file), isFalse);

      file.deleteSync();
      expect(await manifestFile.checkFile(file), isFalse);
    });

    test('computeSHA256', () {
      var file = File('${tmpDir.path}/a.txt');
      file.writeAsStringSync('abc');

      expect(
        file.computeSHA256().toString(),
        equals(
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
      );
    });
  });

  group('whichExecutablePath', () {
    test('resolves a system executable', () {
      var executable = Platform.isWindows ? 'where' : 'ls';

      var path = whichExecutablePath(executable);

      expect(path, isNotEmpty);
      expect(path.toLowerCase(), contains(executable));

      // Cached:
      expect(whichExecutablePath(executable), equals(path));
      expect(whichExecutablePath(executable, useCache: false), equals(path));
    });

    test('unknown executable', () {
      var path = whichExecutablePath('__unknown_executable_x__');
      expect(path, equals('__unknown_executable_x__'));

      expect(
        whichExecutablePath('__unknown_executable_y__', def: '/bin/def'),
        equals('/bin/def'),
      );
    });
  });

  group('ReleaseUpdaterIOExtension', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-process--');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('runReleaseProcess (unknown executable)', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      var updater = ReleaseUpdater(storage, _EmptyProvider());

      expect(await updater.runReleaseProcess('unknown.sh', []), isNull);
      expect(await updater.startReleaseProcess('unknown.sh', []), isNull);
    });

    test('runReleaseProcess', () async {
      var storage = ReleaseStorageDirectory('foo', tmpDir);

      await storage.updateTo(
        ReleaseBundleZip(
          Release.parse('foo/1.0.0'),
          files: [
            ReleaseFile(
              'echo.sh',
              '#!/bin/sh\necho "release-updater-test"\n',
              executable: true,
            ),
          ],
        ),
      );

      var updater = ReleaseUpdater(storage, _EmptyProvider());

      if (Platform.isLinux || Platform.isMacOS) {
        var result = await updater.runReleaseProcess('echo.sh', []);

        expect(result, isNotNull);
        expect(result!.exitCode, equals(0));
        expect(result.stdout.toString().trim(), equals('release-updater-test'));

        var process = await updater.startReleaseProcess('echo.sh', []);
        expect(process, isNotNull);
        expect(await process!.exitCode, equals(0));
      }
    });
  });
}

class _EmptyProvider extends ReleaseProvider {
  @override
  _EmptyProvider copy() => _EmptyProvider();

  @override
  List<Release> listReleases() => <Release>[];

  @override
  ReleaseBundle? getReleaseBundle(
    String name,
    Version targetVersion, [
    String? platform,
  ]) => null;
}
