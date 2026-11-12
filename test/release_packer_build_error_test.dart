@TestOn('vm')
import 'dart:async';
import 'dart:io';

import 'package:release_updater/release_packer.dart';
import 'package:release_updater/release_updater.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePackerCommandStatus', () {
    test('flags', () {
      expect(ReleasePackerCommandStatus.ok.isOK, isTrue);
      expect(ReleasePackerCommandStatus.ok.isSuccessful, isTrue);

      expect(ReleasePackerCommandStatus.ignored.isIgnored, isTrue);
      expect(ReleasePackerCommandStatus.ignored.isSuccessful, isTrue);
      expect(ReleasePackerCommandStatus.ignored.isError, isFalse);

      expect(ReleasePackerCommandStatus.error.isError, isTrue);
      expect(ReleasePackerCommandStatus.error.isSuccessful, isFalse);
    });
  });

  group('ReleasePackerError', () {
    test('defaults', () {
      var error = ReleasePackerError('some error');

      expect(error.message, equals('some error'));
      expect(error.failedCommands, isEmpty);
      expect(error.toString(), equals('ReleasePackerError: some error'));
    });
  });

  group('ReleasePackerCommand.executeCommands', () {
    late Directory tmpDir;
    late ReleasePacker packer;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-error--');

      packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('all commands OK', () async {
      var cmd1 = _FakeCommand(true);
      var cmd2 = _FakeCommand(true);

      var results = await ReleasePackerCommand.executeCommands(packer, [
        cmd1,
        cmd2,
      ], tmpDir);

      expect(results[cmd1], equals(ReleasePackerCommandStatus.ok));
      expect(results[cmd2], equals(ReleasePackerCommandStatus.ok));

      expect(cmd1.executed, isTrue);
      expect(cmd2.executed, isTrue);
    });

    test('a failed command aborts with an error', () async {
      var cmd1 = _FakeCommand(false);
      var cmd2 = _FakeCommand(true);

      await expectLater(
        ReleasePackerCommand.executeCommands(
          packer,
          [cmd1, cmd2],
          tmpDir,
          context: 'prepare',
        ),
        throwsA(
          isA<ReleasePackerError>()
              .having((e) => e.failedCommands, 'failedCommands', equals([cmd1]))
              .having((e) => e.message, 'message', contains('prepare')),
        ),
      );

      // The build is aborted at the 1st error,
      // the remaining commands are NOT executed:
      expect(cmd1.executed, isTrue);
      expect(cmd2.executed, isFalse);
    });

    test('an ignored command does NOT abort', () async {
      var cmd1 = _FakeCommand(
        false,
        status: ReleasePackerCommandStatus.ignored,
      );
      var cmd2 = _FakeCommand(true);

      var results = await ReleasePackerCommand.executeCommands(packer, [
        cmd1,
        cmd2,
      ], tmpDir);

      expect(results[cmd1], equals(ReleasePackerCommandStatus.ignored));
      expect(results[cmd2], equals(ReleasePackerCommandStatus.ok));
    });

    test('no commands', () async {
      expect(
        await ReleasePackerCommand.executeCommands(packer, null, tmpDir),
        isEmpty,
      );
      expect(
        await ReleasePackerCommand.executeCommands(
          packer,
          <ReleasePackerCommand>[],
          tmpDir,
        ),
        isEmpty,
      );
    });

    test('checkCommandsResults', () {
      expect(
        () => ReleasePackerCommand.checkCommandsResults({
          _FakeCommand(true): ReleasePackerCommandStatus.ok,
          _FakeCommand(true): ReleasePackerCommandStatus.ignored,
        }),
        returnsNormally,
      );

      expect(
        () => ReleasePackerCommand.checkCommandsResults({
          _FakeCommand(false): ReleasePackerCommandStatus.error,
        }),
        throwsA(isA<ReleasePackerError>()),
      );
    });
  });

  group('ReleasePackerCommandDelete', () {
    late Directory tmpDir;
    late ReleasePacker packer;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-rm--');

      packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('executeStatus (existing file)', () async {
      File('${tmpDir.path}/foo.out').writeAsStringSync('x');

      var cmd = ReleasePackerCommandDelete('foo.out');

      expect(
        await cmd.executeStatus(packer, tmpDir),
        equals(ReleasePackerCommandStatus.ok),
      );
    });

    test('executeStatus (missing file is ignored)', () async {
      var cmd = ReleasePackerCommandDelete('unknown.out');

      expect(
        await cmd.executeStatus(packer, tmpDir),
        equals(ReleasePackerCommandStatus.ignored),
      );
    });
  });

  group('ReleasePackerWindowsSubsystemCommand', () {
    late Directory tmpDir;
    late ReleasePacker packer;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-win-st--');

      packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('executeStatus (not a Windows executable is ignored)', () async {
      File('${tmpDir.path}/in.exe').writeAsStringSync('not an executable');

      var cmd = ReleasePackerWindowsSubsystemCommand(true, 'in.exe', 'in.exe');

      expect(cmd.isNotAWindowsExecutable(tmpDir), isTrue);

      expect(
        await cmd.executeStatus(packer, tmpDir),
        equals(ReleasePackerCommandStatus.ignored),
      );
    });

    test('executeStatus (missing input file is an error)', () async {
      var cmd = ReleasePackerWindowsSubsystemCommand(
        true,
        'missing.exe',
        'out.exe',
      );

      expect(cmd.isNotAWindowsExecutable(tmpDir), isFalse);

      expect(
        await cmd.executeStatus(packer, tmpDir),
        equals(ReleasePackerCommandStatus.error),
      );
    });
  });

  group('ReleasePacker.buildFromDirectory', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-build--');
      File('${tmpDir.path}/a.txt').writeAsStringSync('A');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('aborts on a `prepare` command error', () async {
      var failedCommand = _FakeCommand(false);

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[ReleasePackerFile('a.txt', 'a.txt')],
        prepareCommands: [failedCommand],
      );

      await expectLater(
        packer.buildFromDirectory(rootDirectory: tmpDir),
        throwsA(isA<ReleasePackerError>()),
      );
    });

    test('aborts on a file command error', () async {
      var failedCommand = _FakeCommand(false);

      var file = ReleasePackerFile('a.txt', 'a.txt');
      file.commands = [failedCommand];

      var packer = ReleasePacker('foo', SemanticVersioning.parse('1.0.0'), [
        file,
      ]);

      await expectLater(
        packer.buildFromDirectory(rootDirectory: tmpDir),
        throwsA(
          isA<ReleasePackerError>().having(
            (e) => e.message,
            'message',
            contains('a.txt'),
          ),
        ),
      );
    });

    test('aborts on a `finalize` command error', () async {
      var failedCommand = _FakeCommand(false);

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[ReleasePackerFile('a.txt', 'a.txt')],
        finalizeCommands: [failedCommand],
      );

      await expectLater(
        packer.buildFromDirectory(rootDirectory: tmpDir),
        throwsA(
          isA<ReleasePackerError>().having(
            (e) => e.message,
            'message',
            contains('finalize'),
          ),
        ),
      );
    });

    test('`finalize: false` skips the `finalize` commands', () async {
      // Would abort the build if executed:
      var finalizeCommand = _FakeCommand(false);

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[ReleasePackerFile('a.txt', 'a.txt')],
        finalizeCommands: [finalizeCommand],
      );

      var bundle = await packer.buildFromDirectory(
        rootDirectory: tmpDir,
        finalize: false,
      );

      expect(finalizeCommand.executed, isFalse);
      expect(
        (await bundle.files).map((f) => f.filePath).toList(),
        equals(['a.txt']),
      );
    });

    test('`finalize` (default) runs the `finalize` commands', () async {
      var finalizeCommand = _FakeCommand(true);

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[ReleasePackerFile('a.txt', 'a.txt')],
        finalizeCommands: [finalizeCommand],
      );

      await packer.buildFromDirectory(rootDirectory: tmpDir);

      expect(finalizeCommand.executed, isTrue);
    });

    test('`finalize: false` still checks the release', () async {
      // A Dart 3.14 Linux `dart build cli` bundle, shipping only `bin/app`:
      var bundle = '${tmpDir.path}/build/cli/app/bundle';
      File('$bundle/bin/app')
        ..createSync(recursive: true)
        ..writeAsStringSync('launcher');
      File('$bundle/lib/libdartaotapp.so')
        ..createSync(recursive: true)
        ..writeAsStringSync('program');

      var packer = ReleasePacker('foo', SemanticVersioning.parse('1.0.0'), [
        ReleasePackerFile('build/cli/app/bundle/bin/app', 'app'),
      ]);

      await expectLater(
        packer.buildFromDirectory(rootDirectory: tmpDir, finalize: false),
        throwsA(isA<ReleasePackerError>()),
      );
    });
  });

  // A `dart build cli` bundle as built by Dart 3.14 on Linux: `bin/<name>` is
  // only a launcher for `lib/libdartaot<name>.so`.
  group('ReleasePacker.checkDartBuildCliLibraries', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-aot-lib--');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    /// Writes a fake bundle at `build/cli/<name>/bundle/`, with the program
    /// library (`lib/libdartaot<name>.so`) if [programLibrary].
    void writeBundle(String name, {bool programLibrary = true}) {
      var bundle = '${tmpDir.path}/build/cli/$name/bundle';
      File('$bundle/bin/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('launcher');
      File('$bundle/lib/libsqlite3.so')
        ..createSync(recursive: true)
        ..writeAsStringSync('sqlite3');
      if (programLibrary) {
        File(
          '$bundle/lib/libdartaot$name.so',
        ).writeAsStringSync('program $name');
      }
    }

    Future<List<String>> buildPaths(List<ReleasePackerFile> files) async {
      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        files,
      );
      var bundle = await packer.buildFromDirectory(rootDirectory: tmpDir);
      return (await bundle.files).map((f) => f.filePath).toList()..sort();
    }

    Matcher throwsMissingLibrary(String library) => throwsA(
      isA<ReleasePackerError>().having(
        (e) => e.message,
        'message',
        allOf(contains(library), contains('dart build cli')),
      ),
    );

    test('only `bin/<name>`: aborts', () async {
      writeBundle('app');

      await expectLater(
        buildPaths([ReleasePackerFile('build/cli/app/bundle/bin/app', 'app')]),
        throwsMissingLibrary('libdartaotapp.so'),
      );
    });

    test('`bin/<name>` and `lib/` mapped apart: aborts', () async {
      writeBundle('app');

      // The executable at the root would load `../lib/`, outside the release:
      await expectLater(
        buildPaths([
          ReleasePackerFile('build/cli/app/bundle/bin/app', 'app'),
          ReleasePackerFile('build/cli/app/bundle/lib/', 'lib/'),
        ]),
        throwsMissingLibrary('libdartaotapp.so'),
      );
    });

    test('the whole bundle: OK', () async {
      writeBundle('app');

      expect(
        await buildPaths([ReleasePackerFile('build/cli/app/bundle/', '/')]),
        equals(['bin/app', 'lib/libdartaotapp.so', 'lib/libsqlite3.so']),
      );
    });

    test('two bundles at the release root: OK', () async {
      writeBundle('app');
      writeBundle('other');

      expect(
        await buildPaths([
          ReleasePackerFile('build/cli/app/bundle/', '/'),
          ReleasePackerFile('build/cli/other/bundle/', '/'),
        ]),
        equals([
          'bin/app',
          'bin/other',
          'lib/libdartaotapp.so',
          'lib/libdartaotother.so',
          'lib/libsqlite3.so',
        ]),
      );
    });

    test('a different program library: aborts', () async {
      writeBundle('app');
      File(
        '${tmpDir.path}/other-libdartaotapp.so',
      ).writeAsStringSync('another program');

      await expectLater(
        buildPaths([
          ReleasePackerFile('build/cli/app/bundle/bin/', 'bin/'),
          ReleasePackerFile('other-libdartaotapp.so', 'lib/libdartaotapp.so'),
        ]),
        throwsMissingLibrary('a different'),
      );
    });

    test('a self-contained executable (macOS, Dart < 3.14): OK', () async {
      writeBundle('app', programLibrary: false);

      expect(
        await buildPaths([
          ReleasePackerFile('build/cli/app/bundle/bin/app', 'app'),
        ]),
        equals(['app']),
      );
    });

    test('dartBuildCliProgramLibrary', () {
      writeBundle('app');
      var bundle = '${tmpDir.path}/build/cli/app/bundle';

      expect(
        ReleasePacker.dartBuildCliProgramLibrary(File('$bundle/bin/app'))?.path,
        endsWith('libdartaotapp.so'),
      );

      // `.exe` (Windows) has the same name:
      File('$bundle/bin/app.exe').writeAsStringSync('launcher');
      expect(
        ReleasePacker.dartBuildCliProgramLibrary(
          File('$bundle/bin/app.exe'),
        )?.path,
        endsWith('libdartaotapp.so'),
      );

      // Not in a `bundle/bin/`:
      expect(
        ReleasePacker.dartBuildCliProgramLibrary(
          File('$bundle/lib/libsqlite3.so'),
        ),
        isNull,
      );

      // Another name, without a program library:
      File('$bundle/bin/tool').writeAsStringSync('tool');
      expect(
        ReleasePacker.dartBuildCliProgramLibrary(File('$bundle/bin/tool')),
        isNull,
      );
    });
  });
}

/// A [ReleasePackerCommand] with a fixed result, to test the build abort.
class _FakeCommand extends ReleasePackerCommand {
  final bool result;

  final ReleasePackerCommandStatus? status;

  bool executed = false;

  _FakeCommand(this.result, {this.status});

  @override
  FutureOr<bool> execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) {
    executed = true;
    return result;
  }

  @override
  FutureOr<ReleasePackerCommandStatus> executeStatus(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) {
    var status = this.status;
    if (status != null) {
      executed = true;
      return status;
    }

    return super.executeStatus(
      releasePacker,
      rootDirectory,
      releaseBundle: releaseBundle,
    );
  }

  @override
  String toString() => '_FakeCommand[$result]';
}
