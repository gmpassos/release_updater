@TestOn('vm')
import 'dart:convert' as dart_convert;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:release_updater/release_updater.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseBundle', () {
    test('formatReleaseBundleFile', () {
      var version = SemanticVersioning.parse('1.0.2');

      expect(
        ReleaseBundle.formatReleaseBundleFile(
          ReleaseBundle.defaultReleasesBundleFileFormat,
          'foo',
          version,
          'linux-x64',
        ),
        equals('foo-1.0.2-linux-x64.zip'),
      );

      expect(
        ReleaseBundle.formatReleaseBundleFile(
          ReleaseBundle.defaultReleasesBundleFileFormat,
          'foo',
          version,
        ),
        equals('foo-1.0.2.zip'),
      );

      expect(
        ReleaseBundle.formatReleaseBundleFile(
          '%NAME%/%VER%/%NAME%-%VER%.zip',
          'foo',
          version,
        ),
        equals('foo/1.0.2/foo-1.0.2.zip'),
      );

      // Without any mark the file is returned as is:
      expect(
        ReleaseBundle.formatReleaseBundleFile('release.zip', 'foo', version),
        equals('release.zip'),
      );
    });

    test('buildManifest', () async {
      var bundle = _bundle(platform: 'linux-x64');

      var manifest = await bundle.buildManifest();

      expect(manifest.release, equals(bundle.release));
      expect(manifest.files, hasLength(2));

      var file = manifest.getFileByPath('a.txt')!;
      expect(file.filePath, equals('a.txt'));
      expect(file.length, equals(1));
      expect(file.sha256Hex, hasLength(64));

      expect(manifest.getFileByPath('unknown.txt'), isNull);

      expect(await manifest.checkBundle(bundle), isTrue);
    });

    test('toASCIIArtTree', () async {
      var bundle = ReleaseBundleZip(
        Release.parse('foo/1.0.0'),
        files: [
          ReleaseFile('a.txt', 'A'),
          ReleaseFile('b.txt', 'BB'),
          ReleaseFile('run.sh', '#!/bin/sh', executable: true),
          // NOTE: `ascii_art_tree` 1.0.6 does not render nested nodes,
          // so only the root entries are checked below.
          ReleaseFile('dir/c.txt', 'CCC'),
        ],
      );

      var tree = await bundle.toASCIIArtTree();
      var treeText = tree.generate();

      print(treeText);

      expect(treeText, contains('a.txt - (1 bytes)'));
      expect(treeText, contains('b.txt - (2 bytes)'));
      expect(treeText, contains('run.sh - (9 bytes) (EXEC)'));
      expect(treeText, contains('dir'));
    });
  });

  group('ReleaseBundleZip', () {
    test('null `files` and `zipBytes`', () {
      expect(
        () => ReleaseBundleZip(Release.parse('foo/1.0.0')),
        throwsArgumentError,
      );
    });

    test('isExecutableFilePath', () {
      expect(ReleaseBundleZip.isExecutableFilePath('a.exe'), isTrue);
      expect(ReleaseBundleZip.isExecutableFilePath('a.sh'), isTrue);
      expect(ReleaseBundleZip.isExecutableFilePath('a.txt'), isFalse);

      expect(ReleaseBundleZip.isExecutableFilePath('a.bin', ['bin']), isTrue);
      expect(ReleaseBundleZip.isExecutableFilePath('a.sh', ['bin']), isFalse);
    });

    test('contentType', () {
      expect(_bundle().contentType, equals('application/zip'));
    });

    test('Zip round-trip', () async {
      var bundle = _bundle(platform: 'linux-x64');

      var zipBytes = await bundle.toBytes();
      expect(zipBytes, isNotEmpty);

      // `zipBytes` is cached:
      expect(identical(await bundle.toBytes(), zipBytes), isTrue);

      var bundle2 = ReleaseBundleZip(bundle.release, zipBytes: zipBytes);

      var files = (await bundle2.files).toList()..sort();

      expect(files.map((e) => e.filePath), equals(['a.txt', 'run.sh']));
      expect(await files[0].dataAsString, equals('A'));
      expect(await files[1].dataAsString, equals('#!/bin/sh'));
      expect(files[1].executable, isTrue);

      // The manifest file is removed from the bundle files:
      expect(
        files.map((e) => e.filePath),
        isNot(contains(ReleaseBundleZip.releaseManifestFilePath)),
      );
    });

    test('Zip round-trip (no platform)', () async {
      // Regression: a release without a platform generated a manifest
      // that could not be parsed back.
      var bundle = _bundle();

      var zipBytes = await bundle.toBytes();

      var bundle2 = ReleaseBundleZip(bundle.release, zipBytes: zipBytes);

      var files = (await bundle2.files).toList()..sort();
      expect(files.map((e) => e.filePath), equals(['a.txt', 'run.sh']));
    });

    test('Zip UNIX file modes', () async {
      var zipBytes = await _bundle().toBytes();

      var archive = ZipDecoder().decodeBytes(zipBytes);

      var runSh = archive.files.firstWhere((e) => e.name == 'run.sh');
      var aTxt = archive.files.firstWhere((e) => e.name == 'a.txt');

      expect(runSh.mode, equals(ReleaseBundleZip.executableFileMode));
      expect(runSh.mode, equals(int.parse('755', radix: 8)));

      expect(aTxt.mode, equals(ReleaseBundleZip.regularFileMode));
      expect(aTxt.mode, equals(int.parse('644', radix: 8)));
    });

    test('Zip with `rootPath`', () async {
      var archive = Archive();

      archive.addFile(ArchiveFile.string('foo-1.0.0/a.txt', 'A'));
      archive.addFile(ArchiveFile.string('foo-1.0.0/dir/b.txt', 'B'));

      var zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      var bundle = ReleaseBundleZip(
        Release.parse('foo/1.0.0'),
        zipBytes: zipBytes,
        rootPath: 'foo-1.0.0/',
      );

      var files = (await bundle.files).toList()..sort();
      expect(files.map((e) => e.filePath), equals(['a.txt', 'dir/b.txt']));
    });

    test('Zip with a corrupted manifest', () async {
      var bundle = _bundle();
      var zipBytes = await bundle.toBytes();

      var archive = ZipDecoder().decodeBytes(zipBytes);

      var archive2 = Archive();
      for (var f in archive.files) {
        if (f.name == 'a.txt') {
          archive2.addFile(ArchiveFile.string(f.name, 'CHANGED'));
        } else {
          archive2.addFile(f);
        }
      }

      var bundle2 = ReleaseBundleZip(
        bundle.release,
        zipBytes: Uint8List.fromList(ZipEncoder().encode(archive2)),
      );

      expect(() => bundle2.files, throwsA(isA<StateError>()));
    });

    test('files from a Zip without a manifest', () async {
      var archive = Archive();
      archive.addFile(ArchiveFile.string('a.txt', 'A'));

      var bundle = ReleaseBundleZip(
        Release.parse('foo/1.0.0'),
        zipBytes: Uint8List.fromList(ZipEncoder().encode(archive)),
      );

      var files = await bundle.files;
      expect(files.map((e) => e.filePath), equals(['a.txt']));
    });

    test('files is unmodifiable', () async {
      var bundle = _bundle();
      var files = await bundle.files;

      expect(
        () => files.add(ReleaseFile('x.txt', 'X')),
        throwsUnsupportedError,
      );
    });
  });

  group('ReleaseManifest', () {
    test('JSON round-trip', () async {
      var date = DateTime.utc(2022, 3, 4, 5, 6, 7);

      var manifest = ReleaseManifest(
        Release.parse('foo/1.0.2/linux-x64'),
        date: date,
        files: await _manifestFiles(),
      );

      var json = manifest.toJson();

      expect(json['release'], equals('foo/1.0.2/linux-x64'));
      expect(json['name'], equals('foo'));
      expect(json['version'], equals('1.0.2'));
      expect(json['platform'], equals('linux-x64'));
      expect(json['date'], equals('$date'));

      var manifest2 = ReleaseManifest.fromJson(
        dart_convert.json.decode(manifest.toJsonEncoded()),
      );

      expect(manifest2.release, equals(manifest.release));
      expect(manifest2.date, equals(date));
      expect(manifest2.files.map((e) => e.filePath), equals(['a.txt']));
      expect(
        manifest2.getFileByPath('a.txt')!.sha256Hex,
        equals(manifest.getFileByPath('a.txt')!.sha256Hex),
      );
    });

    test('JSON round-trip (no platform)', () async {
      var manifest = ReleaseManifest(
        Release.parse('foo/1.0.2'),
        files: await _manifestFiles(),
      );

      var json = manifest.toJson();
      expect(json.containsKey('platform'), isFalse);

      var manifest2 = ReleaseManifest.fromJson(
        dart_convert.json.decode(manifest.toJsonEncoded()),
      );

      expect(manifest2.release, equals(manifest.release));
      expect(manifest2.release.platform, isNull);
    });

    test('JSON of a version <= 1.1.12 manifest', () {
      // Old manifests wrote a `null` platform as the `null` string
      // and the date with a `date:` key:
      var manifest = ReleaseManifest.fromJson({
        'release': 'foo/1.0.2',
        'name': 'foo',
        'version': '1.0.2',
        'platform': 'null',
        'date:': '2022-03-04 05:06:07.000Z',
        'files': {
          'a.txt': {
            'sha256':
                '559AEAD08264D5795D3909718CDD05ABD49572E84FE55590EEF31A88A08FDFFD',
            'length': 1,
          },
        },
      });

      expect(manifest.release.toString(), equals('foo/1.0.2'));
      expect(manifest.release.platform, isNull);
      expect(manifest.date, equals(DateTime.utc(2022, 3, 4, 5, 6, 7)));
      expect(manifest.files, hasLength(1));
    });

    test('JSON without a `release` entry', () {
      var manifest = ReleaseManifest.fromJson({
        'name': 'foo',
        'version': '1.0.2',
        'platform': 'linux-x64',
        'files': <String, Object?>{},
      });

      expect(manifest.release.toString(), equals('foo/1.0.2/linux-x64'));
      expect(manifest.files, isEmpty);
    });

    test('JSON with inconsistent entries', () {
      expect(
        () => ReleaseManifest.fromJson({
          'release': 'foo/1.0.2',
          'name': 'bar',
          'files': <String, Object?>{},
        }),
        throwsArgumentError,
      );

      expect(
        () => ReleaseManifest.fromJson({
          'release': 'foo/1.0.2',
          'version': '1.0.3',
          'files': <String, Object?>{},
        }),
        throwsArgumentError,
      );

      expect(
        () => ReleaseManifest.fromJson({
          'release': 'foo/1.0.2',
          'platform': 'linux',
          'files': <String, Object?>{},
        }),
        throwsArgumentError,
      );
    });

    test('addFile replaces a previous file with the same path', () async {
      var manifest = ReleaseManifest(Release.parse('foo/1.0.0'));

      manifest.addFile(
        await ReleaseManifestFile.fromReleaseFile(ReleaseFile('a.txt', 'A')),
      );
      manifest.addFile(
        await ReleaseManifestFile.fromReleaseFile(ReleaseFile('a.txt', 'AA')),
      );

      expect(manifest.files, hasLength(1));
      expect(manifest.getFileByPath('a.txt')!.length, equals(2));
    });

    test('checkBundleFiles', () async {
      var bundle = _bundle();
      var manifest = await bundle.buildManifest();

      expect(await manifest.checkBundleFiles(await bundle.files), isTrue);

      // Missing file:
      expect(
        await manifest.checkBundleFiles([ReleaseFile('a.txt', 'A')]),
        isFalse,
      );

      // Different content (same length):
      expect(
        await manifest.checkBundleFiles([
          ReleaseFile('a.txt', 'B'),
          ReleaseFile('run.sh', '#!/bin/sh'),
        ]),
        isFalse,
      );

      // Different length:
      expect(
        await manifest.checkBundleFiles([
          ReleaseFile('a.txt', 'AA'),
          ReleaseFile('run.sh', '#!/bin/sh'),
        ]),
        isFalse,
      );
    });
  });

  group('ReleaseManifestFile', () {
    test('fromSha256Hex and sha256Hex', () async {
      var file = await ReleaseManifestFile.fromReleaseFile(
        ReleaseFile('a.txt', 'A'),
      );

      var file2 = ReleaseManifestFile.fromSha256Hex(
        file.filePath,
        file.length,
        file.sha256Hex,
      );

      expect(file2.sha256, equals(file.sha256));
      expect(file2.sha256Hex, equals(file.sha256Hex));
      expect(await file2.checkReleaseFile(ReleaseFile('a.txt', 'A')), isTrue);
      expect(await file2.checkReleaseFile(ReleaseFile('a.txt', 'B')), isFalse);
    });

    test('toReleaseManifestFileList', () async {
      var list = await ReleaseManifestFile.toReleaseManifestFileList([
        ReleaseFile('a.txt', 'A'),
        ReleaseFile('b.txt', 'BB'),
      ]);

      expect(list.map((e) => e.filePath), equals(['a.txt', 'b.txt']));
      expect(list.map((e) => e.length), equals([1, 2]));
    });

    test('sha256 is unmodifiable', () async {
      var file = await ReleaseManifestFile.fromReleaseFile(
        ReleaseFile('a.txt', 'A'),
      );

      expect(() => file.sha256[0] = 0, throwsUnsupportedError);
    });
  });
}

ReleaseBundleZip _bundle({String? platform}) => ReleaseBundleZip(
  Release('foo', SemanticVersioning.parse('1.0.2'), platform: platform),
  files: [
    ReleaseFile('a.txt', 'A'),
    ReleaseFile('run.sh', '#!/bin/sh', executable: true),
  ],
);

Future<List<ReleaseManifestFile>> _manifestFiles() =>
    ReleaseManifestFile.toReleaseManifestFileList([ReleaseFile('a.txt', 'A')]);
