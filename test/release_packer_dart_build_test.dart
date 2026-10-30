@TestOn('vm')
import 'dart:async';
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

    test('output: normalized, inside the root directory', () {
      expect(
        ReleasePackerDartBuildCli('bin/foo.dart', output: './out//x/').output,
        equals('out/x'),
      );
      expect(
        ReleasePackerDartBuildCli('bin/foo.dart', output: r'out\x').bundlePath,
        equals('out/x/bundle'),
      );

      for (var output in [
        '/abs/out',
        r'C:\out',
        '.',
        '..',
        '../out',
        'a/../..',
      ]) {
        expect(
          () => ReleasePackerDartBuildCli('bin/foo.dart', output: output),
          throwsArgumentError,
          reason: output,
        );
      }
    });

    test('args: no target/output', () {
      for (var arg in [
        '-o',
        '-odist',
        '--output',
        '--output=dist',
        '-t',
        '--target',
        '--target=bin/x.dart',
      ]) {
        expect(
          () => ReleasePackerDartBuildCli('bin/foo.dart', args: [arg, 'x']),
          throwsArgumentError,
          reason: arg,
        );
      }

      // Not reserved:
      ReleasePackerDartBuildCli(
        'bin/foo.dart',
        args: ['--target-os=linux', '--target-arch', 'x64'],
      );
    });

    test('Map (2 `dart_build_*` in a command entry)', () {
      expect(
        () => ReleasePackerCommand.from({
          'dart_build_cli': 'bin/a.dart',
          'dart_build_foo': true,
        }),
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

    test('ReleasePacker.fromFile: not a Map', () {
      var tmpDir = Directory.systemTemp.createTempSync('release-packer-cfg--');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      var file = File(pack_path.join(tmpDir.path, 'release_packer.json'))
        ..writeAsStringSync('[1, 2]');

      expect(() => ReleasePacker.fromFile(file), throwsStateError);
    });

    test('ReleasePacker.fromJson with properties/env (the CLI)', () {
      // `release_packer ... --allow-env` resolves the properties of the
      // whole JSON: `bool` values were turned into `null`.
      for (var allowEnv in [true, false]) {
        var packer = ReleasePacker.fromJson(
          {
            'name': 'foo',
            'prepare': [
              {'dart_pub_get': true},
            ],
            'files': [
              {
                'dart_build_cli': {
                  'target': '%TARGET%',
                  'launcher': true,
                  'args': ['--target-os=windows'],
                },
                'windows_gui': true,
              },
            ],
          },
          properties: {'TARGET': 'bin/foo.dart'},
          allowPropertiesFromEnv: allowEnv,
        );

        expect(
          packer.prepareCommands!.single,
          isA<ReleasePackerDartPubGet>(),
          reason: 'allowEnv: $allowEnv',
        );

        var cmds = packer.files.single.commands!;
        var cli = cmds[0] as ReleasePackerDartBuildCli;
        expect(cli.target, equals('bin/foo.dart'));
        expect(cli.launcher, isTrue, reason: 'allowEnv: $allowEnv');
        expect(cmds[1], isA<ReleasePackerWindowsSubsystemCommand>());
      }
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

    test('keeps the executable flag of any copy', () async {
      var time = DateTime.utc(2026, 1, 2);

      var merged = await ReleasePacker.mergeDuplicatedFiles([
        ReleaseFile('bin/a', [1, 2], time: time),
        ReleaseFile('bin/a', [1, 2], executable: true),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.executable, isTrue);
      expect(merged.single.time, equals(time));
      expect(await merged.single.data, equals([1, 2]));
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

    test('packagesWithBuildHooks: only the runtime dependencies', () {
      writePackages(withHook: true);

      var graphFile = File(
        pack_path.join(tmpDir.path, '.dart_tool', 'package_graph.json'),
      );

      void writeGraph({required bool devOnly}) => graphFile.writeAsStringSync(
        dart_convert.json.encode({
          'roots': ['app'],
          'packages': [
            {
              'name': 'app',
              'dependencies': devOnly ? ['plain'] : ['plain', 'hooked'],
              'devDependencies': devOnly ? ['hooked'] : <String>[],
            },
            {'name': 'plain', 'dependencies': <String>[]},
            {'name': 'hooked', 'dependencies': <String>[]},
          ],
        }),
      );

      // A dev dependency with hooks is fine for `dart compile exe`:
      writeGraph(devOnly: true);
      expect(ReleasePacker.packagesWithBuildHooks(tmpDir), isEmpty);

      writeGraph(devOnly: false);
      expect(ReleasePacker.packagesWithBuildHooks(tmpDir), equals(['hooked']));

      // An invalid graph: all the packages count.
      graphFile.writeAsStringSync('{"roots": 1}');
      expect(ReleasePacker.packagesWithBuildHooks(tmpDir), equals(['hooked']));
    });

    test('isPackageResolutionUpToDate', () {
      expect(ReleasePacker.isPackageResolutionUpToDate(tmpDir), isFalse);

      writePackages(withHook: true);
      var config = File(
        pack_path.join(tmpDir.path, '.dart_tool', 'package_config.json'),
      );
      var configTime = DateTime.utc(2026, 1, 1, 12);
      config.setLastModifiedSync(configTime);

      expect(ReleasePacker.isPackageResolutionUpToDate(tmpDir), isTrue);

      var lock = File(pack_path.join(tmpDir.path, 'pubspec.lock'))
        ..writeAsStringSync('')
        ..setLastModifiedSync(configTime.subtract(const Duration(hours: 1)));
      expect(ReleasePacker.isPackageResolutionUpToDate(tmpDir), isTrue);

      // A `pubspec.lock` newer than the resolution: stale.
      lock.setLastModifiedSync(configTime.add(const Duration(hours: 1)));
      expect(ReleasePacker.isPackageResolutionUpToDate(tmpDir), isFalse);
    });

    test(
      'buildFromDirectory: a stale resolution is checked after `prepare`',
      () async {
        writePackages(withHook: true);
        var config = File(
          pack_path.join(tmpDir.path, '.dart_tool', 'package_config.json'),
        );
        config.setLastModifiedSync(DateTime.utc(2026, 1, 1));
        File(pack_path.join(tmpDir.path, 'pubspec.yaml'))
          ..writeAsStringSync('name: app')
          ..setLastModifiedSync(DateTime.utc(2026, 1, 2));

        // `prepare` resolves again, without the hooks:
        var marker = File(pack_path.join(tmpDir.path, 'prepared.txt'));
        var p = ReleasePacker(
          'foo',
          SemanticVersioning.parse('1.0.0'),
          [
            ReleasePackerFile.fromJson({
              'bin/foo.exe': 'foo',
              'dart_compile_exe': 'bin/foo.dart',
            }),
          ],
          prepareCommands: [
            _MarkerCommand(marker),
            ReleasePackerCommandDelete('packages/hooked/hook/build.dart'),
          ],
        );

        // The `dart compile exe` itself fails (no `bin/foo.dart`), but only
        // after `prepare`:
        await expectLater(
          p.buildFromDirectory(rootDirectory: tmpDir),
          throwsA(
            isA<ReleasePackerError>().having(
              (e) => e.message,
              'message',
              isNot(contains('build hooks')),
            ),
          ),
        );

        expect(marker.existsSync(), isTrue);
      },
    );

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

      var p = packer([
        ReleasePackerFile.fromJson({'dart_build_cli': 'bin/foo.dart'}),
        ReleasePackerFile.fromJson({
          'bin/foo.dill': 'foo.dill',
          'dart_compile_kernel': 'bin/foo.dart',
        }),
      ]);

      List<String> output({required bool warnings}) {
        var lines = <String>[];
        runZoned(
          () => p.checkBuildHooks(tmpDir, warnings: warnings),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => lines.add(line),
          ),
        );
        return lines;
      }

      expect(output(warnings: true), [contains('dart compile kernel')]);
      expect(output(warnings: false), isEmpty);
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

    test('`release_packer` CLI with `--allow-env`', () async {
      File(
        pack_path.join(tmpDir.path, 'release_packer.json'),
      ).writeAsStringSync(
        dart_convert.json.encode({
          'name': 'foo',
          'version': '1.0.0',
          'prepare': ['dart_pub_get'],
          'files': [
            {
              'dart_build_cli': {'target': '%FOO_TARGET%', 'launcher': true},
            },
          ],
        }),
      );

      var releasesDir = pack_path.join(tmpDir.path, 'releases');

      var result = await Process.run(Platform.resolvedExecutable, [
        'run',
        pack_path.join(Directory.current.path, 'bin', 'release_packer.dart'),
        pack_path.join(tmpDir.path, 'release_packer.json'),
        'build',
        '.',
        releasesDir,
        '--allow-env',
        '-PFOO_TARGET=bin/foo.dart',
      ], workingDirectory: Directory.current.path);
      expect(result.exitCode, equals(0), reason: '${result.stdout}');

      var zip = Directory(releasesDir).listSync().whereType<File>().singleWhere(
        (f) => f.path.endsWith('.zip'),
      );

      var bundle = ReleaseBundleZip(
        Release.parse('foo/1.0.0'),
        zipBytes: zip.readAsBytesSync(),
      );
      var paths = (await bundle.files).map((e) => e.filePath).toSet();

      var exe = Platform.isWindows ? '.exe' : '';
      var launcher = Platform.isWindows ? 'foo.cmd' : 'foo';
      expect(paths, containsAll(['bin/foo$exe', launcher]));
    }, timeout: const Timeout(Duration(minutes: 3)));

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

        // Through symbolic links (absolute, and relative to another link),
        // from another directory:
        var linksDir = Directory(pack_path.join(tmpDir.path, 'links'))
          ..createSync();
        Link(pack_path.join(linksDir.path, 'foo-abs')).createSync(launcher);
        Link(pack_path.join(linksDir.path, 'foo-rel')).createSync('foo-abs');

        for (var link in ['foo-abs', 'foo-rel']) {
          var result = Process.runSync(
            pack_path.join(linksDir.path, link),
            [],
            workingDirectory: Directory.systemTemp.path,
          );
          expect(result.exitCode, equals(0), reason: '${result.stderr}');
          expect('${result.stdout}'.trim(), equals('Foo!'));
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a normalized `output` maps the bundle', () async {
      var packer = ReleasePacker.fromJson({
        'name': 'foo',
        'version': '1.2.3',
        'prepare': ['dart_pub_get'],
        'files': [
          {
            'dart_build_cli': {'target': 'bin/foo.dart', 'output': './out/x/'},
          },
        ],
      });

      var bundle = await packer.buildFromDirectory(rootDirectory: tmpDir);

      var exeName = Platform.isWindows ? 'foo.exe' : 'foo';
      expect(
        (await bundle.files).map((e) => e.filePath),
        contains('bin/$exeName'),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a directory tree: executable by the file extension', () async {
      var dist = Directory(pack_path.join(tmpDir.path, 'dist', 'bin'))
        ..createSync(recursive: true);
      // Without the executable permission (as on Windows):
      File(pack_path.join(dist.path, 'run.exe')).writeAsStringSync('exe');
      File(pack_path.join(dist.path, 'data.txt')).writeAsStringSync('txt');

      var packer = ReleasePacker('foo', SemanticVersioning.parse('1.0.0'), [
        ReleasePackerFile('dist/', '/'),
      ]);

      var bundle = await packer.buildFromDirectory(rootDirectory: tmpDir);
      var files = {for (var f in await bundle.files) f.filePath: f};

      expect(files.keys, unorderedEquals(['bin/run.exe', 'bin/data.txt']));
      expect(files['bin/run.exe']!.executable, isTrue);
      expect(files['bin/data.txt']!.executable, isFalse);
    });

    test('a single file mapped to the release root', () async {
      Directory(pack_path.join(tmpDir.path, 'docs')).createSync();
      File(
        pack_path.join(tmpDir.path, 'docs', 'note.txt'),
      ).writeAsStringSync('note');

      var packer = ReleasePacker('foo', SemanticVersioning.parse('1.0.0'), [
        ReleasePackerFile('docs/note.txt', '/'),
      ]);

      var bundle = await packer.buildFromDirectory(rootDirectory: tmpDir);

      expect((await bundle.files).map((e) => e.filePath), equals(['note.txt']));
    });
  });

  /// A real project with a dependency with build hooks (`hook/build.dart`),
  /// that `dart compile exe` does NOT support.
  group('build hooks (dart SDK)', () {
    late Directory tmpDir;
    late Directory appDir;

    setUpAll(() {
      tmpDir = Directory.systemTemp.createTempSync(
        'release-packer-hooks-sdk--',
      );

      void write(String path, String content) {
        var file = File(pack_path.joinAll([tmpDir.path, ...path.split('/')]));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      }

      write('hooked/pubspec.yaml', '''
name: hooked
publish_to: none
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  hooks: ^2.0.0
''');
      write('hooked/lib/hooked.dart', "const hooked = 'Hooked!';\n");
      write('hooked/hook/build.dart', '''
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {});
}
''');

      write('app/pubspec.yaml', '''
name: app
publish_to: none
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  hooked:
    path: ../hooked
''');
      write('app/bin/app.dart', '''
import 'package:hooked/hooked.dart';

void main() => print('app: \$hooked');
''');
      write('app/bin/app2.dart', '''
import 'package:hooked/hooked.dart';

void main() => print('app2: \$hooked');
''');

      appDir = Directory(pack_path.join(tmpDir.path, 'app'));

      var pubGet = Process.runSync('dart', [
        'pub',
        'get',
      ], workingDirectory: appDir.path);
      if (pubGet.exitCode != 0) {
        throw StateError('`dart pub get` error: ${pubGet.stderr}');
      }
    });

    tearDownAll(() => tmpDir.deleteSync(recursive: true));

    ReleasePacker packer(
      List<Object> files, {
      List<ReleasePackerCommand>? prepare,
    }) => ReleasePacker(
      'app',
      SemanticVersioning.parse('1.0.0'),
      files.map(ReleasePackerFile.fromJson).toList(),
      prepareCommands: prepare,
    );

    test('packagesWithBuildHooks', () {
      expect(ReleasePacker.packagesWithBuildHooks(appDir), equals(['hooked']));
    });

    test('`dart compile exe` fails with a hint', () {
      var output = <String>[];

      var ok = runZoned(
        () => ReleasePackerDartCompileExe(
          'bin/app.dart',
        ).execute(packer([]), appDir),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => output.add(line),
        ),
      );

      expect(ok, isFalse);
      expect(output.join('\n'), contains('use `dart_build_cli`'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('`dart_compile_exe` aborts before `prepare`', () async {
      var marker = File(pack_path.join(appDir.path, 'prepared.txt'));

      var p = packer(
        [
          {'bin/app.exe': 'app', 'dart_compile_exe': 'bin/app.dart'},
        ],
        prepare: [_MarkerCommand(marker)],
      );

      await expectLater(
        p.buildFromDirectory(rootDirectory: appDir),
        throwsA(
          isA<ReleasePackerError>().having(
            (e) => e.message,
            'message',
            allOf(contains('hooked'), contains('dart_build_cli')),
          ),
        ),
      );

      expect(marker.existsSync(), isFalse);
    });

    test('`dart_build_cli`: 2 targets with launchers', () async {
      var p = packer([
        {
          'dart_build_cli': {'target': 'bin/app.dart', 'launcher': true},
        },
        {
          'dart_build_cli': {'target': 'bin/app2.dart', 'launcher': true},
        },
      ]);

      var bundle = await p.buildFromDirectory(rootDirectory: appDir);

      var exe = Platform.isWindows ? '.exe' : '';
      var launcher = Platform.isWindows ? '.cmd' : '';

      var paths = (await bundle.files).map((e) => e.filePath).toSet();
      expect(
        paths,
        containsAll([
          'bin/app$exe',
          'bin/app2$exe',
          'app$launcher',
          'app2$launcher',
        ]),
      );

      if (!Platform.isWindows) {
        for (var name in ['app', 'app2']) {
          var result = Process.runSync(
            pack_path.join(appDir.path, 'build', 'cli', name, 'bundle', name),
            [],
          );
          expect(result.exitCode, equals(0));
          expect('${result.stdout}'.trim(), equals('$name: Hooked!'));
        }
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

/// A [ReleasePackerCommand] that creates a [marker] file when executed.
class _MarkerCommand extends ReleasePackerCommand {
  final File marker;

  _MarkerCommand(this.marker);

  @override
  bool execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) {
    marker.writeAsStringSync('prepared');
    return true;
  }

  @override
  String toString() => '_MarkerCommand[${marker.path}]';
}
