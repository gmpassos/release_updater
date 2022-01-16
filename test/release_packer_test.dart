import 'dart:io';

import 'package:path/path.dart' as pack_path;
import 'package:release_updater/release_packer.dart';
import 'package:release_updater/release_updater.dart';
import 'package:release_updater/src/release_updater_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePacker', () {
    test('memory', () async {
      var releasePackerJsonPath = resolveReleasePackerJsonFilePath();
      var releasePacker = ReleasePacker.fromFilePath(releasePackerJsonPath);

      print(releasePacker);
      for (var f in releasePacker.files) {
        print('-- $f');
      }

      expect(releasePacker.name, equals('foo'));
      expect(releasePacker.version.toString(), equals(ReleaseUpdater.VERSION));

      expect(releasePacker.files.length, equals(6));

      expect(releasePacker.configDirectory, isNotNull);

      {
        var file = releasePacker.getFile('hello.txt')!;
        expect(file.sourcePath, equals('hello.txt'));
        expect(file.destinyPath, equals('hello-world.txt'));
        expect(file.platforms, isEmpty);
        expect(file.matchesPlatform('any'), isTrue);
      }

      {
        var file = releasePacker.getFile('platform-macos-arm64.txt')!;
        expect(file.sourcePath, equals('platform-macos-arm64.txt'));
        expect(file.destinyPath, equals('platform.txt'));
        expect(file.platforms, isNotEmpty);

        expect(file.matchesPlatform('any'), isFalse);
        expect(file.matchesPlatform('macos'), isFalse);
        expect(file.matchesPlatform('macos-x64'), isFalse);
        expect(file.matchesPlatform('macos-arm64'), isTrue);
      }

      {
        var file = releasePacker.getFile('platform-macos-x64.txt')!;
        expect(file.sourcePath, equals('platform-macos-x64.txt'));
        expect(file.destinyPath, equals('platform.txt'));
        expect(file.platforms, isNotEmpty);

        expect(file.matchesPlatform('any'), isFalse);
        expect(file.matchesPlatform('macos'), isFalse);
        expect(file.matchesPlatform('macos-x64'), isTrue);
        expect(file.matchesPlatform('macos-arm64'), isFalse);
      }
      {
        var file = releasePacker.getFile('platform-linux-x64.txt')!;
        expect(file.sourcePath, equals('platform-linux-x64.txt'));
        expect(file.destinyPath, equals('platform.txt'));
        expect(file.platforms, isNotEmpty);

        expect(file.matchesPlatform('any'), isFalse);
        expect(file.matchesPlatform('macos'), isFalse);
        expect(file.matchesPlatform('macos-x64'), isFalse);
        expect(file.matchesPlatform('macos-arm64'), isFalse);

        expect(file.matchesPlatform('linux-x64'), isTrue);
        expect(file.matchesPlatform('linux-x32'), isTrue);
      }

      var platform = ReleasePlatform.platform;

      var bundle = releasePacker.buildFromDirectory(
          sourcePath: 'project-foo', platform: platform);

      await _checkBundle(bundle, platform);

      var bundleZipBytes = await bundle.zipBytes;
      var bundle2 = ReleaseBundleZip(bundle.release, zipBytes: bundleZipBytes);

      await _checkBundle(bundle2, platform);
    });
  });
}

Future<void> _checkBundle(ReleaseBundleZip bundle, String platform) async {
  expect(bundle, isNotNull);

  expect(bundle.release.toString(),
      equals('foo/${ReleaseUpdater.VERSION}/$platform'));

  var bundleFiles = (await bundle.files).toList();
  bundleFiles.sort();

  expect(bundleFiles.length, equals(3));

  var bundleZipBytes = await bundle.zipBytes;
  expect(bundleZipBytes.length, greaterThan(100));

  {
    var file = bundleFiles[0];
    expect(file.path, equals('README.md'));

    var dataStr = await file.dataAsString;
    expect(dataStr.normalizeToPosixLines().trim(),
        equals('# Foo/1.0.1\n\nA Foo project.'));
  }

  {
    var file = bundleFiles[1];
    expect(file.path, equals('hello-world.txt'));

    var dataStr = await file.dataAsString;
    expect(dataStr.trim(), equals('Hello World!'));
  }

  {
    var file = bundleFiles[2];
    expect(file.path, equals('platform.txt'));

    var dataStr = await file.dataAsString;
    expect(dataStr.trim(), equals(platform));
  }
}

String resolveReleasePackerJsonFilePath() {
  var paths = [
    'release_packer.json',
    'test/release_packer.json',
    '../test/release_packer.json'
  ];

  var currentDir = Directory.current;

  for (var p in paths) {
    var file = File(pack_path.join(currentDir.path, p));
    if (file.existsSync()) {
      return file.path;
    }
  }

  return paths.first;
}
