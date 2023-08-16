@TestOn('vm')
import 'dart:io';

import 'package:mercury_client/mercury_client.dart';
import 'package:path/path.dart' as pack_path;
import 'package:release_updater/release_packer.dart';
import 'package:release_updater/release_updater.dart';
import 'package:release_updater/src/release_updater_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePacker', () {
    test('ReleasePackerCommand', () async {
      expect(
          ReleasePackerCommand.parseInlineCommand(
              'bin/foo.exe arg1 "a b x" arg2'),
          equals(['bin/foo.exe', 'arg1', 'a b x', 'arg2']));
    });

    test('ReleasePackerCommand', () async {
      {
        var cmd = ReleasePackerCommandURL.fromJson(
            {'url': 'http://foo/bar', 'authorization': 'joe:12345678'});

        expect(cmd.url, equals('http://foo/bar'));

        var authorization = cmd.authorization as BasicCredential;
        expect(authorization.username, equals('joe'));
        expect(authorization.password, equals('12345678'));

        expect(cmd.parameters, isNull);
        expect(cmd.body, isNull);
      }
      {
        var cmd = ReleasePackerCommandURL.fromJson({
          'url': 'http://foo/bar',
          'authorization': 'joe:12345678',
          'parameters': {'a': 123},
          'body': 'Data'
        });

        expect(cmd.url, equals('http://foo/bar'));

        var authorization = cmd.authorization as BasicCredential;
        expect(authorization.username, equals('joe'));
        expect(authorization.password, equals('12345678'));

        expect(cmd.parameters, equals({'a': 123}));
        expect(cmd.body, equals('Data'));
      }

      {
        var cmd = ReleasePackerCommandURL.fromJson({
          'url': 'http://foo/bar',
          'authorization': {'user': 'userX', 'pass': 'pass123'},
          'parameters': {'a': 123},
          'body': 'Data'
        });

        expect(cmd.url, equals('http://foo/bar'));

        var authorization = cmd.authorization as BasicCredential;
        expect(authorization.username, equals('userX'));
        expect(authorization.password, equals('pass123'));
      }

      {
        var cmd = ReleasePackerCommand.from({
          'url': {
            'url': 'http://foo/bar',
            'authorization': {'user': 'userX', 'pass': 'pass123'},
            'parameters': {'a': 123},
            'body': 'Data'
          }
        });

        expect(cmd, isA<ReleasePackerCommandURL>());

        var cmdURL = cmd as ReleasePackerCommandURL;

        expect(cmdURL.url, equals('http://foo/bar'));

        var authorization = cmdURL.authorization as BasicCredential;
        expect(authorization.username, equals('userX'));
        expect(authorization.password, equals('pass123'));
      }

      {
        var cmd = ReleasePackerCommand.from('dart_pub_get');

        expect(cmd, isA<ReleasePackerDartPubGet>());
      }

      {
        var cmd =
            ReleasePackerCommand.from({'dart_compile_exe': 'bin/foo.dart'});

        expect(cmd, isA<ReleasePackerDartCompileExe>());

        var cmdWinGUI = cmd as ReleasePackerDartCompileExe;

        expect(cmdWinGUI.args, equals(['exe', 'bin/foo.dart']));
      }

      {
        var cmd = ReleasePackerCommand.from({'windows_gui': 'bin/foo.exe'});

        expect(cmd, isA<ReleasePackerWindowsSubsystemCommand>());

        var cmdWinGUI = cmd as ReleasePackerWindowsSubsystemCommand;

        expect(cmdWinGUI.args, equals(['--windows-gui', 'bin/foo.exe']));
      }

      {
        var cmd = ReleasePackerCommand.from(['dart', 'pub', 'get']);

        expect(cmd, isA<ReleasePackerDartPubGet>());
      }

      {
        var cmd = ReleasePackerCommand.from(
            ['dart', 'compile', 'exe', 'bin/foo.dart']);

        expect(cmd, isA<ReleasePackerDartCompileExe>());

        var cmdDartExe = cmd as ReleasePackerDartCompileExe;

        expect(cmdDartExe.args, equals(['exe', 'bin/foo.dart']));
      }

      {
        var cmd = ReleasePackerCommand.from(['windows_gui', 'bin/foo.exe']);

        expect(cmd, isA<ReleasePackerWindowsSubsystemCommand>());

        var cmdWinGUI = cmd as ReleasePackerWindowsSubsystemCommand;

        expect(cmdWinGUI.args, equals(['--windows-gui', 'bin/foo.exe']));
      }
    });

    test('buildFromDirectory', () async {
      var releasePackerJsonPath = resolveReleasePackerJsonFilePath();
      var properties = {'readme': 'README.md', 'FOO_EXE_PATH': 'foo-cli.exe'};

      var releasePacker = ReleasePacker.fromFilePath(releasePackerJsonPath,
          properties: properties);

      print(releasePacker);
      for (var f in releasePacker.files) {
        print('-- $f');
      }

      expect(releasePacker.name, equals('foo'));
      expect(releasePacker.version.toString(), equals(ReleaseUpdater.VERSION));

      var prepareCommands = releasePacker.prepareCommands!;
      expect(prepareCommands.length, equals(4));

      {
        expect(prepareCommands[0], isA<ReleasePackerDartPubGet>());

        expect(prepareCommands[1], isA<ReleasePackerDartCompileExe>());
        expect((prepareCommands[1] as ReleasePackerDartCompileExe).args,
            equals(['exe', 'bin/foo.dart']));

        expect(prepareCommands[2], isA<ReleasePackerWindowsSubsystemCommand>());
        expect(
            (prepareCommands[2] as ReleasePackerWindowsSubsystemCommand)
                .command,
            equals('release_utility'));
        expect(
            (prepareCommands[2] as ReleasePackerWindowsSubsystemCommand).args,
            equals(['--windows-gui', 'bin/foo.exe']));

        expect(prepareCommands[3], isA<ReleasePackerProcessCommand>());
        expect((prepareCommands[3] as ReleasePackerProcessCommand).command,
            equals('bin/foo.exe'));
        expect(
            (prepareCommands[3] as ReleasePackerProcessCommand).stdoutFilePath,
            equals('foo.out'));
      }

      var finalizeCommands = releasePacker.finalizeCommands!;
      expect(finalizeCommands.length, equals(2));

      {
        expect(finalizeCommands[0], isA<ReleasePackerCommandDelete>());
        expect((finalizeCommands[0] as ReleasePackerCommandDelete).path,
            equals('bin/foo.exe'));

        expect(finalizeCommands[1], isA<ReleasePackerCommandDelete>());
        expect((finalizeCommands[1] as ReleasePackerCommandDelete).path,
            equals('foo.out'));
      }

      expect(releasePacker.files.length, equals(8));

      expect(releasePacker.configDirectory, isNotNull);

      {
        var file = releasePacker.getFile('hello.txt')!;
        expect(file.sourcePath, equals('hello.txt'));
        expect(file.destinyPath, equals('hello-world.txt'));
        expect(file.platforms, isEmpty);
        expect(file.matchesPlatform('any'), isTrue);
      }

      {
        var file = releasePacker.getFile('bin/foo.exe')!;
        expect(file.sourcePath, equals('bin/foo.exe'));
        expect(file.destinyPath, equals('foo-cli.exe'));
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

      var bundle = await releasePacker.buildFromDirectory(
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

  expect(bundleFiles.length, equals(5));

  var bundleZipBytes = await bundle.zipBytes;
  expect(bundleZipBytes.length, greaterThan(100));

  {
    var file = bundleFiles[0];
    expect(file.filePath, equals('README.md'));

    var dataStr = await file.dataAsString;
    expect(dataStr.normalizeToPosixLines().trim(),
        equals('# Foo/1.0.1\n\nA Foo project.'));
  }

  {
    var file = bundleFiles[1];
    expect(file.filePath, equals('foo-cli.exe'));

    var length = await file.length;
    expect(length, greaterThan(1024));
  }

  {
    var file = bundleFiles[2];
    expect(file.filePath, equals('foo.txt'));

    var dataStr = await file.dataAsString;
    expect(dataStr.trim(), equals('Foo!'));
  }

  {
    var file = bundleFiles[3];
    expect(file.filePath, equals('hello-world.txt'));

    var dataStr = await file.dataAsString;
    expect(dataStr.trim(), equals('Hello World!'));
  }

  {
    var file = bundleFiles[4];
    expect(file.filePath, equals('platform.txt'));

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
