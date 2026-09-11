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
