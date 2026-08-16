@TestOn('vm')
import 'dart:io';

import 'package:release_updater/release_packer.dart';
import 'package:release_updater/release_updater.dart';
import 'package:release_updater/release_utility.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePackerWindowsSubsystemCommand', () {
    late Directory tmpDir;
    late ReleasePacker packer;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-win--');

      packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    File copyTestExe(String name) {
      var filePath = 'project-foo/bin/foo-windows64.exe';
      var filePossiblePaths = [filePath, 'test/$filePath', '../test/$filePath'];

      var exeFile = filePossiblePaths
          .map((p) => File(p))
          .firstWhere((f) => f.existsSync());

      var file = File('${tmpDir.path}/$name');
      exeFile.copySync(file.path);
      return file;
    }

    test('fromList', () {
      var cmd = ReleasePackerWindowsSubsystemCommand.fromList([
        'release_utility',
        '--windows-gui',
        'in.exe',
        'out.exe',
      ]);

      expect(cmd.args, equals(['--windows-gui', 'in.exe', 'out.exe']));

      var console = ReleasePackerWindowsSubsystemCommand.fromList([
        '--windows-console',
        'in.exe',
      ]);

      expect(console.args, equals(['--windows-console', 'in.exe', 'in.exe']));
    });

    test('from (inline String)', () {
      var cmd = ReleasePackerWindowsSubsystemCommand.from(
        'release_utility --windows-gui in.exe out.exe',
      );

      expect(cmd.args, equals(['--windows-gui', 'in.exe', 'out.exe']));
      expect(cmd.toString(), contains('release_utility'));
    });

    test('execute (missing input file)', () {
      var cmd = ReleasePackerWindowsSubsystemCommand(
        true,
        'missing.exe',
        'out.exe',
      );

      expect(cmd.execute(packer, tmpDir), isFalse);
    });

    test("execute (can't overwrite the output file)", () {
      copyTestExe('in.exe');
      File('${tmpDir.path}/out.exe').writeAsStringSync('x');

      var cmd = ReleasePackerWindowsSubsystemCommand(true, 'in.exe', 'out.exe');

      expect(cmd.execute(packer, tmpDir), isFalse);
    });

    test('execute (not a Windows executable)', () {
      File('${tmpDir.path}/in.exe').writeAsStringSync('not an executable');

      var cmd = ReleasePackerWindowsSubsystemCommand(true, 'in.exe', 'out.exe');

      expect(cmd.execute(packer, tmpDir), isFalse);
      expect(File('${tmpDir.path}/out.exe').existsSync(), isFalse);
    });

    test('execute (to a new output file)', () {
      var inFile = copyTestExe('in.exe');

      var cmd = ReleasePackerWindowsSubsystemCommand(true, 'in.exe', 'out.exe');

      expect(cmd.execute(packer, tmpDir), isTrue);

      var outFile = File('${tmpDir.path}/out.exe');

      expect(outFile.existsSync(), isTrue);
      expect(outFile.lengthSync(), equals(inFile.lengthSync()));

      // The output is a `GUI` executable and the input is unchanged:
      expect(WindowsPEFile(outFile).readWindowsSubsystem(), equals(2));
      expect(WindowsPEFile(inFile).readWindowsSubsystem(), equals(3));
    });

    test('execute (in place)', () {
      var inFile = copyTestExe('in.exe');
      var originalLength = inFile.lengthSync();

      var cmd = ReleasePackerWindowsSubsystemCommand(true, 'in.exe', 'in.exe');

      expect(cmd.execute(packer, tmpDir), isTrue);

      expect(inFile.lengthSync(), equals(originalLength));
      expect(WindowsPEFile(inFile).readWindowsSubsystem(), equals(2));

      // No copy is left behind:
      expect(File('${tmpDir.path}/in-copy1.exe').existsSync(), isFalse);

      // Back to `console`:
      var cmdConsole = ReleasePackerWindowsSubsystemCommand(
        false,
        'in.exe',
        'in.exe',
      );

      expect(cmdConsole.execute(packer, tmpDir), isTrue);
      expect(WindowsPEFile(inFile).readWindowsSubsystem(), equals(3));
    });

    test('execute (ambiguous parameters)', () {
      copyTestExe('in.exe');

      var cmd = ReleasePackerProcessCommandArgs([
        '--windows-gui',
        '--windows-console',
        'in.exe',
        'out.exe',
      ]);

      expect(cmd.execute(packer, tmpDir), isFalse);
    });

    test('execute (without a subsystem parameter)', () {
      copyTestExe('in.exe');

      var cmd = ReleasePackerProcessCommandArgs(['in.exe', 'out.exe']);

      expect(cmd.execute(packer, tmpDir), isFalse);
    });
  });
}

/// A [ReleasePackerWindowsSubsystemCommand] with custom [args],
/// to test invalid argument combinations.
class ReleasePackerProcessCommandArgs
    extends ReleasePackerWindowsSubsystemCommand {
  ReleasePackerProcessCommandArgs(List<String> args)
    : super(true, args[args.length - 2], args.last) {
    this.args.clear();
    this.args.addAll(args);
  }
}
