@TestOn('vm')
import 'dart:convert' as dart_convert;
import 'dart:io';

import 'package:path/path.dart' as pack_path;
import 'package:release_updater/release_packer.dart';
import 'package:release_updater/release_updater.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePackerDartBuild', () {
    test('JSON keys', () {
      expect(
        ReleasePackerDartBuild.subcommandOfJsonKey('dart_build_cli'),
        'cli',
      );
      expect(
        ReleasePackerDartBuild.subcommandOfJsonKey('dart_build_foo'),
        'foo',
      );
      expect(ReleasePackerDartBuild.subcommandOfJsonKey('dart_build_'), isNull);
      expect(
        ReleasePackerDartBuild.subcommandOfJsonKey('dart_compile_exe'),
        isNull,
      );
      expect(ReleasePackerDartBuild.subcommandOfJsonKey(123), isNull);

      expect(ReleasePackerDartBuild.isJsonKey('dart_build_cli'), isTrue);
      expect(ReleasePackerDartBuild.isJsonKey('platform'), isFalse);
    });

    test('Map (dart_build_cli: String)', () {
      var cmd = ReleasePackerCommand.from({'dart_build_cli': 'bin/foo.dart'});

      expect(cmd, isA<ReleasePackerDartBuildCli>());
      cmd as ReleasePackerDartBuildCli;

      expect(cmd.command, equals('build'));
      expect(
        cmd.args,
        equals([
          'cli',
          '--target',
          'bin/foo.dart',
          '--output',
          'build/cli/foo',
        ]),
      );
      expect(cmd.target, equals('bin/foo.dart'));
      expect(cmd.output, equals('build/cli/foo'));
      expect(cmd.launcher, isFalse);
      expect(cmd.toString(), contains('build/cli/foo/bundle'));
    });

    test('Map (dart_build_cli: Map)', () {
      var cmd = ReleasePackerCommand.from({
        'dart_build_cli': {
          'target': 'bin/foo.dart',
          'output': 'out/foo',
          'args': '--verbosity error',
          'launcher': true,
        },
      });

      expect(cmd, isA<ReleasePackerDartBuildCli>());
      cmd as ReleasePackerDartBuildCli;

      expect(
        cmd.args,
        equals([
          'cli',
          '--target',
          'bin/foo.dart',
          '--output',
          'out/foo',
          '--verbosity',
          'error',
        ]),
      );
      expect(cmd.launcher, isTrue);
      expect(cmd.bundlePath, equals('out/foo/bundle'));
    });

    test('Map (dart_build_cli: args List, launcher String)', () {
      var cmd = ReleasePackerDartBuildCli.fromJson({
        'target': 'bin/foo.dart',
        'args': ['--target-os', 'linux'],
        'launcher': 'true',
      });

      expect(cmd.args.skip(5), equals(['--target-os', 'linux']));
      expect(cmd.launcher, isTrue);
    });

    test('Map (dart_build_cli: invalid)', () {
      expect(
        () => ReleasePackerDartBuildCli.fromJson({'output': 'x'}),
        throwsArgumentError,
      );
      expect(
        () => ReleasePackerDartBuildCli.fromJson({'target': ''}),
        throwsArgumentError,
      );
      expect(
        () => ReleasePackerDartBuildCli.fromJson(123),
        throwsArgumentError,
      );
    });

    test('Map (other subcommand)', () {
      var cmd = ReleasePackerCommand.from({'dart_build_foo': '-a "b c"'});

      expect(cmd, isA<ReleasePackerDartBuild>());
      expect(cmd, isNot(isA<ReleasePackerDartBuildCli>()));
      cmd as ReleasePackerDartBuild;

      expect(cmd.subcommand, equals('foo'));
      expect(cmd.args, equals(['foo', '-a', 'b c']));
      expect(cmd.toString(), contains('foo'));

      expect(
        (ReleasePackerCommand.from({'dart_build_foo': true})
                as ReleasePackerDartBuild)
            .args,
        equals(['foo']),
      );
      expect(
        (ReleasePackerCommand.from({
                  'dart_build_foo': ['-x', 1],
                })
                as ReleasePackerDartBuild)
            .args,
        equals(['foo', '-x', '1']),
      );
      expect(
        () => ReleasePackerCommand.from({'dart_build_foo': 123}),
        throwsArgumentError,
      );
    });

    test('String and List (`dart build`)', () {
      var cmd1 = ReleasePackerCommand.from('dart build cli -t bin/foo.dart');
      expect(cmd1, isA<ReleasePackerDartBuild>());
      cmd1 as ReleasePackerDartBuild;
      expect(cmd1.subcommand, equals('cli'));
      // The arguments are kept as is:
      expect(cmd1.args, equals(['cli', '-t', 'bin/foo.dart']));

      var cmd2 = ReleasePackerCommand.from(['dart', 'build', 'cli']);
      expect(cmd2, isA<ReleasePackerDartBuild>());
      expect((cmd2 as ReleasePackerDartBuild).args, equals(['cli']));

      var cmd3 = ReleasePackerCommand.from({'dart': 'build cli'});
      expect(cmd3, isA<ReleasePackerDartBuild>());

      // `dart build` without a subcommand is a plain `dart` command:
      var cmd4 = ReleasePackerCommand.from('dart build');
      expect(cmd4, isA<ReleasePackerDartCommand>());
      expect(cmd4, isNot(isA<ReleasePackerDartBuild>()));

      expect(() => ReleasePackerDartBuild.fromArgs([]), throwsArgumentError);
    });

    test('paths and launcher', () {
      var linux = ReleasePackerDartBuildCli(
        'bin/foo.dart',
        args: ['--target-os=linux'],
      );
      expect(linux.name, equals('foo'));
      expect(linux.targetsWindows, isFalse);
      expect(linux.executablePath, equals('build/cli/foo/bundle/bin/foo'));
      expect(linux.launcherPath, equals('build/cli/foo/bundle/foo'));
      expect(linux.launcherScript, startsWith('#!/bin/sh\n'));
      expect(linux.launcherScript, contains('/bin/foo" "\$@"'));

      var windows = ReleasePackerDartBuildCli(
        'bin/foo.dart',
        args: ['--target-os', 'windows'],
      );
      expect(windows.targetsWindows, isTrue);
      expect(
        windows.executablePath,
        equals('build/cli/foo/bundle/bin/foo.exe'),
      );
      expect(windows.launcherPath, equals('build/cli/foo/bundle/foo.cmd'));
      expect(windows.launcherScript, contains(r'"%~dp0bin\foo.exe" %*'));

      var host = ReleasePackerDartBuildCli('bin/foo.dart');
      expect(host.targetsWindows, equals(Platform.isWindows));
    });

    test('writeLauncher', () {
      var tmpDir = Directory.systemTemp.createTempSync('dart-build-launcher--');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      var cmd = ReleasePackerDartBuildCli(
        'bin/foo.dart',
        args: ['--target-os=linux'],
        launcher: true,
      );
      Directory(
        pack_path.join(tmpDir.path, cmd.bundlePath),
      ).createSync(recursive: true);

      var file = cmd.writeLauncher(tmpDir);

      expect(file.readAsStringSync(), equals(cmd.launcherScript));
      if (Platform.isLinux || Platform.isMacOS) {
        expect(file.statSync().modeString(), contains('x'));
      }
    });
  });

  group('ReleasePackerFile (dart_build_*)', () {
    test('fromJson (with a mapping)', () {
      var file = ReleasePackerFile.fromJson({
        'build/cli/foo/bundle/': '/',
        'dart_build_cli': 'bin/foo.dart',
      });

      expect(file.sourcePath, equals('build/cli/foo/bundle/'));
      expect(file.destinyPath, equals(''));
      expect(file.hasCommandOfType<ReleasePackerDartBuildCli>(), isTrue);
    });

    test('fromJson (only dart_build_cli)', () {
      var file = ReleasePackerFile.fromJson({
        'dart_build_cli': 'bin/foo.dart',
        'platform': '^linux',
      });

      expect(file.sourcePath, equals('build/cli/foo/bundle/'));
      expect(file.destinyPath, equals(''));
      expect(file.matchesPlatform('linux-x64'), isTrue);
      expect(file.matchesPlatform('macos-arm64'), isFalse);
    });

    test('fromJson (dart_build_cli + windows_gui: true)', () {
      var file = ReleasePackerFile.fromJson({
        'dart_build_cli': {
          'target': 'bin/foo.dart',
          'args': ['--target-os=windows'],
        },
        'windows_gui': true,
      });

      var cmds = file.commands!;
      expect(cmds, hasLength(2));
      expect(cmds[0], isA<ReleasePackerDartBuildCli>());
      expect(cmds[1], isA<ReleasePackerWindowsSubsystemCommand>());
      expect(
        (cmds[1] as ReleasePackerWindowsSubsystemCommand).args,
        equals([
          '--windows-gui',
          'build/cli/foo/bundle/bin/foo.exe',
          'build/cli/foo/bundle/bin/foo.exe',
        ]),
      );
    });

    test('fromJson (no file path)', () {
      expect(
        () => ReleasePackerFile.fromJson({'platform': 'linux'}),
        throwsArgumentError,
      );
      expect(
        () => ReleasePackerFile.fromJson({'dart_build_foo': true}),
        throwsArgumentError,
      );
    });

    test('`./` destiny path', () {
      expect(ReleasePackerFile('a/', './').destinyPath, equals(''));
      expect(ReleasePackerFile('a/', '.').destinyPath, equals('a/'));
    });
  });

  group('ReleasePacker.mergeDuplicatedFiles', () {
    test('merges identical files', () async {
      var merged = await ReleasePacker.mergeDuplicatedFiles([
        ReleaseFile('lib/libfoo.so', [1, 2, 3]),
        ReleaseFile('bin/a', [1]),
        ReleaseFile('lib/libfoo.so', [1, 2, 3]),
      ]);

      expect(merged.map((e) => e.filePath), equals(['lib/libfoo.so', 'bin/a']));
    });

    test('different files with the same path', () async {
      await expectLater(
        ReleasePacker.mergeDuplicatedFiles([
          ReleaseFile('lib/libfoo.so', [1, 2, 3]),
          ReleaseFile('lib/libfoo.so', [3, 2, 1]),
        ]),
        throwsA(
          isA<ReleasePackerError>().having(
            (e) => e.message,
            'message',
            contains('lib/libfoo.so'),
          ),
        ),
      );
    });
  });

  group('build hooks', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-hooks--');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    void writePackages({required bool withHook}) {
      var hookDir = Directory(
        pack_path.join(tmpDir.path, 'packages', 'hooked', 'hook'),
      )..createSync(recursive: true);
      if (withHook) {
        File(pack_path.join(hookDir.path, 'build.dart')).writeAsStringSync('');
      }

      Directory(
        pack_path.join(tmpDir.path, 'packages', 'plain'),
      ).createSync(recursive: true);

      var dartTool = Directory(pack_path.join(tmpDir.path, '.dart_tool'))
        ..createSync();
      File(
        pack_path.join(dartTool.path, 'package_config.json'),
      ).writeAsStringSync(
        dart_convert.json.encode({
          'configVersion': 2,
          'packages': [
            {'name': 'hooked', 'rootUri': '../packages/hooked'},
            {
              'name': 'plain',
              'rootUri': Uri.directory(
                pack_path.join(tmpDir.path, 'packages', 'plain'),
              ).toString(),
            },
            {'name': 'app', 'rootUri': '../'},
          ],
        }),
      );
    }

    ReleasePacker packer(List<ReleasePackerFile> files) =>
        ReleasePacker('foo', SemanticVersioning.parse('1.0.0'), files);

    test('packagesWithBuildHooks', () {
      expect(ReleasePacker.packagesWithBuildHooks(tmpDir), isNull);

      writePackages(withHook: false);
      expect(ReleasePacker.packagesWithBuildHooks(tmpDir), isEmpty);

      writePackages(withHook: true);
      expect(ReleasePacker.packagesWithBuildHooks(tmpDir), equals(['hooked']));
    });

    test('packagesWithBuildHooks (invalid config)', () {
      var dartTool = Directory(pack_path.join(tmpDir.path, '.dart_tool'))
        ..createSync();
      var config = File(pack_path.join(dartTool.path, 'package_config.json'));

      config.writeAsStringSync('{');
      expect(ReleasePacker.packagesWithBuildHooks(tmpDir), isNull);

      config.writeAsStringSync('{"packages": 1}');
      expect(ReleasePacker.packagesWithBuildHooks(tmpDir), isNull);
    });

    test('checkBuildHooks: `dart compile exe` with hooks', () {
      writePackages(withHook: true);

      var p = packer([
        ReleasePackerFile.fromJson({
          'bin/foo.exe': 'foo',
          'dart_compile_exe': 'bin/foo.dart',
        }),
      ]);

      expect(
        () => p.checkBuildHooks(tmpDir),
        throwsA(
          isA<ReleasePackerError>()
              .having((e) => e.message, 'message', contains('hooked'))
              .having((e) => e.message, 'message', contains('dart_build_cli'))
              .having((e) => e.failedCommands, 'failedCommands', hasLength(1)),
        ),
      );

      // Not for another platform:
      var pWin = packer([
        ReleasePackerFile.fromJson({
          'bin/foo.exe': 'foo',
          'dart_compile_exe': 'bin/foo.dart',
          'platform': '^windows',
        }),
      ]);
      pWin.checkBuildHooks(tmpDir, platform: 'linux-x64');
    });

    test('checkBuildHooks: `dart compile exe` without hooks', () {
      writePackages(withHook: false);

      packer([
        ReleasePackerFile.fromJson({
          'bin/foo.exe': 'foo',
          'dart_compile_exe': 'bin/foo.dart',
        }),
      ]).checkBuildHooks(tmpDir);
    });

    test('checkBuildHooks: `dart build cli` and kernel with hooks', () {
      writePackages(withHook: true);

      packer([
        ReleasePackerFile.fromJson({'dart_build_cli': 'bin/foo.dart'}),
        ReleasePackerFile.fromJson({
          'bin/foo.dill': 'foo.dill',
          'dart_compile_kernel': 'bin/foo.dart',
        }),
      ]).checkBuildHooks(tmpDir);
    });

    test('buildFromDirectory: aborts before `prepare`', () async {
      writePackages(withHook: true);

      var prepare = ReleasePackerProcessCommand('__never_executed__');

      var p = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        [
          ReleasePackerFile.fromJson({
            'bin/foo.exe': 'foo',
            'dart_compile_exe': 'bin/foo.dart',
          }),
        ],
        prepareCommands: [prepare],
      );

      await expectLater(
        p.buildFromDirectory(rootDirectory: tmpDir),
        throwsA(isA<ReleasePackerError>()),
      );
    });
  });

  group('buildFromDirectory (dart build cli)', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-cli--');

      var projectFoo = Directory(
        pack_path.join(Directory.current.path, 'test', 'project-foo'),
      );
      File(
        pack_path.join(projectFoo.path, 'pubspec.yaml'),
      ).copySync(pack_path.join(tmpDir.path, 'pubspec.yaml'));
      Directory(pack_path.join(tmpDir.path, 'bin')).createSync();
      File(
        pack_path.join(projectFoo.path, 'bin', 'foo.dart'),
      ).copySync(pack_path.join(tmpDir.path, 'bin', 'foo.dart'));
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('bundle with launcher', () async {
      var packer = ReleasePacker.fromJson({
        'name': 'foo',
        'version': '1.2.3',
        'prepare': ['dart_pub_get'],
        'files': [
          {
            'dart_build_cli': {'target': 'bin/foo.dart', 'launcher': true},
          },
        ],
      });

      var bundle = await packer.buildFromDirectory(rootDirectory: tmpDir);

      var exeName = Platform.isWindows ? 'foo.exe' : 'foo';
      var launcherName = Platform.isWindows ? 'foo.cmd' : 'foo';

      var files = {for (var f in await bundle.files) f.filePath: f};

      expect(files.keys, containsAll(['bin/$exeName', launcherName]));
      expect(files.keys.where((p) => p.startsWith('build/')), isEmpty);

      if (!Platform.isWindows) {
        expect(files['bin/$exeName']!.executable, isTrue);
        expect(files[launcherName]!.executable, isTrue);

        var launcher = pack_path.join(
          tmpDir.path,
          'build',
          'cli',
          'foo',
          'bundle',
          launcherName,
        );
        var result = Process.runSync(launcher, []);
        expect(result.exitCode, equals(0));
        expect('${result.stdout}'.trim(), equals('Foo!'));
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
